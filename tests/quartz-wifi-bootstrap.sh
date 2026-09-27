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

# Mock a signed ARM rootfs and repository for the offline package-staging
# control flow. The mock GPG checks arguments; actual upstream signatures were
# also inspected separately, but CI never needs network access or a real SD.
mkdir -p "$fixture/offline-root/var/lib/pacman/local" "$fixture/offline-root/usr/lib" \
  "$fixture/offline-root/usr/share/pacman/keyrings" "$fixture/repo"
for dependency in glibc-1 libgcc-1 readline-8.3-1; do
  mkdir -p "$fixture/offline-root/var/lib/pacman/local/$dependency"
done
touch "$fixture/offline-root/usr/lib/libreadline.so.8"
printf 'test key\n' > "$fixture/offline-root/usr/share/pacman/keyrings/archlinuxarm.gpg"
printf '%s:4:\n' "$ALARM_SIGNING_FINGERPRINT" > "$fixture/offline-root/usr/share/pacman/keyrings/archlinuxarm-trusted"
tar -cf "$fixture/offline-rootfs.tar" -C "$fixture/offline-root" .

for package in ell iwd; do
  version=0.83-1
  dependencies=$'glibc\nlibgcc'
  if [[ "$package" == iwd ]]; then
    version=3.12-2
    dependencies=$'ell\nglibc\nlibgcc\nlibreadline.so=8-64\nreadline'
  fi
  filename="$package-$version-aarch64.pkg.tar.xz"
  mkdir -p "$fixture/package-content"
  {
    printf 'pkgname = %s\npkgver = %s\narch = aarch64\n' "$package" "$version"
    while IFS= read -r dependency; do printf 'depend = %s\n' "$dependency"; done <<< "$dependencies"
  } > "$fixture/package-content/.PKGINFO"
  bsdtar -cJf "$fixture/repo/$filename" -C "$fixture/package-content" .PKGINFO
  touch "$fixture/repo/$filename.sig"
  mkdir -p "$fixture/repo-db/$package-$version"
  {
    printf '%%FILENAME%%\n%s\n\n' "$filename"
    printf '%%SHA256SUM%%\n%s\n\n' "$(sha256sum "$fixture/repo/$filename" | awk '{print $1}')"
    printf '%%VERSION%%\n%s\n' "$version"
  } > "$fixture/repo-db/$package-$version/desc"
done
bsdtar -cf "$fixture/repo/extra.db" -C "$fixture/repo-db" .
download() { cp -- "$fixture/repo/${1##*/}" "$2"; }
# shellcheck disable=SC2329
gpg() {
  local argument import=0 verify=0
  for argument in "$@"; do
    [[ "$argument" != --import ]] || import=1
    [[ "$argument" != --verify ]] || verify=1
  done
  if ((import)); then cat >/dev/null; return 0; fi
  ((verify)) || return 1
  printf '[GNUPG:] VALIDSIG %s 2026-01-01 0 0 0 0 0 0 00 %s\n' "$ALARM_SIGNING_FINGERPRINT" "$ALARM_SIGNING_FINGERPRINT"
}
WORK_DIR="$fixture/work"
mkdir "$WORK_DIR"
verify_first_boot_wifi_support "$fixture/offline-rootfs.tar"
[[ -f "$WIFI_PACKAGE_DIR/ell-0.83-1-aarch64.pkg.tar.xz" ]]
[[ -f "$WIFI_PACKAGE_DIR/iwd-3.12-2-aarch64.pkg.tar.xz.sig" ]]
# shellcheck disable=SC2329
gpg() {
  printf '[GNUPG:] VALIDSIG %s 2026-01-01 0 0 0 0 0 0 00 %s\n' \
    "$ALARM_SIGNING_FINGERPRINT" '0000000000000000000000000000000000000000'
}
mkdir "$fixture/bad-signer"
if (verify_wifi_package "$fixture/bad-signer" iwd "$fixture/repo/extra.db" "$fixture") >/dev/null 2>&1; then
  printf 'Package signed by an unexpected key was accepted.\n' >&2
  exit 1
fi

# Mock the native first-boot pacman transaction; no real packages are installed.
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/first-boot-wifi.sh"
mkdir "$fixture/board-cache"
cp "$WIFI_PACKAGE_DIR"/*.pkg.tar.xz "$WIFI_PACKAGE_DIR"/*.pkg.tar.xz.sig "$fixture/board-cache/"
printf '[options]\nLocalFileSigLevel = Optional\n' > "$fixture/pacman.conf"
TMPDIR=$fixture
KMOS_PACMAN_CONF="$fixture/pacman.conf"
pacman-key() { :; }
pacman() {
  if [[ "$1" == --config ]]; then
    grep -qx 'LocalFileSigLevel = Required' "$2" || return 1
    [[ "$3" == -U && "$4" == --noconfirm && "$5" == -- ]] || return 1
    [[ -f "${6}.sig" && -f "${7}.sig" ]] || return 1
  else
    [[ "$1" == -Q && "$2" == ell && "$3" == iwd ]]
  fi
}
systemctl() { [[ "$1" == enable && "$2" == --now && "$3" == iwd.service ]]; }
install_offline_wifi "$fixture/board-cache" "$fixture/board-state/done"
[[ -f "$fixture/board-state/done" ]]
rm "$fixture/board-cache/iwd-3.12-2-aarch64.pkg.tar.xz.sig"
if (install_offline_wifi "$fixture/board-cache" "$fixture/board-state/should-not-exist") >/dev/null 2>&1; then
  printf 'Native bootstrap accepted a package without its detached signature.\n' >&2
  exit 1
fi
[[ ! -e "$fixture/board-state/should-not-exist" ]]
printf 'Quartz first-boot Wi-Fi profile and rootfs preflight: OK (offline fixtures).\n'
