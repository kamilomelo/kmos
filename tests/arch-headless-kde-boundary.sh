#!/usr/bin/env bash
# Characterize the v0.9 ISO -> base -> KDE boundary; never touch a real target.
# Mocked functions and state are consumed by the sourced installers.
# shellcheck disable=SC2034,SC2329,SC1090
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

# The ISO installer must finish base configuration and boot setup before KDE.
(
  # shellcheck disable=SC1091
  source "$repo/platforms/archlinux/kmos-archlinux-install.sh"
  record() { printf '%s\n' "$1" >> "$fixture/iso-order"; }
  init_ui() { :; }
  parse_args() { :; }
  print_banner() { :; }
  require_root() { :; }
  require_tools() { :; }
  advance_step() { :; }
  verify_boot_mode() { :; }
  select_disk() { :; }
  snapshot_target_disk() { :; }
  choose_partition_mode() { :; }
  collect_system_config() { :; }
  collect_desktop_config() { INSTALL_KDE=yes; DESKTOP_CHOICE_MADE=1; }
  preflight_partitions() { :; }
  verify_target_disk_snapshot() { :; }
  confirm_install_plan() { :; }
  format_and_mount() { record format; }
  setup_time() { :; }
  install_base_system() { record base; }
  configure_target_system() { record configure; }
  update_target_system() { record update; }
  install_krub_bootloader() { record bootloader; }
  run_kde_installer() { record kde; }
  final_reboot() { record finish; }
  main
)
[[ $(cat "$fixture/iso-order") == $'format\nbase\nconfigure\nupdate\nbootloader\nkde\nfinish' ]]

# Headless keeps the same base path, but cannot enter the desktop layer.
(
  # shellcheck disable=SC1091
  source "$repo/platforms/archlinux/kmos-archlinux-install.sh"
  INSTALL_KDE=no DESKTOP_CHOICE_MADE=1 INSTALL_HEADLESS_AUR=no
  # shellcheck disable=SC2329 # Must not be reached by the headless path.
  run_kde_installer() { printf 'Unexpected KDE call\n' >&2; exit 1; }
  offer_kde_desktop
)

# The ISO KDE stage still runs against a mounted target; the live-system
# upgrade sources only its package resolver, never its installation main.
kde_script="$repo/platforms/archlinux/desktop/kde/kmos-kde-install.sh"
(
  # shellcheck disable=SC1091 # This installer guards its main when sourced.
  source "$kde_script"
  record() { printf '%s\n' "$1" >> "$fixture/kde-order"; }
  init_ui() { :; }
  parse_args() { :; }
  print_banner() { :; }
  require_root() { :; }
  require_tools() { :; }
  verify_target() { record mounted-target-check; }
  load_kde_metapackages() { record resolve-packages; }
  install_kde_packages() { record packages; }
  remove_unwanted_packages() { record prune; }
  install_kde_assets() { record assets; }
  preserve_kwallet_backend() { record kwallet; }
  migrate_wifi_to_networkmanager() { record wifi-migration; }
  enable_kde_services() { record services; }
  bootstrap_aur_helper() { record aur; }
  run_kde_post_installer() { record post; }
  final_success() { :; }
  KDE_PROFILE=full INSTALL_AUR=no
  main
  [[ " ${SELECTED_METAPACKAGES[*]} " == *' kmos-kde-base '* ]]
  [[ " ${SELECTED_METAPACKAGES[*]} " == *' kmos-network '* ]]
)
[[ $(cat "$fixture/kde-order") == $'mounted-target-check\nresolve-packages\npackages\nprune\nassets\nkwallet\nwifi-migration\nservices\naur\npost' ]]

printf 'Arch base -> KDE ordering and mounted-target boundary: OK (mocked only).\n'
