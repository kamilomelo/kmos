#!/bin/bash
# kmos Rocky Linux Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
WIFI_HELPER="$SCRIPT_DIR/tools/kmos-rockylinux-wifi-connect.sh"
STEP_INDEX=0
STEP_TOTAL=5
STATE_DIR="/var/lib/kmos/rockylinux"
REBOOT_MARKER="$STATE_DIR/reboot-required-after-update"
UPDATE_DONE_MARKER="$STATE_DIR/update-baseline-complete"

UI_RESET=""
UI_BOLD=""
UI_DIM=""
UI_HEADER=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""

repeat_char() {
  local char="$1"
  local count="$2"
  local out=""

  while ((count > 0)); do
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
  printf '%bOK%b %s\n' "$UI_SUCCESS" "$UI_RESET" "$*" >&2
}

die() {
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

advance_step() {
  local label="$1"

  ((STEP_INDEX += 1))
  printf '\n%bStep %d/%d%b %s\n' "${UI_HEADER}${UI_BOLD}" "$STEP_INDEX" "$STEP_TOTAL" "$UI_RESET" "$label" >&2
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
  local default="${2:-}"
  local answer=""

  read -r -p "$prompt${default:+ [$default]}: " answer
  if [[ -z "$answer" && -n "$default" ]]; then
    answer="$default"
  fi

  printf '%s\n' "$answer"
}

print_banner() {
  printf '\n' >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$(repeat_char "=" 24)" "$UI_RESET" >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "kmos Rocky Linux Install" "$UI_RESET" >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$(repeat_char "=" 24)" "$UI_RESET" >&2
  log "Initial Rocky Linux post-install scaffold for Rocky 10 minimal."
  log "This stage assumes Rocky is already installed and booted."
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Run this script as root."
}

require_tools() {
  local missing=()
  local tools=(dnf ping systemctl mkdir cat)
  local t

  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done

  [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}

detect_linux_id() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  printf '%s\n' "${ID:-}"
}

is_rocky() {
  [[ "$(detect_linux_id || true)" == "rocky" ]]
}

has_internet() {
  ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1
}

has_wifi_adapter() {
  local path=""

  for path in /sys/class/net/*; do
    [[ -e "$path" ]] || continue
    [[ -d "$path/wireless" ]] && return 0
  done

  return 1
}

has_wired_carrier() {
  local path=""
  local dev=""

  for path in /sys/class/net/*; do
    [[ -e "$path" ]] || continue
    dev="${path##*/}"
    [[ "$dev" == "lo" ]] && continue
    [[ -d "$path/wireless" ]] && continue
    if [[ -r "$path/carrier" ]] && [[ "$(cat "$path/carrier")" == "1" ]]; then
      return 0
    fi
  done

  return 1
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

ensure_network() {
  advance_step "Ensure network access"

  if has_internet; then
    success "Internet access is already available."
    return
  fi

  warn "No internet access detected."

  if has_wired_carrier; then
    die "A wired link is present, but internet is still unavailable. Fix the wired connection first."
  fi

  if [[ -x "$WIFI_HELPER" ]] && has_wifi_adapter; then
    if ask_yes_no "Run the Rocky Wi-Fi helper now?" "yes"; then
      bash "$WIFI_HELPER"
    fi
  fi

  has_internet || die "Internet is still unavailable. Connect Rocky to the network, then rerun kmos."
  success "Internet access confirmed."
}

update_system_baseline() {
  local current_boot_id=""
  local recorded_boot_id=""

  advance_step "Update Rocky baseline"
  ensure_state_dir
  current_boot_id="$(cat /proc/sys/kernel/random/boot_id)"

  if [[ -f "$REBOOT_MARKER" ]]; then
    recorded_boot_id="$(cat "$REBOOT_MARKER")"
    if [[ "$current_boot_id" == "$recorded_boot_id" ]]; then
      die "A full system update already ran. Reboot Rocky before continuing."
    fi

    rm -f "$REBOOT_MARKER"
    touch "$UPDATE_DONE_MARKER"
    success "Reboot after the baseline update confirmed."
    return
  fi

  if [[ -f "$UPDATE_DONE_MARKER" ]]; then
    success "Baseline update already completed. Skipping."
    return
  fi

  info "Running full system update before any NVIDIA or workstation tooling."
  dnf -y upgrade --refresh
  printf '%s\n' "$current_boot_id" > "$REBOOT_MARKER"
  warn "Baseline update completed. Reboot Rocky now, then rerun kmos to continue."
  exit 0
}

configure_swapfile() {
  local swap_size=""

  advance_step "Configure swapfile"

  if swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/swapfile'; then
    success "/swapfile is already active."
    return
  fi

  if grep -Eq '^[^#]+\s+none\s+swap\s' /etc/fstab 2>/dev/null; then
    warn "A swap entry already exists in /etc/fstab. Leaving swap configuration unchanged."
    return
  fi

  if [[ -e /swapfile ]]; then
    warn "/swapfile already exists, but it is not active."
    if ask_yes_no "Activate the existing /swapfile and keep it in /etc/fstab?" "yes"; then
      chmod 600 /swapfile
      mkswap /swapfile >/dev/null
      swapon /swapfile
      grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
      success "Existing /swapfile activated and persisted."
      return
    fi
    warn "Skipping swapfile changes."
    return
  fi

  if ! ask_yes_no "Create a swapfile now?" "yes"; then
    warn "Skipping swapfile creation."
    return
  fi

  swap_size="$(ask_text 'Enter swapfile size in GiB' '8')"
  [[ "$swap_size" =~ ^[0-9]+$ ]] || die "Swapfile size must be an integer number of GiB."
  (( swap_size > 0 )) || die "Swapfile size must be greater than zero."

  dd if=/dev/zero of=/swapfile bs=1M count=$((swap_size * 1024)) status=progress
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
  success "Created ${swap_size} GiB swapfile at /swapfile."
}

describe_scope() {
  advance_step "Describe current Rocky scope"
  info "Rocky support is now scaffolded for the post-install minimal workflow."
  log "Current scope:"
  log "  - assumes Rocky 10 minimal is already installed"
  log "  - assumes /boot/efi, /boot, and / only"
  log "  - creates swap as a swapfile instead of a swap partition"
  log "  - forces a full update and reboot boundary before NVIDIA or tooling"
  log "  - brings up Wi-Fi first when ethernet is not available"
  log "  - prepares the repo for the upcoming KDE and package stages"
}

next_steps() {
  advance_step "Next Rocky work"
  log "Next implementation step:"
  log "  - detect and install NVIDIA drivers, then verify with nvidia-smi"
  log "  - enable EPEL/required repositories for CLI tooling"
  log "  - install btop, fastfetch, starship, and zoxide"
  log "  - install KDE on top of Rocky minimal"
  log "  - add Rocky post-install desktop configuration stages"
}

main() {
  init_ui
  print_banner
  require_root
  require_tools
  is_rocky || die "This installer only supports Rocky Linux."
  ensure_network
  configure_swapfile
  update_system_baseline
  describe_scope
  next_steps
}

main "$@"
