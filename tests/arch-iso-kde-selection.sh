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
  pacman() { [[ "$*" == '-Si -- firefox' ]]; }
  ask_yes_no() { return 1; }
  collect_desktop_config <<< '2'
  [[ "$INSTALL_KDE" == yes && "$INSTALL_KDE_AUR" == yes ]]
  [[ "$kmos_KDE_METAPACKAGES" == kmos-kamilo-productivity && "$kmos_KDE_EXTRA_PACKAGES" == firefox ]]
  [[ "$kmos_KDE_AUR_PACKAGES" == onlyoffice-bin ]]
  [[ "$WIFI_BACKEND" == networkmanager ]]
) > "$fixture/planned" 2>&1
grep -Fq 'KDE desktop (choose packages)' "$fixture/planned"

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
