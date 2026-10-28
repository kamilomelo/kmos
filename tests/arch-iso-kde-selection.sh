#!/usr/bin/env bash
# No real ISO, pacman, formatting or root operations: mocked pre-format plan.
# shellcheck disable=SC1090,SC1091,SC2034,SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
base="$repo/platforms/archlinux/kmos-archlinux-install.sh"
kde="$repo/platforms/archlinux/desktop/kde/kmos-kde-install.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

(
  source "$base"
  KDE_PROFILE=custom
  choose_kde_packages() {
    SELECTED_KDE_METAPACKAGES=(kmos-kamilo-productivity)
    EXTRA_KDE_PACKAGES=(firefox)
  }
  select_kde_aur() {
    INSTALL_KDE_AUR=yes AUR_HELPER=paru
    SELECTED_KDE_AUR_PACKAGES=(onlyoffice-bin)
  }
  pacman() { [[ "$1" == -Si && "$3" != kwin-x11 ]]; }
  ask_yes_no() { return 1; }
  collect_desktop_config <<< '2'
  [[ "$INSTALL_KDE" == yes && "$INSTALL_KDE_AUR" == yes ]]
  [[ "$kmos_KDE_METAPACKAGES" == kmos-kamilo-productivity && "$kmos_KDE_EXTRA_PACKAGES" == firefox ]]
  [[ "$kmos_KDE_AUR_PACKAGES" == onlyoffice-bin ]]
  [[ "$WIFI_BACKEND" == networkmanager ]]
) > "$fixture/planned" 2>&1
grep -Fq 'KDE desktop (choose packages)' "$fixture/planned"

# Exercise the real custom-KDE AUR selector through the ISO installer's path.
(
  source "$base"
  source "$repo/platforms/archlinux/desktop/kde/kmos-kde-package-select.sh"
  KDE_PROFILE=custom
  choose_kde_packages() { :; }
  read_selector_line() {
    if [[ -z ${aur_answer_seen:-} ]]; then
      printf -v "$1" '%s' yay
      aur_answer_seen=1
    else
      printf -v "$1" '%s' ''
    fi
  }
  pacman() { :; }
  collect_desktop_config <<< '2'
  [[ $INSTALL_KDE == yes && $INSTALL_KDE_AUR == yes && $AUR_HELPER == yay ]]
  [[ ${#SELECTED_KDE_AUR_PACKAGES[@]} == 0 ]]
) > "$fixture/custom-yay" 2>&1
grep -Fq 'AUR picks' "$fixture/custom-yay"

if (
  source "$base"
  KDE_PROFILE=custom
  pacman() { [[ "$3" != kwin ]]; }
  verify_kde_repository_packages
) > "$fixture/missing-before-format" 2>&1; then
  printf 'Unavailable KDE package passed disk approval.\n' >&2; exit 1
fi
grep -Fq 'KDE packages unavailable in live-ISO repositories: kwin.' "$fixture/missing-before-format"

if (
  source "$kde"
  MOUNT_POINT="$fixture/target"
  KDE_PACKAGES=(kwin plasma-desktop)
  arch-chroot() { [[ "$*" != *' -Si -- kwin'* ]]; }
  run_target_pacman_without_packagekit_hook() { touch "$fixture/attempted-install"; }
  install_kde_packages
) > "$fixture/missing-in-target" 2>&1; then
  printf 'Unavailable target KDE package passed package preflight.\n' >&2; exit 1
fi
grep -Fq 'KDE packages unavailable in target repositories: kwin.' "$fixture/missing-in-target"
[[ ! -e "$fixture/attempted-install" ]]

(
  source "$base"
  ARCHISO_DIR="$fixture/archiso"
  MOUNT_POINT="$fixture/mnt"
  mkdir -p "$ARCHISO_DIR" "$MOUNT_POINT/etc" "$MOUNT_POINT/boot/grub" \
    "$MOUNT_POINT/usr/share/kmos/metapackages/nodesktop"
  touch "$MOUNT_POINT/etc/arch-release" "$MOUNT_POINT/etc/fstab" \
    "$MOUNT_POINT/boot/grub/grub.cfg" \
    "$MOUNT_POINT/usr/share/kmos/metapackages/nodesktop/PKGBUILD"
  require_root() { :; }
  findmnt() { [[ "$*" == *"$MOUNT_POINT"* ]]; }
  choose_kde_packages() { SELECTED_KDE_METAPACKAGES=() EXTRA_KDE_PACKAGES=(); }
  select_kde_aur() { INSTALL_KDE_AUR=no; SELECTED_KDE_AUR_PACKAGES=(); }
  ask_yes_no() { return 0; }
  run_kde_installer() { printf 'resumed\n' > "$fixture/resumed"; }
  resume_kde
  [[ $(cat "$fixture/resumed") == resumed ]]
  rm "$MOUNT_POINT/boot/grub/grub.cfg" "$fixture/resumed"
  if (resume_kde) > "$fixture/invalid-resume" 2>&1; then exit 1; fi
  [[ ! -e "$fixture/resumed" ]]
) > "$fixture/recovery" 2>&1

if (
  source "$base"
  KDE_PROFILE=custom
  choose_kde_packages() {
    SELECTED_KDE_METAPACKAGES=(kmos-invalid)
    EXTRA_KDE_PACKAGES=()
  }
  select_kde_aur() { INSTALL_KDE_AUR=no; SELECTED_KDE_AUR_PACKAGES=(); }
  pacman() { :; }
  collect_desktop_config <<< '2'
) > "$fixture/bad-plan" 2>&1; then
  printf 'Invalid ISO KDE selection passed pre-format checks.\n' >&2; exit 1
fi
grep -Fq 'Unknown optional group: kmos-invalid' "$fixture/bad-plan"

(
  source "$kde"
  KDE_PROFILE=custom
  INSTALL_AUR=yes
  kmos_KDE_METAPACKAGES=kmos-kamilo-productivity kmos_KDE_EXTRA_PACKAGES=firefox
  select_kde_metapackages
  load_kde_metapackages
  [[ "$INSTALL_AUR" == yes && "$KDE_LOCAL_MANIFESTS_ONLY" == yes ]]
  [[ " ${KDE_PACKAGES[*]} " == *' firefox '* ]]
  [[ " ${KDE_PACKAGES[*]} " == *' kdenlive '* ]]
  [[ " ${KDE_PACKAGES[*]} " == *' firefox-developer-edition '* ]]
  run_target_pacman_without_packagekit_hook() { printf 'Unexpected pruning.\n' >&2; return 1; }
  preserve_kwallet_backend
) > "$fixture/iso-resolved" 2>&1

printf 'ISO KDE selection checked before formatting; custom packages preserved (fixtures only).\n'
