#!/usr/bin/env bash
# Separate, Ethernet-assisted wpa_supplicant trial; not part of provisioning.
set -Eeuo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh
source "$SCRIPT_DIR/connect-quartz64b-wifi.sh"

usage() {
  cat <<'EOF'
Usage: ./try-quartz64b-wpa-wifi.sh [--check|--help]

Run from the Quartz64 local console with Ethernet connected. Installs the ARM
wpa_supplicant package if needed (after asking before a full system update),
then switches Wi-Fi from iwd to wpa_supplicant. It does not rerun provisioning.
After a reboot, run with --check to verify Wi-Fi association, DHCP, route,
internet over Wi-Fi, and that iwd is not enabled or running. --check does not
change the network configuration or need Ethernet.
EOF
}

ethernet_ready() {
  local wifi=$1 route dev
  route=$(ip -4 route get 1.1.1.1) || return 1
  [[ $route =~ [[:space:]]dev[[:space:]]([^[:space:]]+) ]] || return 1
  dev=${BASH_REMATCH[1]}
  [[ "$dev" != "$wifi" && ! -d "/sys/class/net/$dev/wireless" ]] || return 1
  ping -I "$dev" -c 1 -W 3 1.1.1.1 >/dev/null
}

ensure_wpa_package() {
  local wifi=$1 answer
  if pacman -Q wpa_supplicant >/dev/null 2>&1; then
    return 0
  fi
  ethernet_ready "$wifi" || die 'No working Ethernet route. Connect Ethernet before installing wpa_supplicant.'
  info 'Installing wpa_supplicant requires a full Arch Linux ARM update; this may update the kernel.'
  read -r -p 'Continue with pacman -Syu wpa_supplicant? [y/N]: ' answer
  [[ "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]] || die 'Cancelled; Wi-Fi configuration was not changed.'
  pacman -Syu --needed wpa_supplicant
  pacman -Q wpa_supplicant >/dev/null || die 'wpa_supplicant installation did not complete.'
}

verify_wpa_after_boot() {
  local wifi=$1 status ssid
  if systemctl is-active --quiet iwd.service || systemctl is-enabled --quiet iwd.service; then
    die 'iwd is still active or enabled; two Wi-Fi backends must not compete.'
  fi
  status=$(wpa_cli -i "$wifi" status) || die "wpa_supplicant has no status for $wifi."
  ssid=$(sed -n 's/^ssid=//p' <<< "$status" | head -n 1)
  [[ -n "$ssid" ]] || die 'wpa_supplicant is not associated with a Wi-Fi network.'
  wpa_connection_ready "$wifi" "$ssid" "/etc/wpa_supplicant/wpa_supplicant-$wifi.conf" \
    || die "Wi-Fi post-boot check failed on $wifi (association, service, address, route or Wi-Fi internet)."
  info "Post-boot Wi-Fi check passed on $wifi: $ssid (iwd disabled)."
}

main() {
  local mode=${1:-start} wifi
  case "$mode" in
    --help|-h) usage; return 0 ;;
    start|--check) ;;
    *) die "Unknown argument: $mode" ;;
  esac
  (($# <= 1)) || die 'Unexpected arguments.'
  [[ $(uname -m) == aarch64 ]] || die 'This trial is for AArch64 boards.'
  if ((EUID != 0)); then
    command -v sudo >/dev/null 2>&1 || die 'Root access is required, but sudo is unavailable.'
    exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
  fi
  wifi=$(detect_wifi_adapter) || die 'No wireless adapter detected.'
  if [[ "$mode" == --check ]]; then
    verify_wpa_after_boot "$wifi"
    return
  fi
  [[ -z "${SSH_CONNECTION:-}" ]] || die 'Run this trial from the local console, not over SSH.'
  ethernet_ready "$wifi" || die 'Connect working Ethernet before switching Wi-Fi backends; it is needed for recovery.'
  ensure_wpa_package "$wifi"
  run_wpa_fallback "$wifi"
  verify_wpa_after_boot "$wifi"
  info 'Trial configured. Reboot, then run this script with --check before relying on Wi-Fi.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
