#!/usr/bin/env bash
# Offline failure fixtures only; never mount, unmount, or write a real SD card.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

WORK_DIR="$fixture/work"
LEGACY_CACHE_DIR="$fixture/no-legacy-cache"
mkdir -p "$WORK_DIR" "$fixture/target/etc"
BOOTLOADER_ARCHIVE="$fixture/artifact.zip"
printf 'test artifact\n' > "$BOOTLOADER_ARCHIVE"
BOOTLOADER_SHA256=$(sha256sum "$BOOTLOADER_ARCHIVE" | awk '{print $1}')
download() { printf 'downloaded\n' > "$2"; }
verify_rootfs() { printf 'attempt\n' >> "$fixture/verifications"; return 1; }
if (fetch_inputs) >"$fixture/inputs" 2>"$fixture/verification-error"; then
  printf 'Unverified rootfs was accepted.\n' >&2
  exit 1
fi
[[ $(wc -l < "$fixture/verifications") == 2 ]]
grep -q 'refusing to write the SD card' "$fixture/verification-error"

MOUNT_DIR="$fixture/target"
ROOT_PARTITION="$fixture/mock-root"
BOOT_PARTITION="$fixture/mock-boot"
blkid() {
  [[ "$1" == -s && "$2" == PARTUUID && "$3" == -o && "$4" == value ]] || return 1
  [[ ! -e "$fixture/blkid-fails" && ( ! -e "$fixture/boot-blkid-fails" || "$5" != "$BOOT_PARTITION" ) ]] || return 2
  [[ ! -e "$fixture/blkid-empty" ]] || return 0
  case "$5" in
    "$ROOT_PARTITION") printf '11111111-2222-3333-4444-555555555555\n' ;;
    "$BOOT_PARTITION") printf 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n' ;;
    *) return 1 ;;
  esac
}
touch "$fixture/blkid-fails"
if (write_target_fstab) >"$fixture/fstab-error" 2>&1; then
  printf 'Failed blkid was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$MOUNT_DIR/etc/fstab" ]]
rm "$fixture/blkid-fails"
touch "$fixture/boot-blkid-fails"
if (write_target_fstab) >"$fixture/fstab-error" 2>&1; then
  printf 'Failed boot blkid was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$MOUNT_DIR/etc/fstab" ]]
rm "$fixture/boot-blkid-fails"
touch "$fixture/blkid-empty"
if (write_target_fstab) >"$fixture/fstab-error" 2>&1; then
  printf 'Empty PARTUUID was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$MOUNT_DIR/etc/fstab" ]]
rm "$fixture/blkid-empty"
write_target_fstab
grep -qx 'PARTUUID=11111111-2222-3333-4444-555555555555 / ext4 defaults 0 1' "$MOUNT_DIR/etc/fstab"
grep -qx 'PARTUUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee /boot vfat defaults 0 2' "$MOUNT_DIR/etc/fstab"

if (enable_first_boot_ssh) >"$fixture/ssh-error" 2>&1; then
  printf 'Missing sshd.service was accepted.\n' >&2
  exit 1
fi
grep -q 'Rootfs lacks sshd.service' "$fixture/ssh-error"
mkdir -p "$MOUNT_DIR/usr/lib/systemd/system"
touch "$MOUNT_DIR/usr/lib/systemd/system/sshd.service"
enable_first_boot_ssh
[[ -L "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/sshd.service" ]]

mkdir -p "$MOUNT_DIR/boot"
touch "$fixture/root-mounted" "$fixture/boot-mounted" "$fixture/fail-boot-unmount"
mountpoint() {
  case "$2" in
    "$MOUNT_DIR/boot") [[ -e "$fixture/boot-mounted" ]] ;;
    "$MOUNT_DIR") [[ -e "$fixture/root-mounted" ]] ;;
    *) return 1 ;;
  esac
}
umount() {
  if [[ "$1" == "$MOUNT_DIR/boot" ]]; then
    [[ ! -e "$fixture/fail-boot-unmount" ]] || return 1
    rm "$fixture/boot-mounted"
  else
    rm "$fixture/root-mounted"
  fi
}
if (unmount_target) >"$fixture/unmount-error" 2>&1; then
  printf 'Failed unmount was accepted.\n' >&2
  exit 1
fi
grep -q 'do not remove the SD card' "$fixture/unmount-error"
[[ "$MOUNT_DIR" == "$fixture/target" ]]
touch "$fixture/root-mounted"
KEEP_MOUNTS=0
if (cleanup) >"$fixture/cleanup-error" 2>&1; then
  printf 'Cleanup returned success while the SD card stayed mounted.\n' >&2
  exit 1
fi
grep -q 'still mounted' "$fixture/cleanup-error"
rm "$fixture/fail-boot-unmount"
rmdir() { :; }
unmount_target
[[ -z "$MOUNT_DIR" && ! -e "$fixture/boot-mounted" && ! -e "$fixture/root-mounted" ]]

WORK_DIR="$fixture/work"
CUSTOM_WORK_DIR=0
cleanup_workdir_prompt </dev/null >"$fixture/work-prompt" 2>&1
grep -q 'No input; keeping the work directory' "$fixture/work-prompt"
[[ -d "$WORK_DIR" ]]
printf 'Quartz SD verification, UUID, SSH, unmount, and EOF failures: OK (mocked).\n'
