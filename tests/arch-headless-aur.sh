#!/usr/bin/env bash
# Headless AUR selection and sudoers cleanup against a fixture target only.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"
MOUNT_POINT="$fixture/target"
PRIMARY_USER=alice
mkdir -p "$MOUNT_POINT/etc/sudoers.d"
sudoers="$MOUNT_POINT/etc/sudoers.d/10-kmos-headless-aur"

arch-chroot() {
  [[ "$1" == "$MOUNT_POINT" ]]
  shift
  if [[ "$1" == pacman && "$2" == -Q && "$3" == tododo-bin ]]; then
    [[ "${ALREADY_INSTALLED:-no}" == yes || -f "$fixture/installed-package" ]]
    return
  fi
  [[ "$1" == runuser && "$2" == -u && "$3" == alice && "$4" == -- ]]
  printf '%s\n' "${*:5}" >> "$fixture/aur-calls"
  [[ -f "$sudoers" && $(stat -c %a "$sudoers") == 440 ]]
  [[ "${FAIL_AUR:-no}" == no ]] || return 1
  [[ "${FAKE_SUCCESS:-no}" == yes ]] || touch "$fixture/installed-package"
}

AUR_HELPER=paru
install_headless_aur_package > "$fixture/paru-log" 2>&1
[[ $(cat "$fixture/aur-calls") == 'paru --noprovides -S --needed --noconfirm --skipreview tododo-bin' ]]
[[ ! -e "$sudoers" ]]
rm "$fixture/installed-package"
AUR_HELPER=yay
install_headless_aur_package > "$fixture/yay-log" 2>&1
grep -Fxq 'yay -S --needed --noconfirm --answerclean None --answerdiff None tododo-bin' "$fixture/aur-calls"
[[ ! -e "$sudoers" ]]

rm "$fixture/installed-package"
if FAIL_AUR=yes install_headless_aur_package > "$fixture/failure-log" 2>&1; then
  echo 'Failed AUR install was reported as successful.' >&2; exit 1
fi
[[ ! -e "$sudoers" ]]
if FAKE_SUCCESS=yes install_headless_aur_package > "$fixture/no-package-log" 2>&1; then
  echo 'Missing tododo-bin was reported as installed.' >&2; exit 1
fi
[[ ! -e "$sudoers" ]]
before=$(wc -l < "$fixture/aur-calls")
ALREADY_INSTALLED=yes install_headless_aur_package > "$fixture/installed-log" 2>&1
[[ $(wc -l < "$fixture/aur-calls") == "$before" && ! -e "$sudoers" ]]

printf 'personal sudoers rule\n' > "$sudoers"
if install_headless_aur_package > "$fixture/preserve-log" 2>&1; then
  echo 'Existing sudoers file was overwritten.' >&2; exit 1
fi
[[ $(cat "$sudoers") == 'personal sudoers rule' ]]
(
  DESKTOP_CHOICE_MADE=1
  INSTALL_KDE=no
  INSTALL_HEADLESS_AUR=no
  bootstrap_aur_helper() { echo 'Unexpected AUR helper install.' >&2; exit 1; }
  install_headless_aur_package() { echo 'Unexpected tododo-bin install.' >&2; exit 1; }
  offer_kde_desktop
)
echo 'Headless paru/yay tododo-bin install and sudoers cleanup: OK (mocked only).'
