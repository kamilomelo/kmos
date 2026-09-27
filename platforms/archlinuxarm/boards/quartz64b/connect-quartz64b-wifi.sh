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
root-only WPA-Personal profile for later boots. If iwd is not installed, offer
to install the signed offline ARM packages staged during SD preparation.
Incorrect credentials can be retried without keeping the failed profile.
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

wifi_already_configured() {
  local adapter=$1
  systemctl is-active --quiet iwd.service || return 1
  systemctl is-enabled --quiet iwd.service || return 1
  ip -4 -o address show dev "$adapter" scope global | grep -q .
}

connect_wifi_with_retries() {
  local adapter=$1 state_dir=$2 ssid passphrase hidden answer profile backup_dir attempt
  while true; do
    read -r -p 'Wi-Fi SSID (or type CANCEL): ' ssid || return 1
    [[ "$ssid" != CANCEL ]] || return 1
    [[ "$ssid" =~ ^[a-zA-Z0-9_\ -]{1,32}$ ]] || { info 'SSID must be 1-32 ASCII letters, digits, spaces, underscores or hyphens.'; continue; }
    read -r -s -p 'WPA passphrase: ' passphrase || return 1
    printf '\n' >&2
    if ! validate_wifi_credentials "$ssid" "$passphrase"; then
      unset passphrase
      info 'WPA passphrase must be 8-63 characters.'
      continue
    fi
    read -r -p 'Hidden network? [y/N]: ' hidden || { unset passphrase; return 1; }
    case "$hidden" in [Yy]*) hidden=true ;; *) hidden=false ;; esac

    profile="$state_dir/$ssid.psk"
    backup_dir=""
    if [[ -e "$profile" || -L "$profile" ]]; then
      [[ -f "$profile" && ! -L "$profile" ]] || die "Refusing to replace a non-regular Wi-Fi profile: $profile"
      read -r -p "A profile for $ssid already exists. Back it up and replace it? [y/N]: " answer || { unset passphrase; return 1; }
      if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        unset passphrase
        info 'Existing profile kept. Choose another SSID or type CANCEL.'
        continue
      fi
      backup_dir=$(mktemp -d "$state_dir/.kmos-wifi-backup.XXXXXXXX") || die 'Could not create a private Wi-Fi profile backup.'
      cp -p -- "$profile" "$backup_dir/original.psk" || die "Could not back up $profile."
      rm -f -- "$profile"
    fi

    if ! write_iwd_profile "$state_dir" "$ssid" "$passphrase" "$hidden"; then
      unset passphrase
      if [[ -n "$backup_dir" ]]; then cp -p -- "$backup_dir/original.psk" "$profile"; fi
      die 'Could not write the Wi-Fi profile; any previous profile was restored.'
    fi
    unset passphrase
    if iwctl station "$adapter" connect "$ssid"; then
      for ((attempt=0; attempt<5; attempt++)); do
        if ip -4 -o address show dev "$adapter" scope global | grep -q .; then
          [[ -z "$backup_dir" ]] || info "Previous profile backed up at $backup_dir/original.psk"
          info 'Wi-Fi connected and DHCP assigned an IPv4 address; profile saved for future boots.'
          return 0
        fi
        sleep 2
      done
      [[ -z "$backup_dir" ]] || info "Previous profile backed up at $backup_dir/original.psk"
      info 'Wi-Fi associated, but DHCP has not assigned an IPv4 address yet. The profile was saved; check networkctl status.'
      return 0
    else
      info 'Wi-Fi connection failed; check the SSID and passphrase.'
    fi

    rm -f -- "$profile"
    if [[ -n "$backup_dir" ]]; then
      cp -p -- "$backup_dir/original.psk" "$profile" || die "Could not restore the previous profile from $backup_dir."
      rm -f -- "$backup_dir/original.psk"
      rmdir -- "$backup_dir"
      info 'Previous profile restored.'
    fi
    read -r -p 'Try Wi-Fi credentials again? [Y/n]: ' answer || return 1
    [[ ! "$answer" =~ ^[Nn]$ ]] || return 1
  done
}

main() {
  local adapter answer
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
  adapter=$(detect_wifi_adapter) || die 'No wireless interface found. Check your adapter and its firmware.'
  info "Detected Wi-Fi interface: $adapter"
  if ! command -v iwctl >/dev/null 2>&1; then
    local answer
    [[ -r "$SCRIPT_DIR/wifi-offline-packages.sh" && -d /var/lib/kmos/wifi-packages ]] \
      || die 'iwd is missing and no offline packages were staged. Use temporary networking to install the ARM iwd package.'
    read -r -p 'Install signed offline ARM ell and iwd packages now? [Y/n]: ' answer
    [[ ! "$answer" =~ ^[Nn]$ ]] || die 'Cancelled; Wi-Fi remains unconfigured.'
    (
      # shellcheck source=platforms/archlinuxarm/boards/quartz64b/wifi-offline-packages.sh
      source "$SCRIPT_DIR/wifi-offline-packages.sh"
      install_offline_wifi /var/lib/kmos/wifi-packages /var/lib/kmos/quartz64b-wifi-packages-installed
    )
    command -v iwctl >/dev/null 2>&1 || die 'iwd installation did not provide iwctl.'
  fi
  if wifi_already_configured "$adapter"; then
    read -r -p 'Wi-Fi is already active and persistent. Reconfiguring may interrupt it. Continue? [y/N]: ' answer
    [[ "$answer" =~ ^[Yy]$ ]] || { info 'Existing Wi-Fi connection kept.'; return 0; }
  fi
  systemctl start iwd.service
  iwctl station "$adapter" scan || true
  iwctl station "$adapter" get-networks || true
  configure_wifi_network "$adapter"
  connect_wifi_with_retries "$adapter" /var/lib/iwd || { info 'Wi-Fi setup cancelled; previously saved profiles were preserved.'; return 1; }
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
