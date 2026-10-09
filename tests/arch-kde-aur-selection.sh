#!/usr/bin/env bash
# Mock selection and stage the approved AUR list only in a fixture directory.
# shellcheck disable=SC1090,SC1091,SC2034,SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
selector="$repo/platforms/archlinux/desktop/kde/kmos-kde-package-select.sh"
post="$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
iso="$repo/platforms/archlinux/desktop/kde/kmos-kde-install.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
(
  source "$selector"
  printf '%s\n' tododo-bin "${OPTIONAL_KDE_AUR_PACKAGES[@]}" | LC_ALL=C sort
) > "$fixture/allowed-aur"
grep -vE '^[[:space:]]*(#|$)' "$repo/platforms/archlinux/packages/aur/aur-packages.kmos" | LC_ALL=C sort > "$fixture/repo-aur"
cmp "$fixture/allowed-aur" "$fixture/repo-aur"
(
  unset kmos_INSTALL_AUR
  source "$iso"
  parse_args --profile custom
  [[ "$INSTALL_AUR" == no ]]
)
(
  unset kmos_INSTALL_AUR
  source "$post"
  parse_args --profile custom
  [[ "$INSTALL_AUR" == no ]]
)

(
  source "$selector"
  input=0
  read_selector_line() {
    ((input += 1))
    case "$input" in
      1|2) printf -v "$1" '%s' '' ;;
      3) printf -v "$1" '%s' 'onlyoffice-bin kdrive-bin' ;;
    esac
  }
  select_kde_aur
  [[ "$INSTALL_KDE_AUR" == yes && "$AUR_HELPER" == paru ]]
  [[ "${SELECTED_KDE_AUR_PACKAGES[*]}" == 'onlyoffice-bin kdrive-bin' ]]
) > "$fixture/approved" 2>&1
(
  source "$selector"
  read_selector_line() { printf -v "$1" '%s' 'n'; }
  select_kde_aur
  [[ "$INSTALL_KDE_AUR" == no && ${#SELECTED_KDE_AUR_PACKAGES[@]} == 0 ]]
) > "$fixture/declined" 2>&1
(
  source "$selector"
  read_selector_line() { printf -v "$1" '%s' ''; }
  select_kde_aur
  [[ "$INSTALL_KDE_AUR" == yes && "$AUR_HELPER" == paru ]]
  [[ ${#SELECTED_KDE_AUR_PACKAGES[@]} == 0 ]]
) > "$fixture/default-aur" 2>&1
grep -Fq 'Install AUR? [Y/n]:' "$fixture/default-aur"
if (
  source "$selector"
  SELECTED_KDE_AUR_PACKAGES=(unapproved-aur)
  validate_kde_aur_selection
) > "$fixture/unapproved" 2>&1; then
  printf 'Unapproved AUR package was accepted.\n' >&2; exit 1
fi

(
  source "$post"
  KDE_PROFILE=custom MOUNT_POINT="$fixture/target"
  kmos_KDE_AUR_PACKAGES='onlyoffice-bin kdrive-bin'
  stage_aur_package_list
) > "$fixture/stage-output" 2>&1
[[ $(cat "$fixture/target/usr/share/kmos/aur/aur-packages.kmos") == $'tododo-bin\nonlyoffice-bin\nkdrive-bin' ]]
cmp "$fixture/target/usr/share/kmos/aur/aur-packages.kmos" \
  "$fixture/target/opt/kmos/assets/aur/aur-packages.kmos"
if (
  source "$post"
  KDE_PROFILE=custom MOUNT_POINT="$fixture/invalid-target"
  kmos_KDE_AUR_PACKAGES=unapproved-aur
  stage_aur_package_list
) > "$fixture/invalid-target-output" 2>&1; then
  printf 'Post-installer accepted an unapproved AUR package.\n' >&2; exit 1
fi
[[ ! -e "$fixture/invalid-target/usr/share/kmos/aur/aur-packages.kmos" ]]

# Source-building paru must not uninstall Rust/Cargo selected as personal apps.
(
  source "$iso"
  KDE_PROFILE=custom INSTALL_AUR=yes MOUNT_POINT="$fixture/paru-target"
  get_aur_builder_user() { printf 'fixture-user\n'; }
  warn() { :; }
  success() { :; }
  arch-chroot() {
    printf '%s\n' "$*" >> "$fixture/paru-order"
    case "$*" in
      *'command -v paru'*) [[ -f "$fixture/paru-ready" ]] ;;
      *'git clone https://aur.archlinux.org/paru-bin.git'*) return 1 ;;
      *'makepkg -si'*) touch "$fixture/paru-ready" ;;
    esac
  }
  bootstrap_paru
) > "$fixture/paru-output" 2>&1
grep -Fq 'pacman -S --needed --noconfirm rust cargo' "$fixture/paru-order"
if grep -Fq 'pacman -Rns --noconfirm rust cargo' "$fixture/paru-order"; then
  printf 'Custom paru bootstrap removed user-selected Rust/Cargo.\n' >&2; exit 1
fi

(
  source "$post"
  KDE_PROFILE=custom
  disable_legacy_panel_updates() { :; }
  stage_repo_assets() { :; }
  install_fresh_kmos_panel() { :; }
  apply_splash_defaults() { :; }
  apply_sddm_defaults() { :; }
  apply_lockscreen_defaults() { :; }
  apply_desktop_wallpaper_defaults() { :; }
  apply_color_scheme_defaults() { :; }
  apply_konsole_defaults() { :; }
  apply_yakuake_defaults() { :; }
  apply_dolphin_defaults() { :; }
  apply_kate_defaults() { :; }
  apply_virtual_desktop_defaults() { :; }
  install_extra_fonts() { :; }
  install_aur_packages() { :; }
  record_profile() { :; }
  success() { :; }
  remove_noto_fonts() { printf 'Removed a font from a custom install.\n' >&2; return 1; }
  remove_legacy_kmos_font_packages() { printf 'Removed selected fonts.\n' >&2; return 1; }
  apply_post_tweaks
) > "$fixture/no-pruning" 2>&1

printf 'Optional AUR choice, no-AUR path and staged list: OK (fixtures only).\n'
