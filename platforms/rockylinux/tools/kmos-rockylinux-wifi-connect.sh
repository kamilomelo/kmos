#!/bin/bash
# kmos Rocky Wi-Fi Connect
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

NETWORK_NAMES=()

UI_RESET=""
UI_BOLD=""
UI_INFO=""
UI_WARN=""
UI_DANGER=""

init_ui() {
  if [[ -t 2 && "${TERM:-dumb}" != "dumb" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_INFO=$'\033[37m'
    UI_WARN=$'\033[33m'
    UI_DANGER=$'\033[31m'
  fi
}

info() {
  printf '%b%s%b\n' "${UI_INFO}${UI_BOLD}" "$*" "$UI_RESET" >&2
}

warn() {
  printf '%bWARNING:%b %s\n' "${UI_WARN}${UI_BOLD}" "$UI_RESET" "$*" >&2
}

die() {
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Run this script as root."
}

require_tools() {
  local missing=()
  local tools=(nmcli ping rfkill systemctl rpm)
  local t

  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done

  [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}

require_wifi_stack() {
  local missing=()

  rpm -q NetworkManager-wifi >/dev/null 2>&1 || missing+=("NetworkManager-wifi")
  rpm -q wpa_supplicant >/dev/null 2>&1 || missing+=("wpa_supplicant")

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing Wi-Fi packages: ${missing[*]}. Connect with ethernet first and rerun kmos so it can prepare the Rocky Wi-Fi stack."
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

ask_text() {
  local prompt="$1"
  local answer=""

  while true; do
    read -r -p "$prompt: " answer
    [[ -n "$answer" ]] && break
  done

  printf '%s\n' "$answer"
}

pick_wifi_adapter() {
  local adapter=""

  adapter="$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')"
  [[ -n "$adapter" ]] || die "No Wi-Fi adapter detected by NetworkManager."
  printf '%s\n' "$adapter"
}

has_internet() {
  ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1
}

show_networks() {
  local adapter="$1"

  nmcli --fields IN-USE,SSID,SIGNAL,SECURITY device wifi list ifname "$adapter" >&2 || true
}

wifi_scan_has_results() {
  local adapter="$1"

  nmcli -t -f SSID device wifi list ifname "$adapter" 2>/dev/null | grep -q '.'
}

collect_network_names() {
  local adapter="$1"
  local output=""
  local ssid=""
  local existing=""
  local duplicate=0
  local index=1

  NETWORK_NAMES=()
  output="$(nmcli -t -f SSID device wifi list ifname "$adapter" 2>/dev/null || true)"

  while IFS= read -r ssid; do
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
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
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
  info "Network name is $selected_ssid"

  read -r -s -p "Wi-Fi password: " wifi_password
  printf '\n' >&2
  [[ -n "$wifi_password" ]] || die "Password cannot be empty."

  out_ssid="$selected_ssid"
  out_password="$wifi_password"
}

main() {
  local adapter=""
  local ssid=""
  local password=""
  local hidden=0

  init_ui
  require_root
  require_tools
  require_wifi_stack

  systemctl enable --now NetworkManager >/dev/null 2>&1 || die "Could not start NetworkManager."
  rfkill unblock all >/dev/null 2>&1 || die "Could not unblock wireless devices."
  nmcli radio wifi on >/dev/null 2>&1 || true

  adapter="$(pick_wifi_adapter)"
  info "Using Wi-Fi adapter: $adapter"

  nmcli device set "$adapter" managed yes >/dev/null 2>&1 || true
  nmcli device disconnect "$adapter" >/dev/null 2>&1 || true

  info "Scanning Wi-Fi networks..."
  nmcli device wifi rescan ifname "$adapter" >/dev/null 2>&1 || true
  sleep 3

  printf '\nAvailable networks:\n' >&2
  show_networks "$adapter"
  printf '\n' >&2
  collect_network_names "$adapter" || true

  if ! wifi_scan_has_results "$adapter"; then
    warn "No Wi-Fi networks were detected."
    if ask_yes_no "Restart NetworkManager and rescan once more?" "yes"; then
      systemctl restart NetworkManager || die "Could not restart NetworkManager."
      sleep 3
      rfkill unblock all >/dev/null 2>&1 || true
      nmcli radio wifi on >/dev/null 2>&1 || true
      nmcli device wifi rescan ifname "$adapter" >/dev/null 2>&1 || true
      sleep 3
      printf '\nAvailable networks after restart:\n' >&2
      show_networks "$adapter"
      printf '\n' >&2
      collect_network_names "$adapter" || true
    fi
  fi

  prompt_wifi_credentials ssid password hidden

  if (( hidden == 1 )); then
    nmcli device wifi connect "$ssid" password "$password" hidden yes ifname "$adapter" || die "Wi-Fi connection failed."
  else
    nmcli device wifi connect "$ssid" password "$password" ifname "$adapter" || die "Wi-Fi connection failed."
  fi

  has_internet || die "Wi-Fi connected, but internet access is still unavailable."
  info "Wi-Fi connected and internet access is working."
}

main "$@"
