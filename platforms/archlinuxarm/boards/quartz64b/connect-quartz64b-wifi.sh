#!/usr/bin/env bash
# Connect with iwd on Arch Linux ARM, then retain its working profile for boot.
set -Eeuo pipefail
NETWORK_NAMES=()
IWD_CONFIG_CREATED=0
ALLOW_SAE=0

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
Usage: ./connect-quartz64b-wifi.sh [--allow-sae|--help]

Connect a detected Wi-Fi adapter using iwctl first, then verify internet over
that adapter and keep the working iwd profile for later boots. If iwd is missing, offer
to install the signed offline ARM packages staged during SD preparation.
Like the x86 Arch helper, iwctl --passphrase briefly exposes the password in
the process argument list. Run from the local console if Wi-Fi carries SSH.
Only a real reboot can verify that it reconnects on a later boot. Type CANCEL
to stop; cancelling never claims Wi-Fi is configured.
On brcmfmac, new configs use the tested WPA2 workaround by default. For a
WPA3-only network, --allow-sae leaves SAE enabled on a new iwd config. It
does not remove any quirk from an existing config.
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

wifi_driver() {
  local adapter=$1 driver_path=${2:-/sys/class/net/$1/device/driver} target
  [[ -L "$driver_path" ]] || return 1
  target=$(readlink -f -- "$driver_path") || return 1
  printf '%s\n' "${target##*/}"
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
  local config=${1:-/etc/iwd/main.conf} driver=${2:-}
  IWD_CONFIG_CREATED=0
  if [[ -e "$config" || -L "$config" ]]; then
    [[ -f "$config" && ! -L "$config" ]] || die "Refusing to replace a non-regular iwd configuration: $config"
    # iwd defaults to false when this key is absent. Preserve driver quirks,
    # especially the brcmfmac WPA2 compatibility setting validated on Quartz64.
    if ! awk -F= '/^[[:space:]]*EnableNetworkConfiguration[[:space:]]*=/ {
      value=$2
      gsub(/[[:space:]]/, "", value)
      if (value != "false" && value != "0") exit 1
    }' "$config"; then
      die "iwd network configuration conflicts with networkd; inspect $config before continuing."
    fi
    info "Preserving existing iwd configuration: $config"
    if [[ "$driver" == brcmfmac ]] && ! grep -Eq '^[[:space:]]*SaeDisable[[:space:]]*=[[:space:]]*brcmfmac[[:space:]]*$' "$config"; then
      info 'Existing iwd config does not enable the brcmfmac WPA2 workaround; it was not changed automatically.'
    fi
    return 0
  fi
  if [[ "$driver" == brcmfmac ]]; then
    install -Dm0644 /dev/stdin "$config" <<'EOF'
[General]
EnableNetworkConfiguration=false

[DriverQuirks]
SaeDisable=brcmfmac
EOF
    info 'Enabled the board-tested brcmfmac WPA2 workaround. WPA3-only networks will not connect.'
  else
    install -Dm0644 /dev/stdin "$config" <<'EOF'
[General]
EnableNetworkConfiguration=false
EOF
  fi
  IWD_CONFIG_CREATED=1
}

configure_wifi_network() {
  local adapter=$1 iwd_config=${2:-/etc/iwd/main.conf} network_config=${3:-/etc/systemd/network/25-wifi-dhcp.network} driver
  driver=$(wifi_driver "$adapter") || driver=""
  [[ -n "$driver" ]] || info "Could not identify the driver for $adapter; no driver-specific iwd quirk will be added."
  if ((ALLOW_SAE)) && [[ "$driver" == brcmfmac ]]; then
    if [[ -f "$iwd_config" ]] && grep -Eq '^[[:space:]]*SaeDisable[[:space:]]*=[[:space:]]*brcmfmac[[:space:]]*$' "$iwd_config"; then
      die "Existing $iwd_config disables SAE. --allow-sae will not overwrite it; inspect the config before using a WPA3-only network."
    fi
    info 'Leaving SAE enabled for brcmfmac; this has not been verified on the physical board.'
    driver=""
  fi
  # iwd owns association, networkd owns DHCP, and resolved owns DNS.
  configure_iwd_main "$iwd_config" "$driver"
  install -Dm0644 /dev/stdin "$network_config" <<'EOF'
[Match]
Name=wl* wlan*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=600
EOF
  systemctl enable --now systemd-networkd.service systemd-resolved.service
  if ((IWD_CONFIG_CREATED)) && systemctl is-active --quiet iwd.service; then
    if [[ -z $(connected_wifi_ssid "$adapter") ]]; then
      systemctl restart iwd.service
    else
      info 'Existing Wi-Fi connection left intact; the new iwd config takes effect after iwd restarts or the board reboots.'
    fi
  fi
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
  [[ $(stat -c %u -- "$profile") == 0 ]] || return 1
  [[ $(stat -c %a -- "$profile") == 600 ]] || return 1
  # iwd's generated profiles default to autoconnect even without this key.
  ! grep -Fxq 'AutoConnect=false' "$profile" || return 1
  for service in iwd.service systemd-networkd.service systemd-resolved.service; do
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
  local adapter ssid answer
  case "${1:-}" in
    -h|--help) usage; return ;;
    --allow-sae) ALLOW_SAE=1 ;;
    '') ;;
    *) die "Unknown argument: $1" ;;
  esac
  (($# == 0 || ($# == 1 && ALLOW_SAE == 1))) || die 'Unexpected arguments.'
  [[ $(uname -m) == aarch64 ]] || die 'This helper is for AArch64 boards.'
  if ((EUID != 0)); then
    command -v sudo >/dev/null 2>&1 || die 'Root access is required, but sudo is unavailable.'
    info 'Root access is needed to configure Wi-Fi; sudo will prompt for your password.'
    exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
  fi
  adapter=$(detect_wifi_adapter) || die 'No wireless interface found. Check your adapter and its firmware.'
  info "Detected Wi-Fi interface: $adapter"
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
