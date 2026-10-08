#!/usr/bin/env bash
# Fixture-only test; no network or real profiles are touched.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"
MOUNT_POINT="$fixture/target"
INSTALL_KDE=no
ENABLE_WIFI_AFTER_BOOT=no
mkdir -p "$MOUNT_POINT/opt/kmos/bin" "$fixture/bin" "$MOUNT_POINT/var/lib/iwd"
printf 'existing profile\n' > "$MOUNT_POINT/var/lib/iwd/home.psk"
arch-chroot() { printf '%s\n' "$*" >> "$fixture/services"; }
configure_wired_network_after_boot > "$fixture/install-log"
helper="$MOUNT_POINT/opt/kmos/bin/kmos-headless-wifi.sh"
[[ -x "$helper" && $(stat -c %a "$helper") == 755 ]]
[[ $(cat "$MOUNT_POINT/var/lib/iwd/home.psk") == 'existing profile' ]]
grep -Fq 'systemctl enable iwd.service' "$fixture/services"
grep -Fq 'systemctl enable dhcpcd.service' "$fixture/services"
bash -n "$helper"
"$helper" --help | grep -Fq 'Choose Impala or iwctl'

printf 'personal helper\n' > "$helper"
install_headless_wifi_helper > "$fixture/preserve-log" 2>&1
[[ $(cat "$helper") == 'personal helper' ]]
rm "$helper"
install_headless_wifi_helper > /dev/null

cat > "$fixture/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[[ "${IWD_DOWN:-no}" == no ]]
MOCK
cat > "$fixture/bin/impala" <<'MOCK'
#!/usr/bin/env bash
printf 'impala\n' >> "$CALLS"
[[ "${IMPALA_FAIL:-no}" == no ]]
MOCK
cat > "$fixture/bin/iwctl" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == known-networks && "${2:-}" == list ]]; then
  printf 'known-networks list\n' >> "$CALLS"
  [[ "${LIST_FAIL:-no}" == no ]] || exit 1
  printf 'Network name  Security\nExample Wi-Fi  psk\n'
else
  printf 'iwctl\n' >> "$CALLS"
  [[ "${IWCTL_FAIL:-no}" == no ]]
fi
MOCK
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH" CALLS="$fixture/calls"
# util-linux script supplies a pseudo-terminal for the interactive helper.
command -v script >/dev/null
printf '2\ny\n' | script -q -e -c "$helper" /dev/null > "$fixture/direct-log" 2>&1
[[ $(cat "$CALLS") == $'iwctl\nknown-networks list' ]]
grep -Fq 'station DEVICE get-networks' "$fixture/direct-log"
grep -Fq 'known-networks list' "$fixture/direct-log"
rm "$CALLS"
printf '1\nn\ny\n' | script -q -e -c "$helper" /dev/null > "$fixture/fallback-log" 2>&1
[[ $(cat "$CALLS") == $'impala\niwctl\nknown-networks list' ]]
rm "$CALLS"
printf '1\ny\n' | IMPALA_FAIL=yes script -q -e -c "$helper" /dev/null > "$fixture/impala-fail-log" 2>&1
[[ $(cat "$CALLS") == $'impala\niwctl\nknown-networks list' ]]
rm "$CALLS"
printf '1\ny\ny\n' | script -q -e -c "$helper" /dev/null > "$fixture/success-log" 2>&1
[[ $(cat "$CALLS") == $'impala\nknown-networks list' ]]
rm "$CALLS"
printf '\ny\n' | script -q -e -c "$helper" /dev/null > "$fixture/default-log" 2>&1
[[ $(cat "$CALLS") == $'iwctl\nknown-networks list' ]]
rm "$CALLS"
if printf '2\nn\n' | script -q -e -c "$helper" /dev/null > "$fixture/not-saved-log" 2>&1; then
  echo 'Unconfirmed Wi-Fi persistence was reported as saved.' >&2; exit 1
fi
grep -Fq 'Persistence not confirmed' "$fixture/not-saved-log"
rm "$CALLS"
if printf '2\n' | LIST_FAIL=yes script -q -e -c "$helper" /dev/null > "$fixture/list-fail-log" 2>&1; then
  echo 'Failed known-networks check was reported as saved.' >&2; exit 1
fi
rm "$CALLS"
if printf '2\n' | IWCTL_FAIL=yes script -q -e -c "$helper" /dev/null > "$fixture/iwctl-fail-log" 2>&1; then
  echo 'Failed iwctl session was reported as saved.' >&2; exit 1
fi
[[ $(cat "$CALLS") == iwctl ]]
rm "$CALLS"
if IWD_DOWN=yes script -q -e -c "$helper" /dev/null > "$fixture/down-log" 2>&1; then
  echo 'Wi-Fi setup started with iwd stopped.' >&2; exit 1
fi
[[ ! -e "$CALLS" ]]
printf 'q\n' | script -q -e -c "$helper" /dev/null > "$fixture/quit-log" 2>&1
[[ ! -e "$CALLS" ]]
[[ $(cat "$MOUNT_POINT/var/lib/iwd/home.psk") == 'existing profile' ]]
MOUNT_POINT="$fixture/kde-target" INSTALL_KDE=yes configure_wired_network_after_boot > "$fixture/kde-log"
[[ ! -e "$fixture/kde-target/opt/kmos/bin/kmos-headless-wifi.sh" ]]
MOUNT_POINT="$fixture/handoff-target" ENABLE_WIFI_AFTER_BOOT=yes configure_wired_network_after_boot > "$fixture/handoff-log"
[[ ! -e "$fixture/handoff-target/opt/kmos/bin/kmos-headless-wifi.sh" ]]
echo 'Headless wired Impala/iwctl helper and profile preservation: OK (mocked only).'
