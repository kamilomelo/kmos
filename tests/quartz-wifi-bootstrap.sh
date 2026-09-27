#!/usr/bin/env bash
# Offline fixtures only; no network services, disk writers or actual sudo.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh"

write_iwd_profile "$fixture/iwd" 'Test Wifi' 'safe secret 123' false
[[ $(stat -c %a "$fixture/iwd") == 700 ]]
[[ $(stat -c %a "$fixture/iwd/Test Wifi.psk") == 600 ]]
grep -qx 'Passphrase=safe secret 123' "$fixture/iwd/Test Wifi.psk"
write_iwd_profile "$fixture/iwd" 'Other Wifi' ' backslash\test' true
grep -Fxq 'Passphrase=\sbackslash\\test' "$fixture/iwd/Other Wifi.psk"
if write_iwd_profile "$fixture/iwd" 'Test Wifi' 'different secret' false; then
  printf 'Existing Wi-Fi credentials were overwritten.\n' >&2
  exit 1
fi
if write_iwd_profile "$fixture/iwd" '../outside' 'safe secret 123' false; then
  printf 'Unsafe SSID was accepted.\n' >&2
  exit 1
fi

mkdir -p "$fixture/root/usr/bin" "$fixture/root/usr/lib/systemd/system"
touch "$fixture/root/usr/bin/iwctl" "$fixture/root/usr/lib/systemd/system/iwd.service"
tar -cf "$fixture/iwd.tar" -C "$fixture/root" .
FIRST_BOOT_WIFI=1
verify_first_boot_wifi_support "$fixture/iwd.tar"
tar -cf "$fixture/no-iwd.tar" -C "$fixture" root/usr/bin/iwctl
if (verify_first_boot_wifi_support "$fixture/no-iwd.tar") >/dev/null 2>&1; then
  printf 'Rootfs missing the iwd service was accepted.\n' >&2
  exit 1
fi
printf 'Quartz first-boot Wi-Fi profile and rootfs preflight: OK (offline fixtures).\n'
