#!/usr/bin/env bash
# Offline fixtures only; no network services, disk writers or actual sudo.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh"
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"

# SD preparation copies exactly one self-contained board-side Wi-Fi script.
mkdir -p "$fixture/board/root"
install -m 0755 "$repo/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" "$fixture/board/root/connect-quartz64b-wifi.sh"
(
  # shellcheck disable=SC1091
  source "$fixture/board/root/connect-quartz64b-wifi.sh"
  validate_wifi_credentials 'Test Wifi' 'safe secret 123'
)

if validate_wifi_credentials '../outside' 'safe secret 123'; then
  printf 'Unsafe SSID was accepted.\n' >&2
  exit 1
fi
if validate_wifi_credentials 'Test Wifi' 'short'; then
  printf 'Short Wi-Fi password was accepted.\n' >&2
  exit 1
fi

configure_iwd_main "$fixture/iwd-main.conf"
grep -Fxq 'EnableNetworkConfiguration=false' "$fixture/iwd-main.conf"
printf '\n[DriverQuirks]\nSaeDisable=brcmfmac\n' >> "$fixture/iwd-main.conf"
cp "$fixture/iwd-main.conf" "$fixture/iwd-main-before"
configure_iwd_main "$fixture/iwd-main.conf"
cmp "$fixture/iwd-main-before" "$fixture/iwd-main.conf"
printf '[General]\nEnableNetworkConfiguration=true\n' > "$fixture/conflicting-iwd.conf"
if (configure_iwd_main "$fixture/conflicting-iwd.conf") >"$fixture/iwd-error" 2>&1; then
  printf 'Accepted conflicting iwd DHCP configuration.\n' >&2
  exit 1
fi
grep -q 'conflicts with networkd' "$fixture/iwd-error"

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

# Board-side tests: the x86-style flow connects first; iwd supplies the profile.
mkdir -m 700 "$fixture/retry-profiles"
iwctl() {
  if [[ "$1" == --passphrase ]]; then
    [[ "$3" == station && "$4" == wlan0 && "$5" == connect ]] || return 1
    printf '%s\n' "$6" >> "$fixture/attempts"
    [[ "$6" == 'Good Wifi' ]] || return 1
    # iwd, not the KMOS script, creates this working profile after association.
    printf '[Settings]\n\n[Security]\nPassphrase=%s\n' "$2" > "$fixture/retry-profiles/Good Wifi.psk"
    chmod 600 "$fixture/retry-profiles/Good Wifi.psk"
  else
    [[ "$1" == station && "$2" == wlan0 ]] || return 1
    case "$3" in
      show) [[ -f "$fixture/retry-profiles/Good Wifi.psk" ]] && printf '  Connected network    Good Wifi\n' ;;
      scan)
        printf 'scanned\n' >> "$fixture/attempts"
        [[ ! -f "$fixture/scan-in-progress" ]]
        ;;
      get-networks) printf 'Network name      Security\nBad Wifi          psk\nGood Wifi         psk\n' ;;
      connect) [[ "$4" == 'Good Wifi' ]] ;;
      *) return 1 ;;
    esac
  fi
}
# shellcheck disable=SC2329 # Invoked by the sourced board Wi-Fi helper.
timeout() {
  [[ "$1" == --foreground && "$2" == 45s && "$3" == iwctl ]] || return 1
  printf 'connecting\n' >> "$fixture/attempts"
  iwctl "${@:4}"
}
ip() {
  if [[ "$1" == -4 && "$2" == -o && "$3" == address ]]; then
    printf 'wlan0 192.0.2.10\n'
  elif [[ "$1" == -4 && "$2" == route && "$3" == show ]]; then
    [[ ! -e "$fixture/no-route" ]] && printf 'default via 192.0.2.1 dev wlan0\n'
  else
    return 1
  fi
}
ping() {
  [[ "$1" == -I && "$2" == wlan0 && "$3" == -c && "$4" == 3 && "$5" == -W && "$6" == 3 ]] || return 1
  [[ ! -e "$fixture/no-ping" ]]
}
systemctl() { [[ ( "$1" == is-active || "$1" == is-enabled ) && "$2" == --quiet ]]; }
stat() {
  if [[ "$1" == -c && "$2" == %u ]]; then printf '0\n';
  else command stat "$@"; fi
}
networkctl() { :; }
sleep() { :; }
scan_wifi_networks wlan0 >/dev/null
[[ "${NETWORK_NAMES[1]}" == 'Good Wifi' ]]
touch "$fixture/scan-in-progress"
scan_wifi_networks wlan0 >/dev/null
[[ "${NETWORK_NAMES[1]}" == 'Good Wifi' ]]
rm "$fixture/scan-in-progress"
if wifi_connection_ready wlan0 "$fixture/retry-profiles" 'Good Wifi'; then
  printf 'An IP address without a working iwd profile was accepted.\n' >&2
  exit 1
fi
printf '1\nwrong password\n\nc\n' | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >/dev/null 2>&1 && exit 1
[[ ! -e "$fixture/retry-profiles/Bad Wifi.psk" ]]
printf '2\ncorrect password\n\n' | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >"$fixture/output" 2>&1
grep -q 'Working iwd profile' "$fixture/output"
if grep -q 'correct password' "$fixture/output"; then
  printf 'Wi-Fi password appeared in helper output.\n' >&2; exit 1
fi
grep -qx 'Passphrase=correct password' "$fixture/retry-profiles/Good Wifi.psk"
[[ $(cat "$fixture/attempts") == *$'connecting\nBad Wifi\nconnecting\nGood Wifi' ]]
[[ $(grep -c '^scanned$' "$fixture/attempts") == 2 ]]
(
  # A stuck iwctl command must stop; no unverified profile is accepted.
  # shellcheck disable=SC2329 # Invoked by the sourced board helper.
  timeout() { [[ "$1" == --foreground && "$2" == 45s ]] && return 124; }
  if printf 'Never Wifi\nvalid password\n\nc\n' \
    | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >"$fixture/timed-out" 2>&1; then
    printf 'Timed-out connection incorrectly succeeded.\n' >&2; exit 1
  fi
)
grep -q 'iwctl timed out' "$fixture/timed-out"
[[ ! -e "$fixture/retry-profiles/Never Wifi.psk" ]]
if grep -q 'valid password' "$fixture/timed-out"; then
  printf 'Timed-out password appeared in helper output.\n' >&2; exit 1
fi
wifi_connection_ready wlan0 "$fixture/retry-profiles" 'Good Wifi'
touch "$fixture/no-route"
if wifi_connection_ready wlan0 "$fixture/retry-profiles" 'Good Wifi'; then
  printf 'Wi-Fi without a route was reported as connected.\n' >&2; exit 1
fi
rm "$fixture/no-route"
touch "$fixture/no-ping"
if wifi_connection_ready wlan0 "$fixture/retry-profiles" 'Good Wifi'; then
  printf 'Wi-Fi without adapter-bound internet was reported as connected.\n' >&2; exit 1
fi
rm "$fixture/no-ping"
cp "$fixture/retry-profiles/Good Wifi.psk" "$fixture/original-profile"
touch "$fixture/no-route"
printf 'Good Wifi\nn\nwrong replacement\n\nc\n' \
  | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >"$fixture/replacement-output" 2>&1 && {
    printf 'Unverified replacement incorrectly succeeded.\n' >&2; exit 1
  }
cmp "$fixture/original-profile" "$fixture/retry-profiles/Good Wifi.psk"
if grep -q 'wrong replacement' "$fixture/replacement-output"; then
  printf 'Replacement password appeared in helper output.\n' >&2; exit 1
fi
rm "$fixture/no-route"
if printf 'CANCEL\n' | connect_wifi_with_retries wlan0 "$fixture/retry-profiles" >/dev/null 2>&1; then
  printf 'Cancellation incorrectly succeeded.\n' >&2; exit 1
else
  [[ $? == 2 ]]
fi
printf 'Quartz first-boot Wi-Fi profile and rootfs preflight: OK (offline fixtures).\n'
