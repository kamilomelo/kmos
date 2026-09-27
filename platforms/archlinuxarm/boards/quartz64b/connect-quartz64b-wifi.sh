#!/usr/bin/env bash
# Configure an existing Arch Linux ARM iwd installation without needing Ethernet.
set -Eeuo pipefail
SCRIPT_DIR=$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=platforms/archlinuxarm/boards/quartz64b/wifi-profile.sh
source "$SCRIPT_DIR/wifi-profile.sh"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./connect-quartz64b-wifi.sh [--help]

Connect a detected Wi-Fi adapter using iwd and systemd-networkd, saving a
root-only WPA-Personal profile for later boots. Requires iwd already installed;
if it is absent and Ethernet is unavailable, use USB tethering or transfer
verified Arch Linux ARM packages before running this helper.
EOF
}

detect_wifi_adapter() {
  local interface
  for interface in /sys/class/net/*; do
    [[ -d "$interface/wireless" ]] || continue
    printf '%s\n' "${interface##*/}"
    return 0
  done
  return 1
}

configure_wifi_network() {
  local adapter=$1
  install -Dm0644 /dev/stdin /etc/iwd/main.conf <<'EOF'
[General]
EnableNetworkConfiguration=false
EOF
  install -Dm0644 /dev/stdin /etc/systemd/network/25-wifi-dhcp.network <<'EOF'
[Match]
Name=wl* wlan*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=600
EOF
  systemctl enable --now systemd-networkd.service systemd-resolved.service
  systemctl enable --now iwd.service
  networkctl reload
  networkctl reconfigure "$adapter" || true
}

main() {
  local adapter ssid passphrase hidden=no
  case "${1:-}" in
    -h|--help) usage; return ;;
    '') ;;
    *) die "Unknown argument: $1" ;;
  esac
  (($# == 0)) || die 'Unexpected arguments.'
  [[ $(uname -m) == aarch64 ]] || die 'This helper is for AArch64 boards.'
  if ((EUID != 0)); then
    command -v sudo >/dev/null 2>&1 || die 'Root access is required, but sudo is unavailable.'
    info 'Root access is needed to configure Wi-Fi; sudo will prompt for your password.'
    exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
  fi
  command -v iwctl >/dev/null 2>&1 || die 'iwd is not installed. Use USB tethering or transfer verified Arch Linux ARM packages first.'
  adapter=$(detect_wifi_adapter) || die 'No wireless interface found. Check your adapter and its firmware.'
  info "Detected Wi-Fi interface: $adapter"
  systemctl start iwd.service
  iwctl station "$adapter" scan || true
  iwctl station "$adapter" get-networks || true
  read -r -p 'Wi-Fi SSID: ' ssid
  [[ "$ssid" =~ ^[a-zA-Z0-9_\ -]{1,32}$ ]] || die 'SSID must be 1-32 ASCII letters, digits, spaces, underscores or hyphens.'
  read -r -s -p 'WPA passphrase: ' passphrase
  printf '\n' >&2
  [[ ${#passphrase} -ge 8 && ${#passphrase} -le 63 ]] || die 'WPA passphrase must be 8-63 characters.'
  read -r -p 'Hidden network? [y/N]: ' hidden
  case "$hidden" in
    [Yy]*) hidden=true ;;
    *) hidden=false ;;
  esac
  write_iwd_profile /var/lib/iwd "$ssid" "$passphrase" "$hidden" || die 'Invalid credentials or an existing Wi-Fi profile; no profile was overwritten.'
  unset passphrase
  configure_wifi_network "$adapter"
  iwctl station "$adapter" connect "$ssid" || die 'Wi-Fi association failed. The saved profile remains for inspection.'
  info 'Wi-Fi profile saved with root-only permissions. Check networkctl status and reboot persistence before provisioning.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
