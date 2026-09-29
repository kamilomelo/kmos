#!/usr/bin/env bash
# Connect with iwd on Arch Linux ARM, then retain its working profile for boot.
set -Eeuo pipefail
NETWORK_NAMES=()
IWD_CONFIG_CHANGED=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*" >&2; }

validate_wifi_credentials() {
  local ssid=$1 passphrase=$2
  [[ "$ssid" =~ ^[a-zA-Z0-9_\ -]{1,32}$ ]] || return 1
  [[ ${#passphrase} -ge 8 && ${#passphrase} -le 63 && "$passphrase" != *$'\r'* && "$passphrase" != *$'\n'* ]]
}

install_offline_wifi() (
  local cache=$1 marker=$2 config
  local -a ell=() iwd=()
  config=$(mktemp "${TMPDIR:-/run}/kmos-wifi-pacman.XXXXXXXX")
  trap 'rm -f -- "$config"' EXIT
  shopt -s nullglob
  ell=("$cache"/ell-*-aarch64.pkg.tar.xz "$cache"/ell-*-aarch64.pkg.tar.zst)
  iwd=("$cache"/iwd-*-aarch64.pkg.tar.xz "$cache"/iwd-*-aarch64.pkg.tar.zst)
  [[ ${#ell[@]} == 1 && ${#iwd[@]} == 1 ]] || { printf 'Expected exactly one ell and iwd package in %s.\n' "$cache" >&2; return 1; }
  [[ -f "${ell[0]}.sig" && -f "${iwd[0]}.sig" ]] || { printf 'Missing detached ARM package signatures.\n' >&2; return 1; }
  pacman-key --init
  pacman-key --populate archlinuxarm
  cp "${KMOS_PACMAN_CONF:-/etc/pacman.conf}" "$config"
  if grep -q '^LocalFileSigLevel[[:space:]]*=' "$config"; then
    sed -i 's/^LocalFileSigLevel[[:space:]]*=.*/LocalFileSigLevel = Required/' "$config"
  else
    sed -i '/^\[options\]$/a LocalFileSigLevel = Required' "$config"
  fi
  pacman --config "$config" -U --noconfirm -- "${ell[0]}" "${iwd[0]}"
  pacman -Q ell iwd >/dev/null
  systemctl enable --now iwd.service
  install -d -m 0755 "${marker%/*}"
  touch "$marker"
  printf 'Offline ARM Wi-Fi packages installed; iwd enabled. Check Wi-Fi association and DHCP.\n'
)

usage() {
  cat <<'EOF'
Usage: ./connect-quartz64b-wifi.sh [--wpa-fallback|--help]

Connect a detected Wi-Fi adapter using iwctl first, then verify internet over
that adapter and keep the working iwd profile for later boots. If iwd is missing, offer
to install the signed offline ARM packages staged during SD preparation.
Like the x86 Arch helper, iwctl --passphrase briefly exposes the password in
the process argument list. Run from the local console if Wi-Fi carries SSH.
Only a real reboot can verify that it reconnects on a later boot. Type CANCEL
to stop; cancelling never claims Wi-Fi is configured.
Like the x86 installer, iwd handles association, DHCP and DNS on Wi-Fi.
Existing iwd driver settings and saved network profiles are preserved.
--wpa-fallback switches this adapter to wpa_supplicant plus networkd DHCP.
It requires the ARM wpa_supplicant package installed and must be run from the
local console or over Ethernet, not over the Wi-Fi connection being switched.
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
    info 'Wi-Fi scan could not start (it may already be in progress); checking the available network list.'
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

configure_iwd_main() {
  local config=${1:-/etc/iwd/main.conf} backup
  IWD_CONFIG_CHANGED=0
  if [[ -e "$config" || -L "$config" ]]; then
    [[ -f "$config" && ! -L "$config" ]] || die "Refusing to replace a non-regular iwd configuration: $config"
    [[ $(grep -Ec '^[[:space:]]*\[General\][[:space:]]*$' "$config") == 1 ]] \
      || die "Expected one [General] section in $config; inspect it before switching iwd to DHCP."
    if grep -Eq '^[[:space:]]*NameResolvingService[[:space:]]*=' "$config" \
      && ! grep -Eq '^[[:space:]]*NameResolvingService[[:space:]]*=[[:space:]]*systemd[[:space:]]*$' "$config"; then
      die "Existing DNS settings in $config conflict with systemd-resolved."
    fi
    if grep -Eq '^[[:space:]]*EnableNetworkConfiguration[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$config" \
      && grep -Eq '^[[:space:]]*NameResolvingService[[:space:]]*=[[:space:]]*systemd[[:space:]]*$' "$config"; then
      info "Preserving existing iwd configuration: $config"
      return 0
    fi
    if grep -Eq '^[[:space:]]*EnableNetworkConfiguration[[:space:]]*=' "$config" \
      && ! grep -Eq '^[[:space:]]*EnableNetworkConfiguration[[:space:]]*=[[:space:]]*(false|true)[[:space:]]*$' "$config"; then
      die "Unknown iwd network configuration in $config; refusing to overwrite it."
    fi
    backup=$(mktemp "$config.before-kmos.XXXXXXXX") || die "Could not back up $config."
    cp -p -- "$config" "$backup" || die "Could not back up $config."
    if grep -Eq '^[[:space:]]*EnableNetworkConfiguration[[:space:]]*=' "$config"; then
      sed -i -E 's/^[[:space:]]*EnableNetworkConfiguration[[:space:]]*=.*/EnableNetworkConfiguration=true/' "$config"
    else
      sed -i '/^[[:space:]]*\[General\][[:space:]]*$/a EnableNetworkConfiguration=true' "$config"
    fi
    if grep -Eq '^[[:space:]]*\[Network\][[:space:]]*$' "$config"; then
      grep -Eq '^[[:space:]]*NameResolvingService[[:space:]]*=' "$config" \
        || sed -i '/^[[:space:]]*\[Network\][[:space:]]*$/a NameResolvingService=systemd' "$config"
    else
      printf '\n[Network]\nNameResolvingService=systemd\n' >> "$config"
    fi
    info "iwd will own Wi-Fi DHCP/DNS as on x86. Previous config backed up at $backup"
    IWD_CONFIG_CHANGED=1
    return 0
  fi
  install -Dm0644 /dev/stdin "$config" <<'EOF'
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
EOF
  IWD_CONFIG_CHANGED=1
}

configure_wifi_network() {
  local adapter=$1 iwd_config=${2:-/etc/iwd/main.conf} network_config=${3:-/etc/systemd/network/25-wifi-dhcp.network} legacy migrate=0
  if systemctl is-active --quiet "wpa_supplicant@$adapter.service" \
    || systemctl is-enabled --quiet "wpa_supplicant@$adapter.service"; then
    die "wpa_supplicant@$adapter.service is active or enabled; refusing to start iwd on the same adapter."
  fi
  # This is the x86 handoff's iwd DHCP/DNS model. networkd keeps Ethernet.
  if [[ -e "$network_config" || -L "$network_config" ]]; then
    [[ -f "$network_config" && ! -L "$network_config" ]] || die "Refusing to replace a non-regular networkd file: $network_config"
    legacy=$(cat <<'EOF'
[Match]
Name=wl* wlan*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=600
EOF
)
    [[ $(cat "$network_config") == "$legacy" ]] \
      || die "Custom Wi-Fi networkd settings in $network_config; refusing to switch DHCP owners without review."
    if [[ -n "${SSH_CONNECTION:-}" && -n $(connected_wifi_ssid "$adapter") ]]; then
      die 'Switching Wi-Fi DHCP owners may drop SSH. Run from the local console.'
    fi
    [[ ! -e "$network_config.kmos-networkd-backup" && ! -L "$network_config.kmos-networkd-backup" ]] \
      || die "Backup already exists: $network_config.kmos-networkd-backup"
    migrate=1
  fi
  configure_iwd_main "$iwd_config"
  systemctl enable --now systemd-networkd.service systemd-resolved.service
  if ((migrate)); then
    mv -- "$network_config" "$network_config.kmos-networkd-backup"
    networkctl reload
    networkctl reconfigure "$adapter" || die "Could not release networkd's Wi-Fi configuration on $adapter."
    info "Old Wi-Fi networkd config moved to $network_config.kmos-networkd-backup"
  fi
  if ((IWD_CONFIG_CHANGED)) && systemctl is-active --quiet iwd.service; then
    if ((migrate)) || [[ -z $(connected_wifi_ssid "$adapter") ]]; then
      systemctl restart iwd.service
    else
      info 'Existing Wi-Fi connection left intact; the new iwd config takes effect after iwd restarts or the board reboots.'
    fi
  fi
  systemctl enable --now iwd.service
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
  [[ $(stat -c %u -- "$profile") == 0 ]] || return 1
  [[ $(stat -c %a -- "$profile") == 600 ]] || return 1
  # iwd's generated profiles default to autoconnect even without this key.
  ! grep -Fxq 'AutoConnect=false' "$profile" || return 1
  for service in iwd.service systemd-resolved.service; do
    systemctl is-active --quiet "$service" || return 1
    systemctl is-enabled --quiet "$service" || return 1
  done
  [[ $(connected_wifi_ssid "$adapter") == "$ssid" ]] || return 1
  ip -4 -o address show dev "$adapter" scope global | grep -q . || return 1
  ip -4 route show default dev "$adapter" | grep -q . || return 1
  ping -I "$adapter" -c 3 -W 3 km-robota.com >/dev/null
}

wait_for_wifi() {
  local adapter=$1 state_dir=$2 ssid=$3 attempt
  for ((attempt=0; attempt<12; attempt++)); do
    wifi_connection_ready "$adapter" "$state_dir" "$ssid" && return 0
    sleep 2
  done
  return 1
}

wpa_connection_ready() {
  local adapter=$1 ssid=$2 profile=$3 status service
  [[ -f "$profile" && ! -L "$profile" && $(stat -c %a -- "$profile") == 600 ]] || return 1
  status=$(wpa_cli -i "$adapter" status) || return 1
  grep -Fxq 'wpa_state=COMPLETED' <<< "$status" || return 1
  grep -Fxq "ssid=$ssid" <<< "$status" || return 1
  for service in "wpa_supplicant@$adapter.service" systemd-networkd.service systemd-resolved.service; do
    systemctl is-enabled --quiet "$service" || return 1
    systemctl is-active --quiet "$service" || return 1
  done
  ip -4 -o address show dev "$adapter" scope global | grep -q . || return 1
  ip -4 route show default dev "$adapter" | grep -q . || return 1
  ping -I "$adapter" -c 3 -W 3 km-robota.com >/dev/null
}

restore_iwd_after_wpa_failure() {
  local adapter=$1 profile=$2 network_config=$3
  if ! systemctl disable --now "wpa_supplicant@$adapter.service" \
    && systemctl is-active --quiet "wpa_supplicant@$adapter.service"; then
    info 'Could not stop wpa_supplicant; iwd will NOT be started alongside it.'
    return 1
  fi
  rm -f -- "$profile" "$network_config" || return 1
  networkctl reload || return 1
  networkctl reconfigure "$adapter" || return 1
  systemctl enable --now iwd.service
}

configure_wpa_fallback() {
  local adapter=$1 ssid=$2 passphrase=$3
  local profile=${4:-/etc/wpa_supplicant/wpa_supplicant-$adapter.conf}
  local network_config=${5:-/etc/systemd/network/25-wifi-dhcp.network} attempt
  [[ ! -e "$profile" && ! -L "$profile" && ! -e "$network_config" && ! -L "$network_config" ]] \
    || die 'Existing wpa_supplicant or Wi-Fi networkd configuration needs manual review; refusing to overwrite it.'
  # wpa_passphrase reads from stdin; remove its plaintext #psk comment.
  if ! printf '%s\n' "$passphrase" | wpa_passphrase "$ssid" | sed '/^[[:space:]]*#psk=/d' \
    | install -Dm0600 /dev/stdin "$profile"; then
    rm -f -- "$profile"
    die 'Could not create the fallback Wi-Fi profile.'
  fi
  if ! install -Dm0644 /dev/stdin "$network_config" <<'EOF'
[Match]
Name=wl* wlan*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=600
EOF
  then
    rm -f -- "$profile" "$network_config"
    die 'Could not write the fallback networkd configuration.'
  fi
  if ! systemctl disable --now iwd.service; then
    restore_iwd_after_wpa_failure "$adapter" "$profile" "$network_config" \
      || die 'Fallback rollback failed; inspect wpa_supplicant and iwd before rebooting.'
    die 'Could not stop iwd; refusing to run two Wi-Fi managers.'
  fi
  if ! systemctl enable --now systemd-networkd.service systemd-resolved.service \
    || ! networkctl reload \
    || ! networkctl reconfigure "$adapter" \
    || ! systemctl enable --now "wpa_supplicant@$adapter.service"; then
    restore_iwd_after_wpa_failure "$adapter" "$profile" "$network_config" \
      || die 'Fallback rollback failed; inspect wpa_supplicant and iwd before rebooting.'
    die 'Could not start the wpa_supplicant fallback; iwd restoration was attempted.'
  fi
  for ((attempt=0; attempt<12; attempt++)); do
    if wpa_connection_ready "$adapter" "$ssid" "$profile"; then
      info 'wpa_supplicant association, DHCP, route and Wi-Fi internet verified. A real reboot test is still required.'
      return 0
    fi
    sleep 2
  done
  restore_iwd_after_wpa_failure "$adapter" "$profile" "$network_config" \
    || die 'Fallback rollback failed; inspect wpa_supplicant and iwd before rebooting.'
  die 'wpa_supplicant fallback was not verified; iwd restoration was attempted. Keep Ethernet connected.'
}

run_wpa_fallback() {
  local adapter=$1 ssid passphrase
  if ! command -v wpa_passphrase >/dev/null 2>&1 || ! command -v wpa_cli >/dev/null 2>&1; then
    die 'wpa_supplicant is not installed. Use the provisioner with Ethernet to install the ARM package first.'
  fi
  if [[ -n "${SSH_CONNECTION:-}" ]] && ip -4 -o address show dev "$adapter" scope global | grep -q .; then
    die 'Wi-Fi has an IP address during SSH. Use the local console to switch Wi-Fi managers safely.'
  fi
  read -r -p 'Fallback Wi-Fi SSID: ' ssid || return 2
  read -r -s -p 'Fallback Wi-Fi passphrase: ' passphrase || return 2
  printf '\n' >&2
  validate_wifi_credentials "$ssid" "$passphrase" || die 'Invalid SSID or WPA passphrase.'
  configure_wpa_fallback "$adapter" "$ssid" "$passphrase"
  unset passphrase
}

connect_wifi_with_retries() {
  local adapter=$1 state_dir=$2 ssid passphrase hidden answer command profile backup_dir result
  while true; do
    read -r -p 'Wi-Fi network number or SSID (or type CANCEL): ' ssid || return 2
    [[ "$ssid" != CANCEL ]] || return 2
    if [[ "$ssid" =~ ^[1-9][0-9]*$ ]] && ((ssid <= ${#NETWORK_NAMES[@]})); then
      ssid=${NETWORK_NAMES[$((ssid - 1))]}
      info "Selected network: $ssid"
    fi
    [[ "$ssid" =~ ^[a-zA-Z0-9_\ -]{1,32}$ ]] || { info 'SSID must be 1-32 ASCII letters, digits, spaces, underscores or hyphens.'; continue; }
    profile="$state_dir/$ssid.psk"
    [[ ! -L "$profile" ]] || die "Refusing to use a symlinked Wi-Fi profile: $profile"
    if [[ -n "${SSH_CONNECTION:-}" && -n $(connected_wifi_ssid "$adapter") ]]; then
      die 'Changing an active Wi-Fi connection may drop SSH. Run from the local console.'
    fi
    passphrase=""
    if [[ -f "$profile" ]]; then
      read -r -p "Use the existing iwd profile for $ssid? [Y/n]: " answer || return 2
      if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        info 'Testing the profile iwd already saved.'
      else
        read -r -s -p 'WPA passphrase: ' passphrase || return 2
        printf '\n' >&2
      fi
    else
      read -r -s -p 'WPA passphrase: ' passphrase || return 2
      printf '\n' >&2
    fi
    read -r -p 'Hidden network? [y/N]: ' hidden || { unset passphrase; return 2; }
    case "$hidden" in [Yy]*) command=connect-hidden ;; *) command=connect ;; esac
    if [[ -n "$passphrase" ]] && ! validate_wifi_credentials "$ssid" "$passphrase"; then
      unset passphrase
      info 'WPA passphrase must be 8-63 characters.'
      continue
    fi
    backup_dir=""
    if [[ -n "$passphrase" && -f "$profile" ]]; then
      backup_dir=$(mktemp -d "$state_dir/.kmos-wifi-backup.XXXXXXXX") || die 'Could not create a private Wi-Fi profile backup.'
      cp -p -- "$profile" "$backup_dir/original.psk" || die "Could not back up $profile."
    fi
    # As on the x86 live system, connect using the initial scan's network list.
    # An extra asynchronous scan here races with iwd's connection attempt.
    info "Connecting to $ssid via $adapter (up to 45 seconds)..."
    result=0
    if [[ -n "$passphrase" ]]; then
      timeout --foreground 45s iwctl --passphrase "$passphrase" station "$adapter" "$command" "$ssid" || result=$?
    else
      timeout --foreground 45s iwctl station "$adapter" "$command" "$ssid" || result=$?
    fi
    unset passphrase
    if ((result == 124)); then
      info 'iwctl timed out; checking whether iwd associated anyway.'
    elif ((result != 0)); then
      info "iwctl exited with status $result; checking whether iwd associated anyway."
    fi
    if wait_for_wifi "$adapter" "$state_dir" "$ssid"; then
      [[ -z "$backup_dir" ]] || info "Previous profile backed up at $backup_dir/original.psk"
      info 'Working iwd profile, association, Wi-Fi DHCP/route and internet verified. Reboot persistence still requires a real reboot test.'
      return 0
    fi
    info "Wi-Fi was not verified for $ssid (association, profile, DHCP, or internet)."
    if [[ -n "$backup_dir" ]]; then
      cp -p -- "$backup_dir/original.psk" "$profile" || die "Could not restore the previous profile from $backup_dir."
      info 'Previous profile restored.'
    fi
    networkctl status "$adapter" --no-pager >&2 || true
    read -r -p 'Retry Wi-Fi [r] or CANCEL [c]? [r]: ' answer || return 2
    [[ ! "$answer" =~ ^[Cc]$ ]] || return 2
  done
}

main() {
  local adapter ssid answer fallback=0
  case "${1:-}" in
    -h|--help) usage; return ;;
    --wpa-fallback) fallback=1 ;;
    '') ;;
    *) die "Unknown argument: $1" ;;
  esac
  (($# == 0 || ($# == 1 && fallback == 1))) || die 'Unexpected arguments.'
  [[ $(uname -m) == aarch64 ]] || die 'This helper is for AArch64 boards.'
  if ((EUID != 0)); then
    command -v sudo >/dev/null 2>&1 || die 'Root access is required, but sudo is unavailable.'
    info 'Root access is needed to configure Wi-Fi; sudo will prompt for your password.'
    exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
  fi
  adapter=$(detect_wifi_adapter) || die 'No wireless interface found. Check your adapter and its firmware.'
  info "Detected Wi-Fi interface: $adapter"
  if ((fallback)); then
    run_wpa_fallback "$adapter"
    return
  fi
  if command -v rfkill >/dev/null 2>&1; then
    rfkill unblock wifi || die 'Could not unblock the wireless adapter.'
  fi
  if ! command -v iwctl >/dev/null 2>&1; then
    [[ -d /var/lib/kmos/wifi-packages ]] \
      || die 'iwd is missing and no offline packages were staged. Use temporary networking to install the ARM iwd package.'
    read -r -p 'Install signed offline ARM ell and iwd packages now? [Y/n]: ' answer
    [[ ! "$answer" =~ ^[Nn]$ ]] || die 'Cancelled; Wi-Fi remains unconfigured.'
    install_offline_wifi /var/lib/kmos/wifi-packages /var/lib/kmos/quartz64b-wifi-packages-installed
    command -v iwctl >/dev/null 2>&1 || die 'iwd installation did not provide iwctl.'
  fi
  command -v timeout >/dev/null 2>&1 || die 'Coreutils timeout is required so Wi-Fi connect cannot hang indefinitely.'
  configure_wifi_network "$adapter"
  ssid=$(connected_wifi_ssid "$adapter") || true
  if [[ -n "$ssid" ]] && wifi_connection_ready "$adapter" /var/lib/iwd "$ssid"; then
    info "Working Wi-Fi link ($ssid) and saved iwd profile verified. A real reboot test is still required."
    return 0
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
