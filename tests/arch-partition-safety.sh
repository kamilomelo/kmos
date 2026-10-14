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
selected_uuid=22222222-2222-2222-2222-222222222222
selected_device_id=8:1
efi_choice=reuse
reuse_space=yes

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
        MAJ:MIN) [[ "$device" == "$BOOT_PARTITION" ]] && echo "$selected_device_id" || echo 8:2 ;;
        PARTUUID) echo "$selected_uuid" ;;
        *) return 1 ;;
      esac
      ;;
    -bdnro) [[ "$2" == SIZE ]] && echo "$boot_size" ;;
    *) return 1 ;;
  esac
}
ask_yes_no() { [[ "$answer" == yes ]]; }
prompt_choice() {
  if [[ "$efi_choice" == reuse && "$selected_efi_contents" == windows && "$answer" == no ]]; then
    if [[ -e "$fixture/windows-reuse-attempt" ]]; then printf 'cancel\n'
    else touch "$fixture/windows-reuse-attempt"; printf 'reuse\n'; fi
  elif [[ "$efi_choice" == reuse && "$reuse_space" == no ]]; then
    if [[ -e "$fixture/reuse-attempt" ]]; then printf 'cancel\n'
    else touch "$fixture/reuse-attempt"; printf 'reuse\n'; fi
  else printf '%s\n' "$efi_choice"; fi
}
selected_efi_identity() { [[ "$selected_efi_contents" != uninspected ]] || return 2; printf '%s\n' "$selected_efi_contents"; }
check_reused_efi_space() { [[ "$reuse_space" == yes ]]; }

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
[[ "$BOOT_PARTITION_ACTION" == reuse ]]
preflight_partitions
selected_efi_contents=unknown
choose_boot_partition_action  # The previously blocking unknown EFI is safely reusable.
[[ "$BOOT_PARTITION_ACTION" == reuse ]]
preflight_partitions
reuse_space=no
expect_rejected choose_boot_partition_action
reuse_space=yes
selected_efi_contents=windows
answer=no
expect_rejected choose_boot_partition_action  # Reusing a Windows ESP needs separate approval.
answer=yes
choose_boot_partition_action
preflight_partitions  # Windows EFI files are preserved when reusing.
efi_choice=format
expect_rejected choose_boot_partition_action <<< 'ERASE'  # The exact requested token is EREASE.
expect_rejected choose_boot_partition_action <<< "EREASE $BOOT_PARTITION"  # No device path in the token.
choose_boot_partition_action <<< 'EREASE'  # Explicitly approved Windows EFI format is allowed.
[[ "$BOOT_PARTITION_ACTION" == format ]]
preflight_partitions  # Windows contents do not veto an approved force format.
selected_efi_contents=unknown
preflight_partitions  # Unknown contents are also allowed.
selected_efi_contents=uninspected
preflight_partitions  # Read-only mount failures do not veto an approved force format.
choose_boot_partition_action <<< 'EREASE'
preflight_partitions  # Inspection failure before approval also permits a forced format.
selected_uuid=33333333-3333-3333-3333-333333333333
expect_rejected preflight_partitions  # EFI partition changed since approval.
selected_uuid=22222222-2222-2222-2222-222222222222
selected_device_id=8:9
expect_rejected preflight_partitions  # Same path now points to another device.
selected_device_id=8:1
boot_fstype=""
expect_rejected preflight_partitions  # Approved FAT EFI changed before formatting.
boot_fstype=vfat
selected_efi_contents=arch
mounted_partition="$ROOT_PARTITION"
expect_rejected preflight_partitions
mounted_partition=""

answer=no
efi_choice=reuse
choose_boot_partition_action
[[ "$BOOT_PARTITION_ACTION" == reuse ]]  # Existing Arch EFI is preserved by default.
boot_fstype=""
choose_boot_partition_action
[[ "$BOOT_PARTITION_ACTION" == format ]]
preflight_partitions
boot_size=268435456
expect_rejected preflight_partitions
boot_size=1073741824
boot_fstype=vfat
expect_rejected preflight_partitions  # Blank EFI became FAT after selection; approval missing.
boot_fstype=ext4
expect_rejected choose_boot_partition_action
expect_rejected preflight_partitions

printf 'Arch partition selection and EFI preflight: OK (mocked devices only).\n'
