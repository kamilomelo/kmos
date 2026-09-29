#!/usr/bin/env bash
# Offline-only checks for the separate wpa_supplicant trial.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck source=platforms/archlinuxarm/boards/quartz64b/try-quartz64b-wpa-wifi.sh
source "$repo/platforms/archlinuxarm/boards/quartz64b/try-quartz64b-wpa-wifi.sh"

# An already-installed package needs no update or Ethernet.
(
  pacman() { [[ "$1" == -Q && "$2" == wpa_supplicant ]]; }
  ethernet_ready() { printf 'unexpected Ethernet probe\n' >&2; exit 1; }
  ensure_wpa_package wlan0
)

# A missing package requires a working Ethernet route before any changes.
if (
  pacman() { return 1; }
  ethernet_ready() { return 1; }
  ensure_wpa_package wlan0
) >"$fixture/no-ethernet" 2>&1; then
  printf 'Missing package accepted without Ethernet.\n' >&2
  exit 1
fi
grep -q 'No working Ethernet route' "$fixture/no-ethernet"

# Declining the full update does not install anything or switch Wi-Fi.
if (
  pacman() { [[ "$1" != -Q ]] || return 1; printf 'Unexpected update.\n' >&2; exit 1; }
  ethernet_ready() { return 0; }
  ensure_wpa_package wlan0 <<< 'n'
) >"$fixture/declined" 2>&1; then
  printf 'Declined update was accepted.\n' >&2
  exit 1
fi
grep -q 'configuration was not changed' "$fixture/declined"

(
  pacman() {
    if [[ "$1" == -Q ]]; then [[ -e "$fixture/package-installed" ]]; return; fi
    [[ "$*" == '-Syu --needed wpa_supplicant' ]] || exit 1
    touch "$fixture/package-installed"
  }
  ethernet_ready() { [[ "$1" == wlan0 ]]; }
  ensure_wpa_package wlan0 <<< 'y'
)
[[ -e "$fixture/package-installed" ]]

# Post-boot check is read-only; reject competing backends and failed Wi-Fi.
if (
  systemctl() { [[ "$1" == is-enabled && "$3" == iwd.service ]]; }
  verify_wpa_after_boot wlan0
) >"$fixture/dual-manager" 2>&1; then
  printf 'Enabled iwd was accepted during wpa trial.\n' >&2
  exit 1
fi
grep -q 'two Wi-Fi backends' "$fixture/dual-manager"
(
  systemctl() { return 1; }
  wpa_cli() { printf 'wpa_state=COMPLETED\nssid=Trial Wifi\n'; }
  wpa_connection_ready() { [[ "$1" == wlan0 && "$2" == 'Trial Wifi' ]]; }
  verify_wpa_after_boot wlan0
)
if (
  systemctl() { return 1; }
  wpa_cli() { printf 'wpa_state=DISCONNECTED\n'; }
  verify_wpa_after_boot wlan0
) >"$fixture/disconnected" 2>&1; then
  printf 'Disconnected Wi-Fi was accepted after boot.\n' >&2
  exit 1
fi
grep -q 'not associated' "$fixture/disconnected"
printf 'Quartz standalone wpa_supplicant trial: OK (mocked only).\n'
