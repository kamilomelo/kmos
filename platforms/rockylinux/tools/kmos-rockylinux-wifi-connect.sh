#!/bin/bash
# kmos Rocky Wi-Fi Connect
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

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

main() {
  local adapter=""
  local ssid=""
  local password=""

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
    fi
  fi

  ssid="$(ask_text 'SSID')"
  read -r -s -p "Password: " password
  printf '\n' >&2

  if ask_yes_no "Is this a hidden SSID?" "no"; then
    nmcli device wifi connect "$ssid" password "$password" hidden yes ifname "$adapter" || die "Wi-Fi connection failed."
  else
    nmcli device wifi connect "$ssid" password "$password" ifname "$adapter" || die "Wi-Fi connection failed."
  fi

  has_internet || die "Wi-Fi connected, but internet access is still unavailable."
  info "Wi-Fi connected and internet access is working."
}

main "$@"
