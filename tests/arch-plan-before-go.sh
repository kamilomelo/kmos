#!/usr/bin/env bash
# Offline checks: no partitions, accounts, packages or host settings are changed.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"

mock_setup() {
  load_nodesktop_metapackage >/dev/null 2>&1
  require_root() { :; }
  require_tools() { :; }
  pacman() { [[ "$1" == -Si && "$2" == impala ]]; }
  choose_kde_packages() { SELECTED_KDE_METAPACKAGES=(); EXTRA_KDE_PACKAGES=(); }
  select_kde_aur() { INSTALL_KDE_AUR=no; SELECTED_KDE_AUR_PACKAGES=(); }
  verify_boot_mode() { :; }
  select_disk() { TARGET_DISK=/dev/testdisk; }
  lsblk() {
    case "$1" in
      -dnro) [[ "$2" == MAJ:MIN ]] && printf '8:16\n' ;;
      -bdnro) [[ "$2" == SIZE ]] && printf '16000000000\n' ;;
      -nrpo) [[ "${MOUNTED_DISK:-no}" != yes ]] || printf '/mnt/other\n' ;;
      -fp) printf 'NAME SIZE\n/dev/testdisk 16G\n' ;;
      *) return 1 ;;
    esac
  }
  collect_system_config() {
    HOSTNAME=example
    PRIMARY_USER='admin'
    BOOT_MENU_CHOICE_MADE=1
    printf 'choices\n' >> "$fixture/order"
  }
  preflight_partitions() { printf 'preflight\n' >> "$fixture/order"; }
  format_and_mount() { printf 'format\n' >> "$fixture/order"; exit 0; }
  ask_yes_no() {
    case "$1" in
      'Open cfdisk now, before selecting partitions?') [[ "${EDIT_PARTITIONS:-no}" == yes ]] ;;
      'Install an AUR helper and tododo-bin for this headless system?') return 1 ;;
      'Install an AUR helper and AUR desktop packages?') return 1 ;;
      *) printf 'Unplanned installer question: %s\n' "$1" >&2; exit 1 ;;
    esac
  }
  select_boot_partition() {
    BOOT_PARTITION=/dev/testdisk1
    printf 'partitions\n' >> "$fixture/order"
  }
  select_root_partition() { ROOT_PARTITION=/dev/testdisk2; }
  validate_partitions() { :; }
  choose_boot_partition_action() { BOOT_PARTITION_ACTION=reuse; }
  cfdisk() { printf 'cfdisk\n' >> "$fixture/order"; }
  partprobe() { :; }
  udevadm() { :; }
}

# With existing partitions, collect desktop decisions before FORMAT and do not
# format anything until the displayed partitions and EFI action are approved.
(
  mock_setup
  EDIT_PARTITIONS=existing
  main <<< $'2\nFORMAT'
) > "$fixture/existing-output" 2>&1
[[ $(cat "$fixture/order") == $'partitions\nchoices\npreflight\nformat' ]]
grep -q 'KDE desktop (choose packages)' "$fixture/existing-output"
grep -q 'Choose system type \[1/2\] (required, no default)' "$fixture/existing-output"
grep -q 'press Ctrl+C and restart before FORMAT' "$fixture/existing-output"
(
  mock_setup
  EDIT_PARTITIONS=existing
  main <<< $'1\nFORMAT'
) > "$fixture/headless-output" 2>&1
grep -q 'Wi-Fi tools.*Impala + iwd' "$fixture/headless-output"
if (
  mock_setup
  pacman() { return 1; }
  EDIT_PARTITIONS=existing
  main <<< '1'
) > "$fixture/no-impala" 2>&1; then
  printf 'Headless install proceeded without Impala available before FORMAT.\n' >&2; exit 1
fi
grep -q 'cannot approve a headless install' "$fixture/no-impala"
if (
  mock_setup
  EDIT_PARTITIONS=existing
  main <<< $'1\nFORMAT /dev/testdisk2\nEXIT'
) > "$fixture/old-format" 2>&1; then
  printf 'Old disk-specific format token unexpectedly continued.\n' >&2; exit 1
fi
grep -q 'Type FORMAT exactly' "$fixture/old-format"
(
  mock_setup
  KDE_PROFILE=noapps
  collect_desktop_config <<< $'\n2'
  [[ "$DESKTOP_CHOICE_MADE" == 1 && "$INSTALL_KDE" == yes && "$INSTALL_KDE_AUR" == no ]]
) > "$fixture/noapps-output" 2>&1
grep -q 'Enter alone does not select KDE' "$fixture/noapps-output"
(
  mock_setup
  collect_desktop_config <<< '2'
  # shellcheck disable=SC2329 # Must never be called after collecting the choice.
  ask_yes_no() { printf 'Late desktop question after FORMAT.\n' >&2; exit 1; }
  # shellcheck disable=SC2329 # Called by the sourced installer's desktop stage.
  run_kde_installer() { printf 'kde\n' > "$fixture/desktop-execution"; }
  offer_kde_desktop
)
[[ $(cat "$fixture/desktop-execution") == kde ]]
: > "$fixture/desktop-execution"
(
  mock_setup
  INSTALL_HEADLESS_AUR=yes
  DESKTOP_CHOICE_MADE=1
  # shellcheck disable=SC2329 # Must never be called after collecting the choice.
  ask_yes_no() { printf 'Late AUR question after FORMAT.\n' >&2; exit 1; }
  # shellcheck disable=SC2329 # Called by the sourced installer's desktop stage.
  bootstrap_aur_helper() { printf 'aur\n' >> "$fixture/desktop-execution"; }
  install_headless_aur_package() { printf 'tododo-bin\n' >> "$fixture/desktop-execution"; }
  offer_kde_desktop
)
[[ $(cat "$fixture/desktop-execution") == $'aur\ntododo-bin' ]]
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=existing
  main <<< ''
) > "$fixture/no-desktop-choice" 2>&1; then
  printf 'Blank desktop choice unexpectedly continued to FORMAT.\n' >&2; exit 1
fi
[[ $(cat "$fixture/order") == $'partitions\nchoices' ]]
grep -q 'No desktop/headless choice received' "$fixture/no-desktop-choice"
if (
  run_kde_installer() { printf 'KDE must not run without a choice.\n' >&2; exit 1; }
  offer_kde_desktop
) > "$fixture/desktop-unset" 2>&1; then
  printf 'Unset desktop choice unexpectedly ran.\n' >&2; exit 1
fi
grep -q 'Desktop/headless choice was not collected' "$fixture/desktop-unset"
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=existing
  main <<< $'1\nEXIT'
) > "$fixture/declined-output" 2>&1; then
  printf 'Declined FORMAT unexpectedly formatted a partition.\n' >&2; exit 1
fi
[[ $(cat "$fixture/order") == $'partitions\nchoices\npreflight' ]]

# cfdisk opens immediately after the early yes/no choice; FORMAT still gates
# filesystem writes after all choices and a concrete partition summary.
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=yes
  main <<< $'1\nEXIT'
) > "$fixture/edit-declined" 2>&1; then
  printf 'Declined post-cfdisk FORMAT unexpectedly continued.\n' >&2; exit 1
fi
[[ $(cat "$fixture/order") == $'cfdisk\npartitions\nchoices\npreflight' ]]
: > "$fixture/order"
(
  mock_setup
  EDIT_PARTITIONS=yes
  main <<< $'1\nFORMAT'
) > "$fixture/edit-output" 2>&1
[[ $(cat "$fixture/order") == $'cfdisk\npartitions\nchoices\npreflight\nformat' ]]
grep -q 'cfdisk can write the partition table' "$fixture/edit-output"
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=yes
  main <<< $'1\nEXIT'
) > "$fixture/edit-no-format" 2>&1; then
  printf 'A declined post-cfdisk format was accepted.\n' >&2; exit 1
fi
[[ $(cat "$fixture/order") == $'cfdisk\npartitions\nchoices\npreflight' ]]
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=yes
  MOUNTED_DISK=yes
  main <<< $'1\nFORMAT'
) > "$fixture/mounted-disk" 2>&1; then
  printf 'cfdisk accepted a mounted disk.\n' >&2; exit 1
fi
[[ ! -s "$fixture/order" ]]
grep -q 'partition on the selected disk is mounted' "$fixture/mounted-disk"

# If the selected disk changes identity, never proceed to disk edits.
if (
  mock_setup
  TARGET_DISK=/dev/testdisk
  snapshot_target_disk
  lsblk() { printf '8:32\n'; }
  verify_target_disk_snapshot
) > "$fixture/changed-device" 2>&1; then
  printf 'A changed disk identity was accepted.\n' >&2; exit 1
fi
grep -q 'identity or size changed' "$fixture/changed-device"
if (
  preflight_partitions() { printf 'Unexpected preflight without FORMAT.\n' >&2; exit 1; }
  format_and_mount
) > "$fixture/no-format-token" 2>&1; then
  printf 'Formatting without the approval token was allowed.\n' >&2; exit 1
fi
grep -q 'Formatting requires the explicit FORMAT' "$fixture/no-format-token"

# Headless first boot prefers the handed-off iwd profile. WPA is neither
# installed nor configured unless that profile is unavailable.
(
  mock_setup
  WIFI_HANDOFF_DIR="$fixture/iwd-handoff"
  MOUNT_POINT="$fixture/iwd-target"
  ENABLE_WIFI_AFTER_BOOT=yes
  WIFI_ADAPTER=wlan0 WIFI_SSID=example WIFI_PASSWORD=fixture-secret
  mkdir -p "$WIFI_HANDOFF_DIR/iwd" "$MOUNT_POINT"
  printf '[Security]\nPassphrase=fixture-secret\n' > "$WIFI_HANDOFF_DIR/iwd/example.psk"
  collect_desktop_config <<< '1'
  [[ "$WIFI_BACKEND" == iwd && " ${BASE_PACKAGES[*]} " == *' impala '* ]]
  [[ " ${BASE_PACKAGES[*]} " != *' wpa_supplicant '* ]]
  arch-chroot() { printf '%s\n' "$*" >> "$fixture/iwd-services"; }
  chown() { :; }
  configure_wifi_after_boot
  [[ ! -e "$MOUNT_POINT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" ]]
  grep -q 'systemctl enable iwd.service systemd-resolved.service' "$fixture/iwd-services"
  if grep -q 'systemctl enable wpa_supplicant' "$fixture/iwd-services"; then
    printf 'WPA was enabled alongside iwd.\n' >&2; exit 1
  fi
) > "$fixture/iwd-output" 2>&1
(
  mock_setup
  WIFI_HANDOFF_DIR="$fixture/wpa-handoff"
  MOUNT_POINT="$fixture/wpa-target"
  ENABLE_WIFI_AFTER_BOOT=yes
  WIFI_ADAPTER=wlan0 WIFI_SSID=example WIFI_PASSWORD=fixture-secret
  mkdir -p "$WIFI_HANDOFF_DIR" "$MOUNT_POINT"
  collect_desktop_config <<< '1'
  [[ "$WIFI_BACKEND" == wpa && " ${BASE_PACKAGES[*]} " == *' wpa_supplicant '* ]]
  arch-chroot() { printf '%s\n' "$*" >> "$fixture/wpa-services"; }
  configure_wifi_after_boot
  [[ -f "$MOUNT_POINT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" ]]
  grep -q 'systemctl enable wpa_supplicant@wlan0.service' "$fixture/wpa-services"
  if grep -q 'systemctl enable iwd.service' "$fixture/wpa-services"; then
    printf 'iwd was enabled alongside the WPA fallback.\n' >&2; exit 1
  fi
) > "$fixture/wpa-output" 2>&1
(
  mock_setup
  WIFI_HANDOFF_DIR="$fixture/kde-handoff"
  MOUNT_POINT="$fixture/kde-target"
  ENABLE_WIFI_AFTER_BOOT=yes
  WIFI_ADAPTER=wlan0 WIFI_SSID=example WIFI_PASSWORD=fixture-secret
  mkdir -p "$WIFI_HANDOFF_DIR" "$MOUNT_POINT"
  collect_desktop_config <<< '2'
  [[ "$WIFI_BACKEND" == networkmanager && " ${BASE_PACKAGES[*]} " == *' wpa_supplicant '* ]]
  arch-chroot() { :; }
  configure_wifi_after_boot
  [[ -f "$MOUNT_POINT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" ]]
) > "$fixture/kde-wifi-output" 2>&1
(
  INSTALL_KDE=no
  ENABLE_WIFI_AFTER_BOOT=no
  MOUNT_POINT="$fixture/wired-target"
  arch-chroot() { printf '%s\n' "$*" >> "$fixture/wired-services"; }
  configure_wired_network_after_boot
  grep -q 'systemctl enable iwd.service' "$fixture/wired-services"
  grep -q 'systemctl enable dhcpcd.service' "$fixture/wired-services"
) > "$fixture/wired-output" 2>&1
printf 'Arch cfdisk is early; all choices and FORMAT still precede filesystem writes (mocked).\n'
