#!/bin/bash
# kmos Wi-Fi Connect
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

UI_RESET=""
UI_BOLD=""
UI_DIM=""
UI_HEADER=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""
SUCCESS_ICON="▸"
FINAL_SUCCESS_ICON="✔"
STEP_INDEX=0
STEP_TOTAL=4
NETWORK_NAMES=()
WIFI_HANDOFF_DIR="/run/kmos/wifi"

repeat_char() {
  local char="$1"
  local count="$2"
  local out=""

  while (( count > 0 )); do
    out+="$char"
    ((count--))
  done

  printf '%s' "$out"
}

init_ui() {
  if [[ -t 2 && "${TERM:-dumb}" != "dumb" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_DIM=$'\033[2m'
    UI_HEADER=$'\033[34m'
    UI_INFO=$'\033[37m'
    UI_SUCCESS=$'\033[32m'
    UI_WARN=$'\033[33m'
    UI_DANGER=$'\033[31m'
  fi

  if [[ "${TERM:-}" == "linux" || "${kmos_ASCII_UI:-0}" == "1" ]]; then
    SUCCESS_ICON=">"
    FINAL_SUCCESS_ICON="OK"
  fi
}

log() {
  printf '%s\n' "$*" >&2
}

info() {
  printf '%b%s%b\n' "${UI_INFO}${UI_BOLD}" "$*" "$UI_RESET" >&2
}

warn() {
  printf '%bWARNING:%b %s\n' "${UI_WARN}${UI_BOLD}" "$UI_RESET" "$*" >&2
}

success() {
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

final_success() {
  printf '\n%b%s%b %s\n\n' "$UI_SUCCESS" "$FINAL_SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

die() {
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

detail() {
  local key="$1"
  local value="$2"
  printf '  %b%-12s%b %s\n' "$UI_DIM" "$key" "$UI_RESET" "$value" >&2
}

progress_bar() {
  local current="$1"
  local total="$2"
  local width="${3:-28}"
  local filled=0
  local percent=0

  if (( total > 0 )); then
    filled=$(( current * width / total ))
    percent=$(( current * 100 / total ))
  fi

  printf '[%s%s] %3d%%' \
    "$(repeat_char "#" "$filled")" \
    "$(repeat_char "-" "$((width - filled))")" \
    "$percent"
}

advance_step() {
  local label="$1"
  local bar

  ((STEP_INDEX += 1))
  bar="$(progress_bar "$STEP_INDEX" "$STEP_TOTAL")"

  printf '\n%bStep %d/%d%b %s\n' "${UI_HEADER}${UI_BOLD}" "$STEP_INDEX" "$STEP_TOTAL" "$UI_RESET" "$label" >&2
  printf '  %s\n' "$bar" >&2
}

print_banner() {
  printf '\n' >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$(repeat_char "=" 20)" "$UI_RESET" >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "kmos Wi-Fi Connect" "$UI_RESET" >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$(repeat_char "=" 20)" "$UI_RESET" >&2
  log "Connect Arch ISO to Wi-Fi when ethernet is not available."
  #log "Then clone or pull kmos scripts from GitHub."
}

require_tools() {
  local missing=()
  local tools=(chmod ip iwctl mkdir rfkill ping sed timedatectl)
  local t

  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-}"
  local answer=""

  while true; do
    if [[ "$default" == "yes" ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-Y}"
    elif [[ "$default" == "no" ]]; then
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-N}"
    else
      read -r -p "$prompt [y/n]: " answer
    fi

    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

unblock_wireless() {
  rfkill unblock all >/dev/null 2>&1 || die "Could not unblock wireless devices."
}

detect_wireless_adapter() {
  local path=""
  local adapter=""

  for path in /sys/class/net/*; do
    [[ -e "$path" ]] || continue
    adapter="${path##*/}"
    [[ "$adapter" == "lo" ]] && continue
    if [[ -d "$path/wireless" ]]; then
      printf '%s\n' "$adapter"
      return 0
    fi
  done

  for path in /sys/class/net/wlan* /sys/class/net/wl*; do
    [[ -e "$path" ]] || continue
    adapter="${path##*/}"
    printf '%s\n' "$adapter"
    return 0
  done

  return 1
}

is_wireless_adapter() {
  local adapter="$1"

  [[ -n "$adapter" ]] || return 1
  [[ -d "/sys/class/net/$adapter" ]] || return 1
  [[ -d "/sys/class/net/$adapter/wireless" ]] || return 1
}

prompt_manual_adapter() {
  local adapter=""

  while true; do
    ip link >&2
    printf '\n' >&2
    read -r -p "Enter wireless device name [q to quit]: " adapter

    case "$adapter" in
      [Qq]) die "No valid wireless adapter selected." ;;
    esac

    if is_wireless_adapter "$adapter"; then
      printf '%s\n' "$adapter"
      return 0
    fi

    if [[ -d "/sys/class/net/$adapter" ]]; then
      warn "$adapter exists, but it does not look like a wireless adapter."
    else
      warn "$adapter was not found."
    fi

    ask_yes_no "Try another adapter?" "yes" || die "No valid wireless adapter selected."
  done
}

select_wireless_adapter() {
  local detected=""

  detected="$(detect_wireless_adapter || true)"

  if [[ -n "$detected" ]]; then
    detail "Detected" "$detected"
    if ask_yes_no "Use this wireless adapter?" "yes"; then
      if is_wireless_adapter "$detected"; then
        printf '%s\n' "$detected"
        return 0
      fi
      warn "$detected was detected by name, but it does not look like a wireless adapter."
    fi
  else
    warn "No wireless adapter was detected automatically."
  fi

  prompt_manual_adapter
}

scan_wifi_networks() {
  local adapter="$1"
  local output=""
  local line=""
  local ssid=""
  local duplicate=0
  local existing=""
  local index=1

  NETWORK_NAMES=()

  info "Scanning available Wi-Fi networks"
  if ! iwctl station "$adapter" scan; then
    warn "Wi-Fi scan failed. You can still enter the SSID manually."
    return 1
  fi

  sleep 2
  if ! output="$(iwctl station "$adapter" get-networks 2>&1)"; then
    printf '%s\n' "$output" >&2
    warn "Could not list Wi-Fi networks. You can still enter the SSID manually."
    return 1
  fi

  while IFS= read -r line; do
    line="$(printf '%s\n' "$line" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g; s/^[[:space:]>]+//; s/[[:space:]]+$//')"
    [[ -n "$line" ]] || continue
    [[ "$line" == "Available networks"* ]] && continue
    [[ "$line" == "Network name"* ]] && continue
    [[ "$line" == "Security"* ]] && continue
    [[ "$line" == --* ]] && continue

    ssid="$(printf '%s\n' "$line" | sed -E 's/[[:space:]]{2,}.*$//')"
    [[ -n "$ssid" ]] || continue

    duplicate=0
    for existing in "${NETWORK_NAMES[@]}"; do
      if [[ "$existing" == "$ssid" ]]; then
        duplicate=1
        break
      fi
    done
    (( duplicate == 0 )) && NETWORK_NAMES+=("$ssid")
  done <<< "$output"

  if [[ ${#NETWORK_NAMES[@]} -eq 0 ]]; then
    printf '%s\n' "$output" >&2
    warn "No Wi-Fi names could be parsed from the scan. You can enter the SSID manually."
    return 1
  fi

  info "Available Wi-Fi networks:"
  for ssid in "${NETWORK_NAMES[@]}"; do
    printf '  %d) %s\n' "$index" "$ssid" >&2
    ((index++))
  done
}

prompt_wifi_credentials() {
  local -n out_ssid="$1"
  local -n out_password="$2"
  local -n out_hidden="$3"
  local selected_ssid=""
  local wifi_password=""
  local choice=""

  printf '\n' >&2
  if [[ ${#NETWORK_NAMES[@]} -gt 0 ]]; then
    printf '  m) Manual or hidden network\n' >&2
    while true; do
      read -r -p "Select Wi-Fi network [1-${#NETWORK_NAMES[@]}/m]: " choice
      case "$choice" in
        [Mm])
          read -r -p "Wi-Fi SSID: " selected_ssid
          ask_yes_no "Is this a hidden network?" "no" && out_hidden=1 || out_hidden=0
          break
          ;;
        ''|*[!0-9]*)
          warn "Invalid selection."
          ;;
        *)
          if (( choice >= 1 && choice <= ${#NETWORK_NAMES[@]} )); then
            selected_ssid="${NETWORK_NAMES[$((choice - 1))]}"
            out_hidden=0
            break
          fi
          warn "Invalid selection."
          ;;
      esac
    done
  else
    read -r -p "Wi-Fi SSID: " selected_ssid
    ask_yes_no "Is this a hidden network?" "no" && out_hidden=1 || out_hidden=0
  fi

  [[ -n "$selected_ssid" ]] || die "SSID cannot be empty."
  success "Network name is $selected_ssid"

  read -r -s -p "Wi-Fi password: " wifi_password
  printf '\n' >&2
  [[ -n "$wifi_password" ]] || die "Password cannot be empty."

  out_ssid="$selected_ssid"
  out_password="$wifi_password"
}

connect_wifi() {
  local adapter="$1"
  local ssid_name="$2"
  local password="$3"
  local hidden_network="$4"

  info "Connecting to internet"
  if [[ "$hidden_network" == "1" ]]; then
    iwctl --passphrase "$password" station "$adapter" connect-hidden "$ssid_name"
  else
    iwctl --passphrase "$password" station "$adapter" connect "$ssid_name"
  fi
  sleep 2
  success "Connection command completed."
}

save_wifi_handoff() {
  local adapter="$1"
  local ssid_name="$2"
  local password="$3"
  local hidden_network="$4"

  mkdir -p "$WIFI_HANDOFF_DIR"
  chmod 700 "${WIFI_HANDOFF_DIR%/*}" "$WIFI_HANDOFF_DIR"
  printf '%s\n' "$adapter" > "$WIFI_HANDOFF_DIR/adapter"
  printf '%s\n' "$ssid_name" > "$WIFI_HANDOFF_DIR/ssid"
  printf '%s\n' "$password" > "$WIFI_HANDOFF_DIR/password"
  printf '%s\n' "$hidden_network" > "$WIFI_HANDOFF_DIR/hidden"
  chmod 600 "$WIFI_HANDOFF_DIR/adapter" "$WIFI_HANDOFF_DIR/ssid" "$WIFI_HANDOFF_DIR/password" "$WIFI_HANDOFF_DIR/hidden"
}

verify_internet() {
  info "Verifying internet connectivity"
  ping -c 3 km-robota.com || return 1
  sleep 1
  success "Internet connection verified."
}

print_next_commands() {
  local repo_url="https://github.com/kamilomelo/kmos.git"

  info "Next commands after network is ready:"
  printf '\n%s\n' "  git clone $repo_url" >&2
  printf '%s\n' "  cd kmos" >&2
  printf '%s\n\n' "  git pull --ff-only" >&2
}

main() {
  local adapter=""
  local ssid_name=""
  local password=""
  local hidden_network=0

  init_ui
  print_banner
  require_tools

  unblock_wireless

  advance_step "Selecting wireless adapter"
  adapter="$(select_wireless_adapter)"
  detail "Adapter" "$adapter"

  advance_step "Scanning Wi-Fi networks"
  scan_wifi_networks "$adapter" || true
  prompt_wifi_credentials ssid_name password hidden_network

  advance_step "Connecting to Wi-Fi"
  connect_wifi "$adapter" "$ssid_name" "$password" "$hidden_network"

  advance_step "Verifying internet access"
  verify_internet || die "Then go and fix it."
  save_wifi_handoff "$adapter" "$ssid_name" "$password" "$hidden_network"
  unset password
  printf '\n' >&2
  info "Updating system clock"
  timedatectl set-timezone Europe/Zurich
  timedatectl set-ntp true
  timedatectl status
  printf '\n' >&2
  #print_next_commands
  final_success "Wi-Fi setup complete."
}

main "$@"
