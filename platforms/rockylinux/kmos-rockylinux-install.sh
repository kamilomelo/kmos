#!/bin/bash
# kmos Rocky Linux Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
WIFI_HELPER="$SCRIPT_DIR/tools/kmos-rockylinux-wifi-connect.sh"
STEP_INDEX=0
STEP_TOTAL=3

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
  local tools=(dnf ping systemctl)
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

describe_scope() {
  advance_step "Describe current Rocky scope"
  info "Rocky support is now scaffolded for the post-install minimal workflow."
  log "Current scope:"
  log "  - assumes Rocky 10 minimal is already installed"
  log "  - brings up Wi-Fi first when ethernet is not available"
  log "  - prepares the repo for the upcoming KDE and package stages"
}

next_steps() {
  advance_step "Next Rocky work"
  log "Next implementation step:"
  log "  - install KDE on top of Rocky minimal"
  log "  - add Rocky post-install package and desktop configuration stages"
}

main() {
  init_ui
  print_banner
  require_root
  require_tools
  is_rocky || die "This installer only supports Rocky Linux."
  ensure_network
  describe_scope
  next_steps
}

main "$@"
