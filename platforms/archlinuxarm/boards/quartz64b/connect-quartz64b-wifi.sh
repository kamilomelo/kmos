#!/usr/bin/env bash
# Configure an existing Arch Linux ARM iwd installation without needing Ethernet.
set -Eeuo pipefail
SCRIPT_DIR=$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=platforms/archlinuxarm/boards/quartz64b/wifi-profile.sh
source "$SCRIPT_DIR/wifi-profile.sh"
NETWORK_NAMES=()
WIFI_FAILURE_KIND=association

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./connect-quartz64b-wifi.sh [--help]

Connect a detected Wi-Fi adapter using iwd and systemd-networkd, saving a
root-only WPA-Personal profile for later boots. If iwd is not installed, offer
to install the signed offline ARM packages staged during SD preparation.
Incorrect credentials can be retried without keeping the failed profile.
Success requires the saved profile, Wi-Fi association, DHCP, and a Wi-Fi route.
Only a real reboot can verify that it reconnects on a later boot.
Type CANCEL to stop. During provisioning, you may then explicitly finish on
working Ethernet only; cancelling does not claim Wi-Fi was configured.
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

scan_wifi_networks() {
  local adapter=$1 output line name existing duplicate index=1
  NETWORK_NAMES=()
  if ! iwctl station "$adapter" scan; then
    info 'Wi-Fi scan failed. You may still enter an SSID manually.'
    return 1
  fi
  # iwd scans asynchronously; an immediate get-networks can show stale results.
  sleep 2
  if ! output=$(iwctl station "$adapter" get-networks 2>&1); then
    info 'Could not list Wi-Fi networks. You may still enter an SSID manually.'
    return 1
  fi
  while IFS= read -r line; do
    line=$(printf '%s\n' "$line" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g; s/^[[:space:]>]+//; s/[[:space:]]+$//')
    [[ -n "$line" && "$line" != 'Available networks'* && "$line" != 'Network name'* && "$line" != 'Security'* && "$line" != --* ]] || continue
    name=$(printf '%s\n' "$line" | sed -E 's/[[:space:]]{2,}.*$//')
    [[ -n "$name" ]] || continue
    duplicate=0
    for existing in "${NETWORK_NAMES[@]}"; do
      [[ "$existing" != "$name" ]] || { duplicate=1; break; }
    done
    ((duplicate == 1)) || NETWORK_NAMES+=("$name")
  done <<< "$output"
  if ((${#NETWORK_NAMES[@]} > 0)); then
    info 'Available Wi-Fi networks (choose a number, or enter an SSID):'
    for name in "${NETWORK_NAMES[@]}"; do
      printf '  %d) %s\n' "$index" "$name" >&2
      ((index++))
    done
  else
    printf '%s\n' "$output" >&2
    info 'No network names could be parsed; enter the SSID manually.'
  fi
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

connected_wifi_ssid() {
  local adapter=$1
  iwctl station "$adapter" show | awk '
    /^[[:space:]]*Connected network[[:space:]]+/ {
      sub(/^[[:space:]]*Connected network[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }'
}

wifi_connection_ready() {
  local adapter=$1 state_dir=$2 ssid=$3 profile service
  profile="$state_dir/$ssid.psk"
  [[ -f "$profile" && ! -L "$profile" ]] || return 1
  [[ $(stat -c %a -- "$profile") == 600 ]] || return 1
  grep -Fxq 'AutoConnect=true' "$profile" || return 1
  for service in iwd.service systemd-networkd.service systemd-resolved.service; do
    systemctl is-active --quiet "$service" || return 1
    systemctl is-enabled --quiet "$service" || return 1
  done
  [[ $(connected_wifi_ssid "$adapter") == "$ssid" ]] || return 1
  ip -4 -o address show dev "$adapter" scope global | grep -q . || return 1
  ip -4 route show default dev "$adapter" | grep -q .
}

wait_for_wifi() {
  local adapter=$1 state_dir=$2 ssid=$3 attempt
  for ((attempt=0; attempt<15; attempt++)); do
    wifi_connection_ready "$adapter" "$state_dir" "$ssid" && return 0
    sleep 2
  done
  return 1
}

reconnect_saved_wifi() {
  local adapter=$1 state_dir=$2 ssid=$3 current command=connect
  WIFI_FAILURE_KIND=association
  current=$(connected_wifi_ssid "$adapter") || true
  if [[ -n "$current" ]]; then
    [[ -z "${SSH_CONNECTION:-}" ]] || die 'Testing saved credentials requires restarting Wi-Fi. Run this helper from the local console, not over SSH.'
  fi
  info 'Restarting iwd to reload the saved profile and test reconnection; Ethernet is unaffected.'
  systemctl restart iwd.service || return 1
  # Restarting iwd clears its scan cache. Scan again before connecting, as in
  # the Arch ISO helper; otherwise iwctl can report "Invalid network name".
  scan_wifi_networks "$adapter" || true
  if grep -Fxq 'Hidden=true' "$state_dir/$ssid.psk"; then command=connect-hidden; fi
  # AutoConnect may already have associated while the scan was running.
  if ! iwctl station "$adapter" "$command" "$ssid"; then
    [[ $(connected_wifi_ssid "$adapter") == "$ssid" ]] || return 1
  fi
  if wait_for_wifi "$adapter" "$state_dir" "$ssid"; then return 0; fi
  if [[ $(connected_wifi_ssid "$adapter") == "$ssid" ]]; then
    WIFI_FAILURE_KIND=dhcp
  fi
  return 1
}

retry_wifi_dhcp() {
  local adapter=$1 state_dir=$2 ssid=$3 answer
  info "Associated with $ssid, but Wi-Fi DHCP/default route is not ready. The saved credentials will be kept."
  networkctl status "$adapter" --no-pager >&2 || true
  while true; do
    read -r -p 'Retry Wi-Fi DHCP [r] or CANCEL (offer Ethernet-only completion) [c]? [r]: ' answer || return 2
    [[ ! "$answer" =~ ^[Cc]$ ]] || return 2
    networkctl reconfigure "$adapter" || true
    networkctl renew "$adapter" || true
    if wait_for_wifi "$adapter" "$state_dir" "$ssid"; then
      info 'Wi-Fi DHCP address and route verified.'
      return 0
    fi
    info 'Wi-Fi DHCP/default route is still missing; no password change was made.'
  done
}

connect_wifi_with_retries() {
  local adapter=$1 state_dir=$2 ssid passphrase hidden answer profile backup_dir
  while true; do
    read -r -p 'Wi-Fi network number or SSID (or type CANCEL): ' ssid || return 2
    [[ "$ssid" != CANCEL ]] || return 2
    if [[ "$ssid" =~ ^[1-9][0-9]*$ ]] && ((ssid <= ${#NETWORK_NAMES[@]})); then
      ssid=${NETWORK_NAMES[$((ssid - 1))]}
      info "Selected network: $ssid"
    fi
    [[ "$ssid" =~ ^[a-zA-Z0-9_\ -]{1,32}$ ]] || { info 'SSID must be 1-32 ASCII letters, digits, spaces, underscores or hyphens.'; continue; }
    if [[ -n "${SSH_CONNECTION:-}" && -n $(connected_wifi_ssid "$adapter") ]]; then
      die 'Testing saved credentials requires restarting Wi-Fi. Run this helper from the local console, not over SSH.'
    fi
    profile="$state_dir/$ssid.psk"
    if [[ -f "$profile" && ! -L "$profile" ]]; then
      read -r -p "Try the existing saved profile for $ssid first? [Y/n]: " answer || return 2
      if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        if reconnect_saved_wifi "$adapter" "$state_dir" "$ssid"; then
          info 'Existing saved Wi-Fi profile reconnected successfully.'
          return 0
        fi
        if [[ "$WIFI_FAILURE_KIND" == dhcp ]]; then
          retry_wifi_dhcp "$adapter" "$state_dir" "$ssid"
          return $?
        fi
        info 'The saved profile could not associate. You can enter corrected credentials or type CANCEL.'
      fi
    fi
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
    if reconnect_saved_wifi "$adapter" "$state_dir" "$ssid"; then
      [[ -z "$backup_dir" ]] || info "Previous profile backed up at $backup_dir/original.psk"
      info 'Saved Wi-Fi profile, association, DHCP, and Wi-Fi route verified. Reboot persistence still requires a real reboot test.'
      return 0
    fi
    if [[ "$WIFI_FAILURE_KIND" == dhcp ]]; then
      [[ -z "$backup_dir" ]] || info "Previous profile backed up at $backup_dir/original.psk"
      retry_wifi_dhcp "$adapter" "$state_dir" "$ssid"
      return $?
    fi
    info "iwd could not associate with $ssid. The previous profile will be restored if one existed."

    rm -f -- "$profile"
    if [[ -n "$backup_dir" ]]; then
      cp -p -- "$backup_dir/original.psk" "$profile" || die "Could not restore the previous profile from $backup_dir."
      rm -f -- "$backup_dir/original.psk"
      rmdir -- "$backup_dir"
      info 'Previous profile restored.'
    fi
    read -r -p 'Retry Wi-Fi [r] or CANCEL (offer Ethernet-only completion) [c]? [r]: ' answer || return 2
    [[ ! "$answer" =~ ^[Cc]$ ]] || return 2
    scan_wifi_networks "$adapter" || true
  done
}

main() {
  local adapter ssid answer
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
  systemctl start iwd.service
  configure_wifi_network "$adapter"
  ssid=$(connected_wifi_ssid "$adapter") || true
  if [[ -n "$ssid" ]] && wifi_connection_ready "$adapter" /var/lib/iwd "$ssid"; then
    info "The current Wi-Fi link ($ssid) looks ready, but the saved credentials have not been retested."
    if reconnect_saved_wifi "$adapter" /var/lib/iwd "$ssid"; then
      info 'Saved credentials reconnected, Wi-Fi DHCP and route verified. A real reboot test is still required.'
      return 0
    fi
    info 'The saved profile did not reconnect. Please enter corrected credentials or type CANCEL.'
  else
    info 'The current Wi-Fi connection is not verified as persistent; credentials must be checked.'
  fi
  scan_wifi_networks "$adapter" || true
  if connect_wifi_with_retries "$adapter" /var/lib/iwd; then
    return 0
  else
    answer=$?
    info 'Wi-Fi was not verified; previously saved profiles were preserved.'
    return "$answer"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
