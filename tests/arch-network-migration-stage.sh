#!/usr/bin/env bash
# Offline reboot-stage / boot-check fixtures; no host networking is changed.
# Mocked functions are consumed by the sourced migration script.
# shellcheck disable=SC1090,SC2034,SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/tools/kmos-network-migration.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

(
  # shellcheck disable=SC1091
  source "$script"
  NM_CONF="$fixture/nm.conf" STAGED_MARKER="$fixture/staged"
  MIGRATION_MARKER="$fixture/live" MIGRATION_DONE="$fixture/done"
  BOOT_SCRIPT="$fixture/installed-script" BOOT_UNIT="$fixture/boot.service"
  ready_for_handoff() { WIRED_IFACE=enp1s0 WIFI_IFACE=wlan0; }
  ssh_interface() { printf 'enp1s0\n'; }
  check_internet_on() { [[ "$1" == enp1s0 ]]; }
  confirm_staging() { :; }
  require_root() { :; }
  state() { [[ "$2" == NetworkManager.service ]] && printf 'inactive\n' || printf 'active\n'; }
  systemctl() { printf '%s\n' "$*" >> "$fixture/stage-order"; }
  SSH_CONNECTION='192.0.2.9 1234 192.0.2.10 22'
  stage_reboot
  [[ -r "$STAGED_MARKER" && -f "$BOOT_SCRIPT" && -f "$BOOT_UNIT" && -f "$NM_CONF" ]]
  [[ $(cat "$STAGED_MARKER") == enp1s0 ]]
) > "$fixture/stage-output"
[[ $(cat "$fixture/stage-order") == $'daemon-reload\nenable kmos-nm-boot-check.service\nenable NetworkManager.service\ndisable dhcpcd.service iwd.service' ]]
if grep -Eq '^(start|stop) ' "$fixture/stage-order"; then
  printf 'Staging modified live network services.\n' >&2; exit 1
fi
mkdir -p "$fixture/sysnet/enp1s0"
touch "$fixture/sysnet/enp1s0/device"

(
  # shellcheck disable=SC1091
  source "$script"
  NM_CONF="$fixture/nm.conf" STAGED_MARKER="$fixture/staged"
  MIGRATION_MARKER="$fixture/live" MIGRATION_DONE="$fixture/done"
  BOOT_SCRIPT="$fixture/installed-script" BOOT_UNIT="$fixture/boot.service"
  SYS_NET_ROOT="$fixture/sysnet"
  interface_kind() { printf 'Ethernet\n'; }
  nm_connected() { [[ "$1" == enp1s0 ]]; }
  require_boot_root() { :; }
  systemctl() { printf '%s\n' "$*" >> "$fixture/boot-order"; }
  boot_check
  [[ ! -e "$STAGED_MARKER" && -f "$MIGRATION_DONE" && ! -e "$BOOT_UNIT" ]]
  [[ -f "$NM_CONF" ]]
) > "$fixture/boot-output"
grep -Fxq 'disable kmos-nm-boot-check.service' "$fixture/boot-order"

(
  # shellcheck disable=SC1091
  source "$script"
  NM_CONF="$fixture/failed-nm.conf" STAGED_MARKER="$fixture/failed-stage"
  MIGRATION_MARKER="$fixture/failed-live" MIGRATION_DONE="$fixture/failed-done"
  BOOT_SCRIPT="$fixture/failed-script" BOOT_UNIT="$fixture/failed-boot.service"
  SYS_NET_ROOT="$fixture/sysnet"
  printf 'enp1s0\n' > "$STAGED_MARKER"
  write_backend_config
  install -Dm0755 "$script" "$BOOT_SCRIPT"
  write_boot_unit
  interface_kind() { printf 'Ethernet\n'; }
  nm_connected() { return 1; }
  require_boot_root() { :; }
  sleep() { :; }
  state() { printf 'active\n'; }
  systemctl() { printf '%s\n' "$*" >> "$fixture/failure-order"; }
  if boot_check; then
    printf 'A failed Ethernet handoff was accepted.\n' >&2; exit 1
  fi
  [[ ! -e "$STAGED_MARKER" && ! -e "$NM_CONF" && ! -e "$BOOT_UNIT" ]]
) > "$fixture/failed-boot" 2>&1
grep -Fxq 'start iwd.service dhcpcd.service' "$fixture/failure-order"

if (
  # shellcheck disable=SC1091
  source "$script"
  NM_CONF="$fixture/partial-nm.conf" STAGED_MARKER="$fixture/partial-stage"
  MIGRATION_MARKER="$fixture/partial-live" MIGRATION_DONE="$fixture/partial-done"
  BOOT_SCRIPT="$fixture/partial-script" BOOT_UNIT="$fixture/partial-boot.service"
  ready_for_handoff() { WIRED_IFACE=enp1s0 WIFI_IFACE=wlan0; }
  check_internet_on() { :; }
  confirm_staging() { :; }
  require_root() { :; }
  state() { [[ "$2" == NetworkManager.service ]] && printf 'inactive\n' || printf 'active\n'; }
  systemctl() {
    printf '%s\n' "$*" >> "$fixture/partial-order"
    [[ "$*" != 'enable NetworkManager.service' ]]
  }
  stage_reboot
) > "$fixture/partial-failure" 2>&1; then
  printf 'Partially staged boot migration was accepted.\n' >&2; exit 1
fi
[[ ! -e "$fixture/partial-stage" && ! -e "$fixture/partial-boot.service" && ! -e "$fixture/partial-nm.conf" ]]
grep -Fxq 'enable iwd.service dhcpcd.service' "$fixture/partial-order"
printf 'SSH reboot stage, boot validation and fallback: OK (mocked only).\n'
