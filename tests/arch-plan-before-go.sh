#!/usr/bin/env bash
# Offline checks: no partitions, accounts, packages or host settings are changed.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"

mock_setup() {
  require_root() { :; }
  require_tools() { :; }
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
    printf 'choices\n' >> "$fixture/order"
  }
  preflight_partitions() { printf 'preflight\n' >> "$fixture/order"; }
  format_and_mount() { printf 'format\n' >> "$fixture/order"; exit 0; }
  ask_yes_no() {
    case "$1" in
      'Edit the partition table with cfdisk after the first GO?') [[ "${EDIT_PARTITIONS:-no}" == yes ]] ;;
      'Do you want to install a desktop?') [[ "${KDE_CHOICE:-no}" == yes ]] ;;
      'Install an AUR helper for this headless system?') return 1 ;;
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

# With existing partitions, collect desktop decisions before GO and do not
# write or format anything until the exact partitions/action are confirmed.
(
  mock_setup
  EDIT_PARTITIONS=existing
  KDE_CHOICE=yes
  main <<< 'FORMAT /dev/testdisk2 KEEP /dev/testdisk1'
) > "$fixture/existing-output" 2>&1
[[ $(cat "$fixture/order") == $'partitions\nchoices\npreflight\nformat' ]]
grep -q 'KDE full' "$fixture/existing-output"
(
  mock_setup
  KDE_CHOICE=yes
  collect_desktop_config
  # shellcheck disable=SC2329 # Must never be called after collecting the choice.
  ask_yes_no() { printf 'Late desktop question after GO.\n' >&2; exit 1; }
  # shellcheck disable=SC2329 # Called by the sourced installer's desktop stage.
  run_kde_installer() { printf 'kde\n' > "$fixture/desktop-execution"; }
  offer_kde_desktop
)
[[ $(cat "$fixture/desktop-execution") == kde ]]
(
  mock_setup
  KDE_CHOICE=no
  INSTALL_HEADLESS_AUR=yes
  # shellcheck disable=SC2329 # Must never be called after collecting the choice.
  ask_yes_no() { printf 'Late AUR question after GO.\n' >&2; exit 1; }
  # shellcheck disable=SC2329 # Called by the sourced installer's desktop stage.
  bootstrap_aur_helper() { printf 'aur\n' > "$fixture/desktop-execution"; }
  offer_kde_desktop
)
[[ $(cat "$fixture/desktop-execution") == aur ]]
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=existing
  main <<< 'EXIT'
) > "$fixture/declined-output" 2>&1; then
  printf 'Declined GO unexpectedly formatted a partition.\n' >&2; exit 1
fi
[[ $(cat "$fixture/order") == $'partitions\nchoices\npreflight' ]]

# cfdisk is not reachable before the first disk-specific GO. After it runs,
# the concrete partitions need a separate FORMAT confirmation.
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=yes
  main <<< 'EXIT'
) > "$fixture/edit-declined" 2>&1; then
  printf 'Declined disk edit unexpectedly continued.\n' >&2; exit 1
fi
[[ $(cat "$fixture/order") == choices ]]
: > "$fixture/order"
(
  mock_setup
  EDIT_PARTITIONS=yes
  main <<< $'GO /dev/testdisk\nFORMAT /dev/testdisk2 KEEP /dev/testdisk1'
) > "$fixture/edit-output" 2>&1
[[ $(cat "$fixture/order") == $'choices\ncfdisk\npartitions\npreflight\nformat' ]]
grep -q 'cfdisk may write the partition table' "$fixture/edit-output"
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=yes
  main <<< $'GO /dev/testdisk\nEXIT'
) > "$fixture/edit-no-format" 2>&1; then
  printf 'A declined post-cfdisk format was accepted.\n' >&2; exit 1
fi
[[ $(cat "$fixture/order") == $'choices\ncfdisk\npartitions\npreflight' ]]
: > "$fixture/order"
if (
  mock_setup
  EDIT_PARTITIONS=yes
  MOUNTED_DISK=yes
  main <<< $'GO /dev/testdisk\nFORMAT /dev/testdisk2 KEEP /dev/testdisk1'
) > "$fixture/mounted-disk" 2>&1; then
  printf 'cfdisk accepted a mounted disk.\n' >&2; exit 1
fi
[[ $(cat "$fixture/order") == choices ]]
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
  preflight_partitions() { printf 'Unexpected preflight without GO.\n' >&2; exit 1; }
  format_and_mount
) > "$fixture/no-format-token" 2>&1; then
  printf 'Formatting without the approval token was allowed.\n' >&2; exit 1
fi
grep -q 'Formatting requires the exact' "$fixture/no-format-token"
if (
  TARGET_DISK=/dev/testdisk
  lsblk() { :; }
  choose_partitions edit
) > "$fixture/no-edit-token" 2>&1; then
  printf 'cfdisk was reachable without disk-specific GO.\n' >&2; exit 1
fi
grep -q 'cfdisk requires the disk-specific GO' "$fixture/no-edit-token"
printf 'Arch decisions precede GO; cfdisk and format remain gated (mocked).\n'
