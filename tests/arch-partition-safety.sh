#!/usr/bin/env bash
# Pure mocked-device tests. Never invoke mkfs, mount, or the installer entry point.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# Sourcing defines functions without running the installer.
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
TARGET_DISK="$fixture/disk"
BOOT_PARTITION="$fixture/efi"
ROOT_PARTITION="$fixture/root"
disk_root="$ROOT_PARTITION"
other_partition="$fixture/other"
touch "$TARGET_DISK" "$BOOT_PARTITION" "$ROOT_PARTITION" "$other_partition"

efi_type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
boot_type="$efi_type"
root_type=0fc63daf-8483-4772-8e79-3d69d8477de4
boot_fstype=vfat
root_fstype=ext4
boot_size=1073741824
mounted_partition=""
answer=yes
selected_efi_contents=arch
windows_separate=yes
firmware_windows_uuid=11111111-1111-1111-1111-111111111111
selected_uuid=22222222-2222-2222-2222-222222222222
firmware_readable=yes

block_device() { [[ -e "$1" ]]; }
lsblk() {
  local flags="$1"
  local device="${*: -1}"
  case "$flags" in
    -nrpo)
      printf '%s disk\n%s part\n%s part\n' "$TARGET_DISK" "$fixture/efi" "$disk_root"
      ;;
    -dnro)
      case "$2" in
        TYPE) [[ "$device" == "$TARGET_DISK" ]] && echo disk || echo part ;;
        PARTTYPE) [[ "$device" == "$BOOT_PARTITION" ]] && echo "$boot_type" || echo "$root_type" ;;
        FSTYPE) [[ "$device" == "$BOOT_PARTITION" ]] && echo "$boot_fstype" || echo "$root_fstype" ;;
        MOUNTPOINTS) [[ "$device" == "$mounted_partition" ]] && echo /already-mounted || true ;;
        MAJ:MIN) [[ "$device" == "$BOOT_PARTITION" ]] && echo 8:1 || echo 8:2 ;;
        PARTUUID) echo "$selected_uuid" ;;
        *) return 1 ;;
      esac
      ;;
    -bdnro) [[ "$2" == SIZE ]] && echo "$boot_size" ;;
    *) return 1 ;;
  esac
}
ask_yes_no() { [[ "$answer" == yes ]]; }
selected_efi_identity() { printf '%s\n' "$selected_efi_contents"; }
scan_windows_efi_loaders() { [[ "$windows_separate" == yes ]] && printf '%s|ABCD-1234|8:2\n' "$other_partition"; }
efibootmgr() {
  [[ "$firmware_readable" == yes ]] || return 1
  printf 'Boot0009* Windows Boot Manager HD(1,GPT,%s,0x800,0x10000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n' "$firmware_windows_uuid"
}

expect_rejected() {
  if ("$@") >/dev/null 2>&1; then
    printf 'Unexpectedly accepted: %s\n' "$*" >&2
    exit 1
  fi
}

validate_partitions
ln -s "$BOOT_PARTITION" "$fixture/efi-alias"
BOOT_PARTITION="$fixture/efi-alias"
validate_partitions  # A symlink to a partition on the target disk is acceptable.
ROOT_PARTITION="$fixture/efi"  # A different spelling of the same partition is not.
expect_rejected validate_partitions
ROOT_PARTITION="$other_partition"  # A valid partition on another disk is not.
expect_rejected validate_partitions
ROOT_PARTITION="$fixture/root"
BOOT_PARTITION="$fixture/efi"

boot_type="$root_type"
expect_rejected validate_partitions  # Boot must have the EFI GPT partition type.
boot_type="$efi_type"
root_type="$efi_type"
expect_rejected validate_partitions  # Root must not be an EFI partition.
root_type=0fc63daf-8483-4772-8e79-3d69d8477de4
root_fstype=ntfs
expect_rejected validate_partitions  # Do not accept an existing Windows filesystem as root.
root_fstype=ext4

choose_boot_partition_action
[[ "$BOOT_PARTITION_ACTION" == format ]]
preflight_partitions
selected_efi_contents=windows
expect_rejected preflight_partitions
selected_efi_contents=unknown
expect_rejected preflight_partitions  # Never erase an unrelated ESP.
selected_efi_contents=arch
firmware_readable=no
expect_rejected preflight_partitions
firmware_readable=yes
windows_separate=no
expect_rejected preflight_partitions
windows_separate=yes
firmware_windows_uuid="$selected_uuid"
expect_rejected preflight_partitions  # NVRAM Windows record points here.
firmware_windows_uuid=11111111-1111-1111-1111-111111111111
selected_efi_contents=empty
preflight_partitions  # A verified empty ESP is also safe to format.
selected_efi_contents=arch
mounted_partition="$ROOT_PARTITION"
expect_rejected preflight_partitions
mounted_partition=""

answer=no
choose_boot_partition_action
[[ "$BOOT_PARTITION_ACTION" == format ]]  # Existing separate Arch EFI is reformatted.
boot_fstype=""
choose_boot_partition_action
[[ "$BOOT_PARTITION_ACTION" == format ]]
preflight_partitions
boot_size=268435456
expect_rejected preflight_partitions
boot_size=1073741824
boot_fstype=ext4
expect_rejected choose_boot_partition_action
expect_rejected preflight_partitions

printf 'Arch partition selection and EFI preflight: OK (mocked devices only).\n'
