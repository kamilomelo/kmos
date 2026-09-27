#!/usr/bin/env bash
# Prepare a bootable Arch Linux ARM SD card for a Pine64 Quartz64 Model B.
# This script intentionally erases the device passed with --device.
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail
IFS=$'\n\t'

# os.archlinuxarm.org currently serves a certificate for a different hostname.
# The rootfs remains PGP-verified after downloading from this official mirror.
readonly ALARM_ROOTFS_URL="https://ca.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
readonly ALARM_SIGNING_FINGERPRINT="68B3537F39A313B3E574D06777193F152BDBE6A6"
# This is the exact CI artifact linked by Pine64's Quartz64 Arch Linux ARM guide.
readonly DEFAULT_BOOTLOADER_URL="https://gitlab.com/pgwipeout/quartz64_ci/-/jobs/3293568184/artifacts/download?file_type=archive"

SCRIPT_DIR=$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=platforms/archlinuxarm/boards/quartz64b/wifi-profile.sh
source "$SCRIPT_DIR/wifi-profile.sh"
DEVICE=""
WORK_DIR="$SCRIPT_DIR/work"
CUSTOM_WORK_DIR=0
LEGACY_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quartz64b-archlinuxarm"
BOOTLOADER_URL="$DEFAULT_BOOTLOADER_URL"
BOOTLOADER_ARCHIVE=""
BOOTLOADER_SHA256=""
ROOT_PASSWORD_HASH=""
ASSUME_YES=0
KEEP_MOUNTS=0
FIRST_BOOT_WIFI=0
WIFI_SSID=""
WIFI_PASSPHRASE=""
WIFI_HIDDEN=false
MOUNT_DIR=""
BOOT_PARTITION=""
ROOT_PARTITION=""
BOOTLOADER_DIR=""
PROTECTED_DISKS=()
CONFIRMED_DEVICE=""
CONFIRMED_DEVICE_ID=""
CONFIRMED_DEVICE_SIZE=""

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

info() {
  printf '==> %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage:
  ./prepare-quartz64b-sd.sh [options]

Options:
  --device PATH                 Advanced: select a whole disk without the device menu.
  --work-dir PATH               Download and verification directory (default: ./work).
  --cache-dir PATH              Alias for --work-dir.
  --bootloader-url URL          CI artifact ZIP URL.
  --bootloader-archive PATH     Use a previously downloaded artifact ZIP.
  --bootloader-sha256 SHA256    Require this SHA-256 for the artifact ZIP.
  --root-password-hash HASH     SHA-512 crypt hash for root; avoids an interactive prompt.
  --yes-really-erase            Skip the final y/N confirmation.
  --keep-mounts                 Leave the SD mounted on success, for inspection.
  -h, --help                    Show this help.

The artifact must contain idblock.bin and uboot.img, normally under artifacts/.
First-boot Wi-Fi is offered interactively. It requires iwd in the verified ARM
rootfs and a supported wireless adapter on the board. No Wi-Fi credentials are
passed on command lines. Ethernet remains available as a fallback.
The default artifact is the unmaintained one linked by Pine64. Unlike the rootfs,
it has no upstream cryptographic signature. Prefer --bootloader-archive together
with --bootloader-sha256 after you have recorded a trusted digest.
EOF
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  [[ -z "$BOOTLOADER_DIR" ]] || rm -rf "$BOOTLOADER_DIR"
  if [[ -n "$MOUNT_DIR" && "$KEEP_MOUNTS" -eq 0 ]]; then
    if mountpoint -q "$MOUNT_DIR/boot"; then
      umount "$MOUNT_DIR/boot" || true
    fi
    if mountpoint -q "$MOUNT_DIR"; then
      umount "$MOUNT_DIR" || true
    fi
    rmdir "$MOUNT_DIR" 2>/dev/null || true
  fi
  exit "$status"
}

require_root() {
  ((EUID == 0)) && return
  command -v sudo >/dev/null 2>&1 || die 'Root access is required, but sudo is not installed.'
  info 'Root access is needed to prepare the SD card; sudo will prompt for your password.'
  exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
}

require_commands() {
  local command missing=()
  local commands=(
    awk basename blockdev blkid chpasswd cmp cp curl dd df dirname find findmnt flock
    bsdtar gpg grep head install ln lsblk mkdir mkfs.ext4 mkfs.fat mktemp mount mountpoint
    mv openssl parted partprobe readlink rm rmdir sed sha256sum sort stat sync systemctl
    tar tee udevadm umount wipefs
  )
  for command in "${commands[@]}"; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  ((${#missing[@]} == 0)) || die "Missing required commands: ${missing[*]}"
}

parse_arguments() {
  while (($#)); do
    case "$1" in
      --device) DEVICE=${2:-}; shift 2 ;;
      --work-dir|--cache-dir) WORK_DIR=${2:-}; CUSTOM_WORK_DIR=1; shift 2 ;;
      --bootloader-url) BOOTLOADER_URL=${2:-}; shift 2 ;;
      --bootloader-archive) BOOTLOADER_ARCHIVE=${2:-}; shift 2 ;;
      --bootloader-sha256) BOOTLOADER_SHA256=${2:-}; shift 2 ;;
      --root-password-hash) ROOT_PASSWORD_HASH=${2:-}; shift 2 ;;
      --yes-really-erase) ASSUME_YES=1; shift ;;
      --keep-mounts) KEEP_MOUNTS=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  [[ -n "$WORK_DIR" ]] || die '--work-dir cannot be empty.'
  [[ -z "$BOOTLOADER_SHA256" || "$BOOTLOADER_SHA256" =~ ^[[:xdigit:]]{64}$ ]] || die '--bootloader-sha256 must be a SHA-256 digest.'
}

select_device() {
  local choice index candidate transport removable hotplug
  local -a candidates=()

  [[ -n "$DEVICE" ]] && return

  collect_protected_disks
  while IFS= read -r candidate; do
    is_protected_disk "$candidate" && continue
    transport=$(lsblk -dnro TRAN "$candidate")
    removable=$(lsblk -dnro RM "$candidate")
    hotplug=$(lsblk -dnro HOTPLUG "$candidate")
    if [[ "$transport" == usb || "$transport" == mmc || "$removable" == 1 || "$hotplug" == 1 ]]; then
      candidates+=("$candidate")
    fi
  done < <(lsblk -dnpr -o NAME,TYPE | awk '$2 == "disk" { print $1 }')

  ((${#candidates[@]} > 0)) || die 'No separate removable/SD disk was detected. Connect the card and try again.'
  printf '\nAvailable removable/SD disks:\n'
  for index in "${!candidates[@]}"; do
    printf '  %d) ' "$((index + 1))"
    lsblk -d -n -p -o NAME,SIZE,MODEL,TRAN,RM,HOTPLUG "${candidates[$index]}"
  done

  if ((${#candidates[@]} == 1)); then
    read -r -p "Use ${candidates[0]} for the Quartz64 SD card? [y/N]: " choice
    [[ "$choice" =~ ^[Yy]$ ]] || die 'Card selection cancelled; nothing was changed.'
    DEVICE="${candidates[0]}"
    return
  fi

  while true; do
    read -r -p "Select the SD card [1-${#candidates[@]}] or EXIT: " choice
    [[ "$choice" != EXIT ]] || die 'Card selection cancelled; nothing was changed.'
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#candidates[@]})); then
      DEVICE="${candidates[$((choice - 1))]}"
      break
    fi
    warn 'Choose a listed number or EXIT.'
  done

}

collect_protected_disks() {
  local mount_path mount_type mount_id devices name device_type device_id
  local ancestors ancestor ancestor_type disk known found protected
  PROTECTED_DISKS=()

  # MAJ:MIN identifies the mounted block device even when SOURCE contains a
  # Btrfs subvolume suffix or a /dev/mapper alias. Walk the inverse block
  # graph to protect every physical disk underneath an LVM/crypt/RAID root.
  devices=$(lsblk -nrpo NAME,TYPE,MAJ:MIN) || die 'Cannot inspect host block devices; refusing to erase anything.'
  [[ -n "$devices" ]] || die 'No host block devices were found; refusing to erase anything.'
  for mount_path in / "$SCRIPT_DIR"; do
    mount_type=$(findmnt -nro FSTYPE --target "$mount_path") || die "Cannot identify the filesystem hosting $mount_path."
    # A multi-device Btrfs filesystem can contain other disks not represented
    # by its mounted device's lsblk ancestry; refuse instead of guessing.
    [[ "$mount_type" != btrfs ]] || die "Cannot safely determine all disks for the Btrfs mount $mount_path."
    mount_id=$(findmnt -nro MAJ:MIN --target "$mount_path") || die "Cannot identify the block device hosting $mount_path."
    [[ "$mount_id" =~ ^[0-9]+:[0-9]+$ ]] || die "Invalid block device ID for $mount_path."
    found=0
    while IFS=' ' read -r name device_type device_id; do
      [[ "$device_id" == "$mount_id" && -n "$device_type" ]] || continue
      found=1
      ancestors=$(lsblk -srnpo NAME,TYPE "$name") || die "Cannot trace storage ancestry for $mount_path."
      disk=0
      while IFS=' ' read -r ancestor ancestor_type; do
        [[ "$ancestor_type" == disk ]] || continue
        disk=1
        ancestor=$(readlink -f -- "$ancestor") || die "Cannot resolve host disk $ancestor."
        known=0
        for protected in "${PROTECTED_DISKS[@]}"; do
          [[ "$ancestor" != "$protected" ]] || { known=1; break; }
        done
        ((known)) || PROTECTED_DISKS+=("$ancestor")
      done <<< "$ancestors"
      ((disk)) || die "No physical ancestor disk found for $mount_path."
    done <<< "$devices"
    ((found)) || die "The device hosting $mount_path is not in the block-device graph."
  done
}

is_protected_disk() {
  local candidate protected
  candidate=$(readlink -f -- "$1") || return 0
  for protected in "${PROTECTED_DISKS[@]}"; do
    [[ "$candidate" != "$protected" ]] || return 0
  done
  return 1
}

partition_path() {
  local number=$1
  if [[ "$DEVICE" =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$DEVICE" "$number"
  else
    printf '%s%s\n' "$DEVICE" "$number"
  fi
}

validate_device() {
  local size
  collect_protected_disks
  DEVICE=$(readlink -f -- "$DEVICE")
  is_block_device "$DEVICE" || die "$DEVICE is not a block device. Pass the full SD card, not a partition."
  [[ "$(lsblk -dnro TYPE "$DEVICE")" == 'disk' ]] || die "$DEVICE is not a whole-disk block device."
  is_protected_disk "$DEVICE" && die 'Refusing to erase a disk containing the host system or this script.'
  if lsblk -nrpo MOUNTPOINTS "$DEVICE" | grep -q .; then
    die "A partition on $DEVICE is mounted. Unmount it before continuing."
  fi
  size=$(blockdev --getsize64 "$DEVICE")
  ((size >= 8 * 1024 * 1024 * 1024)) || die 'An SD card of at least 8 GiB is required.'
}

is_block_device() {
  [[ -b "$1" ]]
}

confirm_erase() {
  local model size answer
  model=$(lsblk -dnro MODEL "$DEVICE" | awk '{$1=$1; print}')
  size=$(lsblk -dnro SIZE "$DEVICE")
  printf '\nTarget device:\n  path:  %s\n  model: %s\n  size:  %s\n\n' "$DEVICE" "${model:-unknown}" "$size"
  warn 'ALL DATA on this device will be permanently erased.'
  if ((ASSUME_YES == 0)); then
    read -r -p 'Continue? [y/N]: ' answer
    [[ "$answer" =~ ^[Yy]$ ]] || die 'Cancelled; nothing was changed.'
  fi
  CONFIRMED_DEVICE="$DEVICE"
  CONFIRMED_DEVICE_ID=$(lsblk -dnro MAJ:MIN "$DEVICE")
  CONFIRMED_DEVICE_SIZE=$(blockdev --getsize64 "$DEVICE")
  [[ "$CONFIRMED_DEVICE_ID" =~ ^[0-9]+:[0-9]+$ ]] || die 'Could not identify the selected SD card.'
}

verify_confirmed_device() {
  [[ -n "$CONFIRMED_DEVICE" && "$DEVICE" == "$CONFIRMED_DEVICE" ]] || die 'The selected SD-card path changed after confirmation.'
  [[ "$(lsblk -dnro MAJ:MIN "$DEVICE")" == "$CONFIRMED_DEVICE_ID" ]] || die 'The selected SD-card device changed after confirmation.'
  [[ "$(blockdev --getsize64 "$DEVICE")" == "$CONFIRMED_DEVICE_SIZE" ]] || die 'The selected SD-card size changed after confirmation.'
}

create_root_password_hash() {
  local first second
  [[ -n "$ROOT_PASSWORD_HASH" ]] && return
  while true; do
    read -r -s -p 'Root password for the first boot: ' first
    printf '\n'
    [[ -n "$first" ]] || { warn 'The root password cannot be empty.'; continue; }
    read -r -s -p 'Confirm root password: ' second
    printf '\n'
    [[ "$first" == "$second" ]] || { warn 'Passwords differ.'; continue; }
    ROOT_PASSWORD_HASH=$(printf '%s\n' "$first" | openssl passwd -6 -stdin)
    unset first second
    return
  done
}

collect_first_boot_wifi() {
  local answer confirmation
  read -r -p 'Preconfigure Wi-Fi for first boot (without Ethernet)? [y/N]: ' answer
  [[ "$answer" =~ ^[Yy]$ ]] || return 0
  FIRST_BOOT_WIFI=1
  read -r -p 'Wi-Fi SSID (ASCII letters, digits, spaces, _ or -): ' WIFI_SSID
  read -r -s -p 'WPA-Personal passphrase: ' WIFI_PASSPHRASE
  printf '\n' >&2
  read -r -s -p 'Confirm Wi-Fi passphrase: ' confirmation
  printf '\n' >&2
  [[ "$WIFI_PASSPHRASE" == "$confirmation" ]] || die 'Wi-Fi passphrases differ.'
  unset confirmation
  validate_wifi_credentials "$WIFI_SSID" "$WIFI_PASSPHRASE" || die 'SSID or passphrase is unsupported; see --help.'
  read -r -p 'Hidden Wi-Fi network? [y/N]: ' answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then WIFI_HIDDEN=true; fi
}

verify_first_boot_wifi_support() {
  local rootfs=$1
  ((FIRST_BOOT_WIFI)) || return 0
  info 'Checking the verified ARM rootfs for iwd before writing the SD card.'
  tar -tf "$rootfs" | awk '
    /(^|\/)usr\/bin\/iwctl$/ { iwctl=1 }
    /(^|\/)usr\/lib\/systemd\/system\/iwd.service$/ { service=1 }
    END { exit !(iwctl && service) }
  ' || die 'The ARM rootfs lacks iwd. SD card untouched; use Ethernet/USB tethering or arrange verified offline ARM packages before first-boot Wi-Fi.'
}

download() {
  local url=$1 output=$2
  curl --fail --location --retry 4 --retry-delay 3 --continue-at - --output "$output" "$url"
}

verify_rootfs() (
  local rootfs=$1 signature=$2 gpg_home
  gpg_home=$(mktemp -d "$WORK_DIR/gnupg.XXXXXXXX") || die 'Could not create a temporary PGP keyring.'
  trap 'rm -rf -- "$gpg_home"' EXIT
  info 'Importing the Arch Linux ARM signing key.'
  curl --fail --location --retry 4 \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$ALARM_SIGNING_FINGERPRINT" \
    | gpg --homedir "$gpg_home" --batch --import
  gpg --homedir "$gpg_home" --batch --with-colons --fingerprint "$ALARM_SIGNING_FINGERPRINT" \
    | awk -F: '$1 == "fpr" { print $10; exit }' \
    | grep -qx "$ALARM_SIGNING_FINGERPRINT" \
    || die 'The imported rootfs signing key does not have the expected fingerprint.'
  info 'Verifying the Arch Linux ARM rootfs signature.'
  gpg --homedir "$gpg_home" --batch --verify "$signature" "$rootfs"
)

fetch_inputs() {
  local rootfs="$WORK_DIR/ArchLinuxARM-aarch64-latest.tar.gz"
  local signature="$rootfs.sig"
  local artifact="$WORK_DIR/quartz64-ci-artifact.zip"
  install -d -m 0755 "$WORK_DIR"

  # Reuse downloads made before work/ became the default location.
  if [[ "$WORK_DIR" != "$LEGACY_CACHE_DIR" && ! -s "$rootfs" && -s "$LEGACY_CACHE_DIR/ArchLinuxARM-aarch64-latest.tar.gz" ]]; then
    info 'Reusing the rootfs from the previous cache directory.'
    cp "$LEGACY_CACHE_DIR/ArchLinuxARM-aarch64-latest.tar.gz" "$rootfs"
    if [[ ! -s "$signature" && -s "$LEGACY_CACHE_DIR/ArchLinuxARM-aarch64-latest.tar.gz.sig" ]]; then
      cp "$LEGACY_CACHE_DIR/ArchLinuxARM-aarch64-latest.tar.gz.sig" "$signature"
    fi
  fi

  if [[ ! -s "$rootfs" ]]; then
    info 'Downloading the Arch Linux ARM aarch64 rootfs.'
    download "$ALARM_ROOTFS_URL" "$rootfs"
  fi
  if [[ ! -s "$signature" ]]; then
    info 'Downloading the rootfs signature.'
    download "$ALARM_ROOTFS_URL.sig" "$signature"
  fi
  if ! verify_rootfs "$rootfs" "$signature"; then
    warn 'Cached rootfs verification failed; downloading it again.'
    rm -f "$rootfs" "$signature"
    download "$ALARM_ROOTFS_URL" "$rootfs"
    download "$ALARM_ROOTFS_URL.sig" "$signature"
    verify_rootfs "$rootfs" "$signature"
  fi

  if [[ -n "$BOOTLOADER_ARCHIVE" ]]; then
    [[ -r "$BOOTLOADER_ARCHIVE" ]] || die "Cannot read bootloader archive: $BOOTLOADER_ARCHIVE"
    artifact=$(readlink -f -- "$BOOTLOADER_ARCHIVE")
  elif [[ ! -s "$artifact" ]]; then
    warn 'Downloading the legacy Pine64-linked bootloader artifact. It is not signed.'
    download "$BOOTLOADER_URL" "$artifact"
  fi
  if [[ -n "$BOOTLOADER_SHA256" ]]; then
    printf '%s  %s\n' "${BOOTLOADER_SHA256,,}" "$artifact" | sha256sum --check --status \
      || die 'Bootloader archive SHA-256 verification failed.'
  else
    warn "Bootloader archive SHA-256 (record it before future use): $(sha256sum "$artifact" | awk '{print $1}')"
  fi
  printf '%s\n%s\n%s\n' "$rootfs" "$signature" "$artifact"
}

extract_bootloader() {
  local artifact=$1 output_dir=$2 idblock uboot
  local entries
  entries=$(bsdtar -tf "$artifact") || die 'The bootloader artifact is not a readable ZIP archive.'
  idblock=$(printf '%s\n' "$entries" | grep -E '(^|/)idblock\.bin$' | head -n1 || true)
  uboot=$(printf '%s\n' "$entries" | grep -E '(^|/)uboot\.img$' | head -n1 || true)
  [[ -n "$idblock" && -n "$uboot" ]] || die 'The artifact does not contain both idblock.bin and uboot.img.'
  bsdtar -xOf "$artifact" "$idblock" > "$output_dir/idblock.bin"
  bsdtar -xOf "$artifact" "$uboot" > "$output_dir/uboot.img"
  [[ -s "$output_dir/idblock.bin" && -s "$output_dir/uboot.img" ]] || die 'Bootloader extraction produced an empty file.'
}

partition_and_format() {
  # Recheck immediately before the first write: downloads and prompts can take
  # long enough for device names or mount state to change.
  validate_device
  verify_confirmed_device
  BOOT_PARTITION=$(partition_path 4)
  ROOT_PARTITION=$(partition_path 5)
  info 'Removing existing signatures and creating the Quartz64 partition layout.'
  wipefs --all --force "$DEVICE"
  parted --script --align none "$DEVICE" mklabel gpt
  parted --script --align none "$DEVICE" mkpart loader 64s 8MiB
  parted --script --align none "$DEVICE" mkpart uboot 8MiB 16MiB
  parted --script --align none "$DEVICE" mkpart env 16MiB 32MiB
  parted --script --align none "$DEVICE" mkpart efi fat32 32MiB 544MiB
  parted --script --align none "$DEVICE" set 4 boot on
  parted --script --align none "$DEVICE" mkpart root ext4 544MiB 100%
  partprobe "$DEVICE"
  udevadm settle
  [[ -b "$BOOT_PARTITION" && -b "$ROOT_PARTITION" ]] || die 'The expected SD partitions were not created.'
  mkfs.fat -F 32 -n EFI "$BOOT_PARTITION"
  mkfs.ext4 -F -L rootfs "$ROOT_PARTITION"
}

write_bootloader() {
  local input_dir=$1 loader_partition uboot_partition
  loader_partition=$(partition_path 1)
  uboot_partition=$(partition_path 2)
  [[ $(stat -c %s "$input_dir/idblock.bin") -le $((8 * 1024 * 1024 - 64 * 512)) ]] || die 'idblock.bin is too large for partition 1.'
  [[ $(stat -c %s "$input_dir/uboot.img") -le $((8 * 1024 * 1024)) ]] || die 'uboot.img is too large for partition 2.'
  info 'Writing the Quartz64 bootloader.'
  dd if="$input_dir/idblock.bin" of="$loader_partition" bs=4M conv=fsync status=progress
  dd if="$input_dir/uboot.img" of="$uboot_partition" bs=4M conv=fsync status=progress
}

enable_unit() {
  local unit=$1 target=$2 unit_path
  unit_path="$MOUNT_DIR/usr/lib/systemd/system/$unit"
  [[ -e "$unit_path" ]] || { warn "Rootfs lacks $unit; it was not enabled."; return; }
  install -d -m 0755 "$MOUNT_DIR/etc/systemd/system/$target.wants"
  ln -sfn "/usr/lib/systemd/system/$unit" "$MOUNT_DIR/etc/systemd/system/$target.wants/$unit"
}

configure_target() {
  local rootfs=$1 dtb
  MOUNT_DIR=$(mktemp -d /mnt/quartz64b.XXXXXX)
  mount "$ROOT_PARTITION" "$MOUNT_DIR"
  install -d -m 0755 "$MOUNT_DIR/boot"
  mount "$BOOT_PARTITION" "$MOUNT_DIR/boot"
  info 'Extracting the verified Arch Linux ARM rootfs.'
  tar --extract --preserve-permissions --numeric-owner --file "$rootfs" --directory "$MOUNT_DIR"

  dtb=$(find "$MOUNT_DIR/boot" -type f -name 'rk3566-quartz64-b.dtb' -print -quit)
  [[ -n "$dtb" ]] || die 'The rootfs kernel does not contain rk3566-quartz64-b.dtb.'
  install -d -m 0755 "$MOUNT_DIR/boot/dtbs/rockchip" "$MOUNT_DIR/boot/extlinux"
  if [[ "$dtb" != "$MOUNT_DIR/boot/dtbs/rockchip/rk3566-quartz64-b.dtb" ]]; then
    install -m 0644 "$dtb" "$MOUNT_DIR/boot/dtbs/rockchip/rk3566-quartz64-b.dtb"
  fi
  [[ -f "$MOUNT_DIR/boot/Image" ]] || die 'The rootfs kernel image /boot/Image is missing.'
  [[ -f "$MOUNT_DIR/boot/initramfs-linux.img" ]] || die 'The rootfs initramfs is missing.'

  cat > "$MOUNT_DIR/boot/extlinux/extlinux.conf" <<'EOF'
default arch
menu title Quartz64 Model B Boot Menu
prompt 0
timeout 50

label arch
  menu label Arch Linux ARM
  linux /Image
  fdt /dtbs/rockchip/rk3566-quartz64-b.dtb
  append initrd=/initramfs-linux.img earlycon=uart8250,mmio32,0xfe660000 console=ttyS2,1500000n8 root=LABEL=rootfs rw rootwait
EOF

  cat > "$MOUNT_DIR/etc/fstab" <<EOF
PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PARTITION") / ext4 defaults 0 1
PARTUUID=$(blkid -s PARTUUID -o value "$BOOT_PARTITION") /boot vfat defaults 0 2
EOF
  install -d -m 0755 "$MOUNT_DIR/etc/systemd/network"
  cat > "$MOUNT_DIR/etc/systemd/network/20-ethernet-dhcp.network" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=100
EOF
  enable_unit systemd-networkd.service multi-user.target
  enable_unit systemd-resolved.service multi-user.target
  enable_unit sshd.service multi-user.target
  install -Dm0755 "$SCRIPT_DIR/connect-quartz64b-wifi.sh" "$MOUNT_DIR/root/connect-quartz64b-wifi.sh"
  install -Dm0644 "$SCRIPT_DIR/wifi-profile.sh" "$MOUNT_DIR/root/wifi-profile.sh"
  if ((FIRST_BOOT_WIFI)); then
    write_iwd_profile "$MOUNT_DIR/var/lib/iwd" "$WIFI_SSID" "$WIFI_PASSPHRASE" "$WIFI_HIDDEN" || die 'Could not save the first-boot Wi-Fi profile.'
    unset WIFI_PASSPHRASE
    install -Dm0644 /dev/stdin "$MOUNT_DIR/etc/iwd/main.conf" <<'IWD_CONFIG'
[General]
EnableNetworkConfiguration=false
IWD_CONFIG
    cat > "$MOUNT_DIR/etc/systemd/network/25-wifi-dhcp.network" <<'WIFI_NETWORK'
[Match]
Name=wl* wlan*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=600
WIFI_NETWORK
    enable_unit iwd.service multi-user.target
  fi
  ln -sfn /run/systemd/resolve/stub-resolv.conf "$MOUNT_DIR/etc/resolv.conf"

  [[ -f "$MOUNT_DIR/etc/shadow" ]] || die 'The extracted rootfs does not contain /etc/shadow.'
  awk -F: -v hash="$ROOT_PASSWORD_HASH" 'BEGIN { OFS=FS } $1 == "root" { $2=hash } { print }' \
    "$MOUNT_DIR/etc/shadow" > "$MOUNT_DIR/etc/shadow.new"
  chmod 0600 "$MOUNT_DIR/etc/shadow.new"
  mv "$MOUNT_DIR/etc/shadow.new" "$MOUNT_DIR/etc/shadow"
  info 'Configured DHCP Ethernet, DNS, SSH, and the root password for first boot.'
}

verify_target() {
  info 'Verifying the completed SD card.'
  grep -qx 'root=LABEL=rootfs rw rootwait' <(grep 'append ' "$MOUNT_DIR/boot/extlinux/extlinux.conf" | sed 's/^.*root=/root=/') \
    || die 'extlinux root parameter verification failed.'
  grep -q 'rk3566-quartz64-b.dtb' "$MOUNT_DIR/boot/extlinux/extlinux.conf" || die 'Model B DTB is not configured.'
  grep -q 'DHCP=yes' "$MOUNT_DIR/etc/systemd/network/20-ethernet-dhcp.network" || die 'DHCP configuration is missing.'
  [[ -L "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ]] || die 'systemd-networkd was not enabled.'
  [[ -s "$MOUNT_DIR/boot/Image" && -s "$MOUNT_DIR/boot/initramfs-linux.img" ]] || die 'Boot files are incomplete.'
}

cleanup_workdir_prompt() {
  local choice
  if ((CUSTOM_WORK_DIR)); then
    info "Custom work directory preserved; inspect and remove it manually when finished: $WORK_DIR"
    return
  fi
  printf '\nDirectorio de trabajo: %s\n' "$WORK_DIR"
  printf '  1) Conservar para preparar otra SD sin volver a descargar (predeterminado)\n'
  printf '  2) Borrar descargas, firmas y archivos de verificacion\n'
  while true; do
    read -r -p 'Que desea hacer? [1-2] (predeterminado: 1): ' choice
    choice=${choice:-1}
    case "$choice" in
      1)
        info 'Directorio de trabajo conservado.'
        return
        ;;
      2)
        rm -rf -- "$WORK_DIR"
        info 'Directorio de trabajo borrado.'
        return
        ;;
      *) warn 'Seleccione 1 o 2.' ;;
    esac
  done
}

main() {
  parse_arguments "$@"
  require_root "$@"
  require_commands
  select_device
  validate_device
  confirm_erase
  create_root_password_hash
  collect_first_boot_wifi
  trap cleanup EXIT INT TERM

  local inputs rootfs artifact
  inputs=$(fetch_inputs)
  rootfs=$(printf '%s\n' "$inputs" | sed -n '1p')
  artifact=$(printf '%s\n' "$inputs" | sed -n '3p')
  verify_first_boot_wifi_support "$rootfs"
  BOOTLOADER_DIR=$(mktemp -d)
  extract_bootloader "$artifact" "$BOOTLOADER_DIR"
  partition_and_format
  write_bootloader "$BOOTLOADER_DIR"
  rm -rf "$BOOTLOADER_DIR"
  BOOTLOADER_DIR=""
  configure_target "$rootfs"
  verify_target
  info "Flushing buffered writes to $DEVICE. This may take several minutes; do not remove the SD card."
  sync
  info 'All buffered writes have completed.'
  if ((KEEP_MOUNTS)); then
    info "SD card is ready and remains mounted at $MOUNT_DIR."
  else
    info "SD card is ready. Safely remove $DEVICE and insert it into the Quartz64 Model B."
  fi
  cleanup_workdir_prompt
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
