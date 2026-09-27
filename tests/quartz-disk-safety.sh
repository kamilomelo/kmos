#!/usr/bin/env bash
# Mocked block graph only. No real block device or provisioning command is used.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh"

fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
SCRIPT_DIR="$fixture/script"
mkdir "$SCRIPT_DIR"
disk_a="$fixture/disk-a"
part_a="$fixture/part-a"
crypt="$fixture/crypt-root"
volume="$fixture/lvm-root"
disk_b="$fixture/disk-b"
part_b="$fixture/part-b"
touch "$disk_a" "$part_a" "$crypt" "$volume" "$disk_b" "$part_b"

root_id=253:1
script_id=8:1
root_fs=ext4
ancestor_mode=single
mounted=no
disk_id=8:16
disk_size=17179869184

findmnt() {
  case "$2" in
    FSTYPE) [[ "$4" == / ]] && printf '%s\n' "$root_fs" || printf 'ext4\n' ;;
    MAJ:MIN) [[ "$4" == / ]] && printf '%s\n' "$root_id" || printf '%s\n' "$script_id" ;;
    *) return 1 ;;
  esac
}
lsblk() {
  case "$1 $2" in
    '-dnpr -o') printf '%s disk\n%s disk\n' "$disk_a" "$disk_b" ;;
    '-d -n') printf '%s 16G Mock-card usb 1 1\n' "${*: -1}" ;;
    '-nrpo NAME,TYPE,MAJ:MIN')
      printf '%s disk 8:0\n%s part 8:1\n%s crypt 253:0\n%s lvm 253:1\n%s disk 8:16\n%s part 8:17\n' \
        "$disk_a" "$part_a" "$crypt" "$volume" "$disk_b" "$part_b"
      ;;
    '-srnpo NAME,TYPE')
      case "$3" in
        "$volume")
          printf '%s lvm\n%s crypt\n%s part\n%s disk\n' "$volume" "$crypt" "$part_a" "$disk_a"
          [[ "$ancestor_mode" != raid ]] || printf '%s part\n%s disk\n' "$part_b" "$disk_b"
          ;;
        "$part_a") printf '%s part\n%s disk\n' "$part_a" "$disk_a" ;;
        "$part_b") printf '%s part\n%s disk\n' "$part_b" "$disk_b" ;;
        *) return 1 ;;
      esac
      ;;
    '-dnro TYPE') [[ "$3" == "$disk_a" || "$3" == "$disk_b" ]] && printf 'disk\n' || printf 'part\n' ;;
    '-dnro TRAN') [[ "$3" == "$disk_b" ]] && printf 'usb\n' || printf 'nvme\n' ;;
    '-dnro RM') [[ "$3" == "$disk_b" ]] && printf '1\n' || printf '0\n' ;;
    '-dnro HOTPLUG') [[ "$3" == "$disk_b" ]] && printf '1\n' || printf '0\n' ;;
    '-dnro MODEL') printf 'Mock SD card\n' ;;
    '-dnro SIZE') printf '16G\n' ;;
    '-dnro MAJ:MIN') printf '%s\n' "$disk_id" ;;
    '-nrpo MOUNTPOINTS') [[ "$mounted" == yes ]] && printf '/some/mount\n' || true ;;
    *) return 1 ;;
  esac
}
is_block_device() { [[ -e "$1" ]]; }
blockdev() { [[ "$1" == --getsize64 ]] && printf '%s\n' "$disk_size"; }

expect_rejected() {
  if ("$@") >/dev/null 2>&1; then
    printf 'Unexpectedly accepted: %s\n' "$*" >&2
    exit 1
  fi
}

collect_protected_disks
is_protected_disk "$disk_a"
expect_rejected is_protected_disk "$disk_b"
DEVICE="$disk_a"
expect_rejected validate_device  # LVM over encryption still protects its physical host disk.
DEVICE="$disk_b"
validate_device
ln -s "$disk_a" "$fixture/host-alias"
DEVICE="$fixture/host-alias"
expect_rejected validate_device

DEVICE="$disk_b"
script_id=8:17
expect_rejected validate_device  # Never erase the disk containing the checkout.
script_id=8:1
mounted=yes
expect_rejected validate_device
mounted=no

ancestor_mode=raid
expect_rejected validate_device  # An array root can involve more than one disk.
ancestor_mode=single
root_id=99:99
expect_rejected validate_device  # Unknown graph means refuse, not guess.
root_id=253:1
root_fs=btrfs
expect_rejected validate_device  # Multi-device Btrfs ancestry cannot be proven.
root_fs=ext4

DEVICE=""
select_device <<< 'y' >/dev/null
[[ "$DEVICE" == "$disk_b" ]]
DEVICE=""
expect_rejected select_device <<< 'n'

DEVICE="$disk_b"
ASSUME_YES=1
confirm_erase >/dev/null 2>&1
verify_confirmed_device
disk_id=8:32
expect_rejected verify_confirmed_device
disk_id=8:16
disk_size=32212254720
expect_rejected verify_confirmed_device
disk_size=17179869184
DEVICE="$disk_a"
expect_rejected verify_confirmed_device

printf 'Quartz disk selection and pre-write identity checks: OK (mocked only).\n'
