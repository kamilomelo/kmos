#!/usr/bin/env bash
# Mock-only backend selection; no Wi-Fi device or system services are changed.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"
REPOSITORY_DIR=$repo

# Default selection uses iwd and installs the repository Impala package.
(
  detect_wifi_adapter() { printf 'wlan0\n'; }
  systemctl() { return 1; }
  pacman() { printf '%s\n' "$*" >> "$fixture/pacman"; return 0; }
  configure_impala_wifi() {
    WIFI_BACKEND=iwd
    printf 'iwd\n' > "$fixture/chosen"
  }
  configure_persistent_wifi <<< ''
  [[ "$WIFI_BACKEND" == iwd ]]
)
[[ $(cat "$fixture/chosen") == iwd ]]

# An existing enabled wpa_supplicant profile remains the default, and an
# explicit attempt to choose iwd cannot start a competing backend.
(
  detect_wifi_adapter() { printf 'wlan0\n'; }
  systemctl() { [[ "$1" == is-enabled && "${!#}" == wpa_supplicant@wlan0.service ]]; }
  configure_wpa_wifi() { printf 'wpa\n' > "$fixture/chosen"; }
  configure_persistent_wifi <<< ''
)
[[ $(cat "$fixture/chosen") == wpa ]]
if (
  detect_wifi_adapter() { printf 'wlan0\n'; }
  systemctl() { [[ "$1" == is-enabled && "${!#}" == wpa_supplicant@wlan0.service ]]; }
  pacman() { printf 'Unexpected install with wpa enabled.\n' >&2; exit 1; }
  configure_persistent_wifi <<< '1'
) > "$fixture/conflict" 2>&1; then
  printf 'Impala was allowed to compete with wpa_supplicant.\n' >&2
  exit 1
fi
grep -q 'switching to iwd needs an explicit recovery migration' "$fixture/conflict"

# The maintenance command must not uninstall Impala simply because NM is
# installed: it needs active, enabled, exclusive, Wi-Fi-bound connectivity.
if (
  pacman() { [[ "$1" == -Q ]]; }
  systemctl() { return 1; }
  remove_impala_if_nm_ready
) > "$fixture/no-nm" 2>&1; then
  printf 'Impala was removed without a live NetworkManager takeover.\n' >&2
  exit 1
fi
grep -q 'must be active and enabled' "$fixture/no-nm" || { cat "$fixture/no-nm" >&2; exit 1; }

# Read-only iwd verification checks a saved profile and rejects NM conflicts.
(
  # shellcheck disable=SC1091
  source "$repo/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
  connected_wifi_ssid() { printf 'Example Network\n'; }
  wifi_connection_ready() { [[ "$1" == wlan0 && "$2" == /var/lib/iwd && "$3" == 'Example Network' ]]; }
  systemctl() { return 1; }
  check_iwd_wifi wlan0
) > "$fixture/iwd-check" 2>&1
grep -q 'iwd Wi-Fi verified' "$fixture/iwd-check"
if (
  # shellcheck disable=SC1091
  source "$repo/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
  systemctl() { [[ "${!#}" == NetworkManager.service ]]; }
  check_iwd_wifi wlan0
) > "$fixture/nm-conflict" 2>&1; then
  printf 'iwd was accepted alongside NetworkManager.\n' >&2
  exit 1
fi
grep -q 'standalone iwd must not compete' "$fixture/nm-conflict"
printf 'Quartz Impala/iwd choice, wpa isolation and NM removal gate: OK (mocked).\n'
