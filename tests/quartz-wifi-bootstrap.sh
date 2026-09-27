#!/usr/bin/env bash
# Offline fixtures only; no network services, disk writers or actual sudo.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh"
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/wifi-profile.sh"

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

# Fake ARM repository contents, with no external network or actual card.
mkdir -p "$fixture/repo"

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
  printf 'test signature\n' > "$fixture/repo/$filename.sig"
  mkdir -p "$fixture/repo-db/$package-$version"
  {
    printf '%%FILENAME%%\n%s\n\n' "$filename"
    printf '%%SHA256SUM%%\n%s\n\n' "$(sha256sum "$fixture/repo/$filename" | awk '{print $1}')"
    printf '%%VERSION%%\n%s\n' "$version"
  } > "$fixture/repo-db/$package-$version/desc"
done
bsdtar -cf "$fixture/repo/extra.db" -C "$fixture/repo-db" .
download() { cp -- "$fixture/repo/${1##*/}" "$2"; }
WORK_DIR="$fixture/work"
mkdir "$WORK_DIR"
stage_offline_wifi_packages
[[ -f "$WIFI_PACKAGE_DIR/ell-0.83-1-aarch64.pkg.tar.xz" ]]
[[ -f "$WIFI_PACKAGE_DIR/iwd-3.12-2-aarch64.pkg.tar.xz.sig" ]]

# Mock the native first-boot pacman transaction; no real packages are installed.
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/wifi-offline-packages.sh"
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

# Exercise the board-side retry loop with mocked association and DHCP only.
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
iwctl() {
  [[ "$1" == station && "$2" == wlan0 ]] || return 1
  if [[ "$3" == show ]]; then
    printf '  Connected network    Good Wifi\n'
  elif [[ "$3" == scan ]]; then
    printf 'scanned\n' >> "$fixture/attempts"
  elif [[ "$3" == get-networks ]]; then
    printf 'Network name                 Security\n  Bad Wifi                    psk\n  Good Wifi                   psk\n'
  else
    [[ "$3" == connect ]] || return 1
    printf '%s\n' "$4" >> "$fixture/attempts"
    [[ "$4" == 'Good Wifi' ]]
  fi
}
ip() {
  if [[ "$1" == -4 && "$2" == -o && "$3" == address ]]; then
    printf 'wlan0 192.0.2.10\n'
  elif [[ "$1" == -4 && "$2" == route && "$3" == show ]]; then
    printf 'default via 192.0.2.1 dev wlan0\n'
  else
    return 1
  fi
}
systemctl() {
  if [[ "$1" == restart && "$2" == iwd.service ]]; then
    printf 'restarted\n' >> "$fixture/attempts"
  else
    [[ "$1" == is-active || "$1" == is-enabled ]] && [[ "$2" == --quiet ]]
  fi
}
sleep() { :; }
mkdir -m 700 "$fixture/retry-profiles"
scan_wifi_networks wlan0 >/dev/null
[[ "${NETWORK_NAMES[1]}" == 'Good Wifi' ]]
if wifi_connection_ready wlan0 "$fixture/retry-profiles" 'Good Wifi'; then
  printf 'An IP address without a saved profile was accepted as persistent.\n' >&2
  exit 1
fi
if ! printf '1\nwrong password\n\n\n2\ncorrect password\n\n' \
  | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >"$fixture/retry-output" 2>&1; then
  cat "$fixture/retry-output" >&2
  exit 1
fi
[[ ! -e "$fixture/retry-profiles/Bad Wifi.psk" ]]
grep -qx 'Passphrase=correct password' "$fixture/retry-profiles/Good Wifi.psk"
[[ $(stat -c %a "$fixture/retry-profiles/Good Wifi.psk") == 600 ]]
[[ $(cat "$fixture/attempts") == $'scanned\nrestarted\nscanned\nBad Wifi\nscanned\nrestarted\nscanned\nGood Wifi' ]]
wifi_connection_ready wlan0 "$fixture/retry-profiles" 'Good Wifi'
reconnect_saved_wifi wlan0 "$fixture/retry-profiles" 'Good Wifi'
[[ $(tail -n 3 "$fixture/attempts") == $'restarted\nscanned\nGood Wifi' ]]
cp "$fixture/retry-profiles/Good Wifi.psk" "$fixture/good-profile"
printf 'Good Wifi\n\n' | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >"$fixture/saved-output" 2>&1
cmp "$fixture/good-profile" "$fixture/retry-profiles/Good Wifi.psk"
grep -q 'Existing saved Wi-Fi profile reconnected successfully' "$fixture/saved-output"

# A failed replacement must restore the original profile, even if the user stops.
write_iwd_profile "$fixture/retry-profiles" 'Old Wifi' 'original password' false
cp "$fixture/retry-profiles/Old Wifi.psk" "$fixture/original-profile"
printf 'Old Wifi\nn\nincorrect password\n\ny\nc\n' \
  | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >"$fixture/restore-output" 2>&1 && {
    printf 'Cancelling Wi-Fi retries incorrectly succeeded.\n' >&2
    exit 1
  }
cmp "$fixture/original-profile" "$fixture/retry-profiles/Old Wifi.psk"
[[ $(stat -c %a "$fixture/retry-profiles/Old Wifi.psk") == 600 ]]
[[ $(find "$fixture/retry-profiles" -maxdepth 1 -name '.kmos-wifi-backup.*' | wc -l) == 0 ]]

# Declining replacement keeps the old profile and allows a clean cancellation.
printf 'Old Wifi\nn\nunused password\n\nn\nCANCEL\n' \
  | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >/dev/null 2>&1 && {
    printf 'Declining replacement incorrectly succeeded.\n' >&2
    exit 1
  }
cmp "$fixture/original-profile" "$fixture/retry-profiles/Old Wifi.psk"

# Association success with no DHCP route cannot be reported as success.
ip() { [[ "$1" == -4 && "$2" == -o && "$3" == address ]] && printf 'wlan0 192.0.2.10\n'; }
networkctl() { :; }
printf 'Good Wifi\nn\ncorrect password\n\ny\nc\n' \
  | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >"$fixture/dhcp-output" 2>&1 && {
    printf 'Wi-Fi without a DHCP route incorrectly succeeded.\n' >&2
    exit 1
  }
grep -q 'Associated with Good Wifi, but Wi-Fi DHCP/default route is not ready' "$fixture/dhcp-output"
grep -qx 'Passphrase=correct password' "$fixture/retry-profiles/Good Wifi.psk"

# Explicit cancellation before credential entry must leave profiles untouched.
if printf 'CANCEL\n' | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >/dev/null 2>&1; then
  printf 'Cancelling before entry incorrectly succeeded.\n' >&2
  exit 1
else
  [[ $? == 2 ]] || { printf 'Cancellation did not signal the explicit Ethernet choice.\n' >&2; exit 1; }
fi
cmp "$fixture/original-profile" "$fixture/retry-profiles/Old Wifi.psk"

# Regression: the displayed KASA SSID must still be found after iwd restarts.
(
  # Invoked by functions sourced from the board helper.
  # shellcheck disable=SC2329
  iwctl() {
    [[ "$1" == station && "$2" == wlan0 ]] || return 1
    case "$3" in
      scan) printf 'scanned\n' >> "$fixture/kasa-attempts" ;;
      get-networks) printf 'Network name      Security\nKASA              psk\n' ;;
      show) printf '  Connected network    KASA\n' ;;
      connect) [[ "$4" == KASA ]] && printf 'connected KASA\n' >> "$fixture/kasa-attempts" ;;
      *) return 1 ;;
    esac
  }
  # shellcheck disable=SC2329
  ip() {
    if [[ "$2" == -o ]]; then printf 'wlan0 192.0.2.10\n';
    else printf 'default via 192.0.2.1 dev wlan0\n'; fi
  }
  scan_wifi_networks wlan0 >/dev/null
  printf 'KASA\ncorrect password\n\n' \
    | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >"$fixture/kasa-output" 2>&1
  [[ $(tail -n 3 "$fixture/kasa-attempts") == $'scanned\nscanned\nconnected KASA' ]]
  grep -Fxq 'Passphrase=correct password' "$fixture/retry-profiles/KASA.psk"
)
printf 'Quartz first-boot Wi-Fi profile and rootfs preflight: OK (offline fixtures).\n'
