#!/usr/bin/env bash
# Selection is mocked: no user prompts, root escalation or pacman operations.
# shellcheck disable=SC1090,SC1091,SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
"$script" --help > "$fixture/help"
grep -Fq -- '--install --select' "$fixture/help"

(
  source "$script"
  command() {
    if [[ "$1" == -v && "$2" == fzf ]]; then return 1; fi
    builtin command "$@"
  }
  input=0
  read_selector_line() {
    ((input += 1))
    if ((input == 1)); then printf -v "$1" '%s' '1 5';
    else printf -v "$1" '%s' 'firefox'; fi
  }
  select_live_packages
  [[ ${SELECTED_KDE_METAPACKAGES[*]} == 'kmos-browsers kmos-kde-multimedia' ]]
  [[ ${EXTRA_KDE_PACKAGES[*]} == firefox ]]
  resolve_kde_packages custom "${SELECTED_KDE_METAPACKAGES[@]}"
  printf '%s\n' "${EXTRA_KDE_PACKAGES[@]}"
) > "$fixture/selected" 2> "$fixture/selection-details"
grep -Fxq firefox "$fixture/selected"
grep -Fxq plasma-desktop "$fixture/selected"
if (
  source "$script"
  command() {
    if [[ "$1" == -v && "$2" == fzf ]]; then return 1; fi
    builtin command "$@"
  }
  read_selector_line() { printf -v "$1" '%s' '9'; }
  select_live_packages
) > "$fixture/invalid-output" 2>&1; then
  printf 'Invalid optional metapackage index was accepted.\n' >&2; exit 1
fi
grep -Fq 'Invalid group number: 9' "$fixture/invalid-output"
if (
  source "$script"
  command() {
    if [[ "$1" == -v && "$2" == fzf ]]; then return 1; fi
    builtin command "$@"
  }
  input=0
  read_selector_line() {
    ((input += 1))
    if ((input == 1)); then printf -v "$1" '%s' '';
    else printf -v "$1" '%s' 'kmos-unknown'; fi
  }
  select_live_packages
) > "$fixture/invalid-package" 2>&1; then
  printf 'Unknown kmos package was accepted as a repository package.\n' >&2; exit 1
fi
grep -Fq 'Invalid repository package: kmos-unknown' "$fixture/invalid-package"

(
  source "$script"
  preflight() { :; }
  kde_profile_present() { return 1; }
  upgrade_in_progress() { return 1; }
  package_installed() { return 1; }
  panel_template_available() { :; }
  require_root() { [[ "$*" == '--install --select' ]]; }
  select_live_packages() {
    SELECTED_KDE_METAPACKAGES=(kmos-browsers)
    EXTRA_KDE_PACKAGES=(firefox)
  }
  confirm_install() { :; }
  mark_upgrade() { :; }
  clear_upgrade() { :; }
  service_state() { printf 'active\n'; }
  service_enabled() { printf 'disabled\n'; }
  stage_live_defaults() { :; }
  systemctl() { [[ "$*" == 'enable sddm.service' || "$*" == 'set-default graphical.target' ]]; }
  install() { cat > "$fixture/custom-profile"; }
  pacman() {
    [[ "$1" == -Syu && "$2" == --needed && "$3" == -- ]] || return 1
    printf '%s\n' "${@:4}" > "$fixture/custom-pacman-packages"
  }
  install_layer custom
) > "$fixture/custom-install-output" 2>&1
grep -Fxq firefox "$fixture/custom-pacman-packages"
grep -Fxq plasma-desktop "$fixture/custom-pacman-packages"
[[ $(cat "$fixture/custom-profile") == custom ]]
printf 'Custom KDE selector and package resolution: OK (mocked only).\n'
