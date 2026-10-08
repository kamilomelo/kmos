#!/usr/bin/env bash
# Only fixtures and mocked services: never switch the host's network.
# Mock state is consumed by the sourced migration script.
# shellcheck disable=SC1090,SC2034,SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/tools/kmos-network-migration.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

(
  # shellcheck disable=SC1091
  source "$script"
  NM_CONF="$fixture/nm.conf" MIGRATION_MARKER="$fixture/in-progress" MIGRATION_DONE="$fixture/done"
  local_console() { :; }
  ready_for_handoff() { WIRED_IFACE=enp1s0 WIFI_IFACE=wlan0; }
  check_internet_on() { [[ "$1" == enp1s0 ]]; }
  confirm_handoff() { :; }
  require_root() { :; }
  iwctl() { [[ "$*" == 'station wlan0 disconnect' ]] && printf 'disconnect wifi\n' >> "$fixture/success-order"; }
  systemctl() { printf '%s\n' "$*" >> "$fixture/success-order"; }
  wait_for_wired() { printf 'wired verified\n' >> "$fixture/success-order"; }
  confirm_wifi() { printf 'wifi verified\n' >> "$fixture/success-order"; }
  apply_handoff
  [[ ! -e "$MIGRATION_MARKER" && -f "$NM_CONF" && -f "$MIGRATION_DONE" ]]
  [[ $(cat "$NM_CONF") == $'[device]\nwifi.backend=iwd\nwifi.iwd.autoconnect=false' ]]
) > "$fixture/success"
[[ $(cat "$fixture/success-order") == $'stop dhcpcd.service\ndisconnect wifi\nstart NetworkManager.service\nwired verified\nwifi verified\nenable NetworkManager.service\ndisable dhcpcd.service\ndisable iwd.service' ]]

(
  # shellcheck disable=SC1091
  source "$script"
  NM_CONF="$fixture/nm.conf" MIGRATION_MARKER="$fixture/in-progress" MIGRATION_DONE="$fixture/done"
  state() { printf 'active\n'; }
  systemctl() { printf '%s\n' "$*" >> "$fixture/manual-rollback-order"; }
  rollback
) > "$fixture/manual-rollback" 2>&1
[[ ! -e "$fixture/done" && ! -e "$fixture/nm.conf" ]]
grep -Fxq 'enable iwd.service dhcpcd.service' "$fixture/manual-rollback-order"

if (
  # shellcheck disable=SC1091
  source "$script"
  NM_CONF="$fixture/fail-nm.conf" MIGRATION_MARKER="$fixture/fail-marker" MIGRATION_DONE="$fixture/fail-done"
  local_console() { :; }
  ready_for_handoff() { WIRED_IFACE=enp1s0 WIFI_IFACE=wlan0; }
  check_internet_on() { :; }
  confirm_handoff() { :; }
  require_root() { :; }
  iwctl() { :; }
  state() { printf 'active\n'; }
  systemctl() {
    printf '%s\n' "$*" >> "$fixture/rollback-order"
    [[ "$*" != 'start NetworkManager.service' ]]
  }
  apply_handoff
) > "$fixture/failed" 2>&1; then
  printf 'Failed NetworkManager start was accepted.\n' >&2; exit 1
fi
[[ ! -e "$fixture/fail-marker" && ! -e "$fixture/fail-nm.conf" && ! -e "$fixture/fail-done" ]]
grep -Fxq 'start iwd.service dhcpcd.service' "$fixture/rollback-order"
grep -Fq 'Restoring the prior network services' "$fixture/failed"

if (
  # shellcheck disable=SC1091
  source "$script"
  NM_CONF="$fixture/unset-nm.conf" MIGRATION_MARKER="$fixture/unset-marker" MIGRATION_DONE="$fixture/unset-done"
  IWD_CONF="$fixture/iwd.conf"
  printf '[General]\nEnableNetworkConfiguration=true\n' > "$IWD_CONF"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  kde_ready() { :; }
  nmcli() { :; }
  curl() { :; }
  iwctl() { :; }
  state() {
    case "$2" in
      NetworkManager.service) printf 'inactive\n' ;;
      *) [[ "$1" == is-active ]] && printf 'active\n' || printf 'enabled\n' ;;
    esac
  }
  ready_for_handoff
) > "$fixture/unset-iwd" 2>&1; then
  printf 'Accepted simultaneous iwd IP configuration.\n' >&2; exit 1
fi
grep -Fq 'iwd built-in IP configuration is enabled' "$fixture/unset-iwd"

printf 'Local NM handoff and failure rollback: OK (mocked services only).\n'
