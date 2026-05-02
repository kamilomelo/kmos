#!/bin/bash
# KMOS Arch Linux Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

MOUNT_POINT="/mnt"
STEP_INDEX=0
STEP_TOTAL=7

UI_RESET=""
UI_BOLD=""
UI_DIM=""
UI_HEADER=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""
SUCCESS_ICON="▸"
FINAL_SUCCESS_ICON="✔"

TARGET_DISK=""
ROOT_PARTITION=""
BOOT_PARTITION=""
ROOT_FILESYSTEM="xfs"
TIMEZONE="Europe/Zurich"
LOCALE="en_US.UTF-8"
KEYMAP=""
HOSTNAME=""
SWAPFILE_SIZE="4G"
ROOT_PASSWORD=""
PRIMARY_USER=""
PRIMARY_PASSWORD=""
ADDITIONAL_LOCALES=()
declare -a EXTRA_USERS=()
declare -a EXTRA_PASSWORDS=()
declare -a EXTRA_SUDO=()

BASE_PACKAGES=(
  base
  linux
  linux-firmware
  sudo
  nano
)

TIMEZONE_OPTIONS=(
  "Europe/Zurich"
  "America/Bogota"
)

LOCALE_OPTIONS=(
  "en_US.UTF-8"
  "en_GB.UTF-8"
  "fr_CH.UTF-8"
  "es_CO.UTF-8"
)

FILESYSTEM_OPTIONS=(
  "xfs"
  "ext4"
  "btrfs"
)

repeat_char() {
  local char="$1"
  local count="$2"
  local out=""

  while ((count > 0)); do
    out+="$char"
    ((count--))
  done

  printf '%s' "$out"
}

init_ui() {
  if [[ -t 2 && "${TERM:-dumb}" != "dumb" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_DIM=$'\033[2m'
    UI_HEADER=$'\033[34m'
    UI_INFO=$'\033[37m'
    UI_SUCCESS=$'\033[32m'
    UI_WARN=$'\033[33m'
    UI_DANGER=$'\033[31m'
  fi

  if [[ "${TERM:-}" == "linux" || "${ASCII_UI:-${KMOS_ASCII_UI:-0}}" == "1" ]]; then
    SUCCESS_ICON=">"
    FINAL_SUCCESS_ICON="OK"
  fi
}

log() {
  printf '%s\n' "$*" >&2
}

info() {
  printf '%b%s%b\n' "${UI_INFO}${UI_BOLD}" "$*" "$UI_RESET" >&2
}

warn() {
  printf '%bWARNING:%b %s\n' "${UI_WARN}${UI_BOLD}" "$UI_RESET" "$*" >&2
}

success() {
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

final_success() {
  printf '\n%b%s%b %s\n\n' "$UI_SUCCESS" "$FINAL_SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

die() {
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

detail() {
  local key="$1"
  local value="$2"
  printf '  %b%-14s%b %s\n' "$UI_DIM" "$key" "$UI_RESET" "$value" >&2
}

progress_bar() {
  local current="$1"
  local total="$2"
  local width="${3:-28}"
  local filled=0
  local percent=0

  if ((total > 0)); then
    filled=$((current * width / total))
    percent=$((current * 100 / total))
  fi

  printf '[%s%s] %3d%%' \
    "$(repeat_char "#" "$filled")" \
    "$(repeat_char "-" "$((width - filled))")" \
    "$percent"
}

advance_step() {
  local label="$1"
  local bar

  ((STEP_INDEX += 1))
  bar="$(progress_bar "$STEP_INDEX" "$STEP_TOTAL")"

  printf '\n%bStep %d/%d%b %s\n' "${UI_HEADER}${UI_BOLD}" "$STEP_INDEX" "$STEP_TOTAL" "$UI_RESET" "$label" >&2
  printf '  %s\n' "$bar" >&2
}

print_banner() {
  printf '\n' >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$(repeat_char "=" 23)" "$UI_RESET" >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "KMOS Arch Linux Install" "$UI_RESET" >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$(repeat_char "=" 23)" "$UI_RESET" >&2
  log "Lean Arch Linux installer for the base system."
  log "This stage prepares partitions, installs base packages, and configures users."
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-}"
  local answer=""

  while true; do
    if [[ "$default" == "yes" ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-Y}"
    elif [[ "$default" == "no" ]]; then
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-N}"
    else
      read -r -p "$prompt [y/n]: " answer
    fi

    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value=""

  read -r -p "$prompt [$default]: " value
  printf '%s\n' "${value:-$default}"
}

prompt_choice() {
  local prompt="$1"
  local default="$2"
  shift 2
  local options=("$@")
  local index=1
  local choice=""
  local default_index=1

  for index in "${!options[@]}"; do
    if [[ "${options[$index]}" == "$default" ]]; then
      default_index=$((index + 1))
      break
    fi
  done

  log "$prompt"
  for index in "${!options[@]}"; do
    printf '  %d) %s\n' "$((index + 1))" "${options[$index]}" >&2
  done

  while true; do
    read -r -p "Select [1-${#options[@]}] (default: $default_index): " choice
    choice="${choice:-$default_index}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
      printf '%s\n' "${options[$((choice - 1))]}"
      return 0
    fi
    warn "Invalid selection."
  done
}

prompt_secret() {
  local prompt="$1"
  local first=""
  local second=""

  while true; do
    read -r -s -p "$prompt: " first
    printf '\n' >&2
    if [[ -z "$first" ]]; then
      if ask_yes_no "Leave $prompt empty?" "no"; then
        printf '\n'
        return 0
      fi
      continue
    fi

    read -r -s -p "Confirm $prompt: " second
    printf '\n' >&2

    if [[ "$first" != "$second" ]]; then
      warn "Passwords do not match."
    else
      printf '%s\n' "$first"
      return 0
    fi
  done
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run this script as root from the Arch ISO."
}

require_tools() {
  local missing=()
  local tools=(arch-chroot cfdisk findmnt genfstab grep lsblk mkfs.ext4 mkfs.fat mkfs.xfs mount pacstrap sed timedatectl)
  local tool

  for tool in "${tools[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}"
  fi
}

verify_boot_mode() {
  [[ -d /sys/firmware/efi/efivars ]] || die "UEFI mode was not detected. Boot the Arch ISO in UEFI mode."

  if [[ -r /sys/firmware/efi/fw_platform_size ]]; then
    detail "UEFI bits" "$(cat /sys/firmware/efi/fw_platform_size)"
  fi
}

select_disk() {
  local default_disk=""
  local name=""
  local type=""
  local tran=""
  local rm=""
  local hotplug=""
  local idx=0
  local choice=""
  local -a candidates=()
  local -a fallback=()
  local -a selectable=()

  while read -r name type tran rm hotplug; do
    [[ "$type" == "disk" ]] || continue
    [[ "$name" == /dev/loop* ]] && continue
    fallback+=("$name")

    if [[ "$tran" == "usb" || "$rm" == "1" || "$hotplug" == "1" ]]; then
      continue
    fi
    candidates+=("$name")
  done < <(lsblk -dnpr -o NAME,TYPE,TRAN,RM,HOTPLUG)

  if [[ ${#candidates[@]} -eq 0 ]]; then
    candidates=("${fallback[@]}")
  fi

  [[ ${#candidates[@]} -gt 0 ]] || die "No installable disk detected."

  default_disk="${candidates[0]}"
  selectable=("${candidates[@]}")

  info "Autodetected install disk."
  detail "Default" "$default_disk"
  if ask_yes_no "Use autodetected default disk?" "yes"; then
    TARGET_DISK="$default_disk"
    return 0
  fi

  selectable=("${fallback[@]}")
  info "Available disks:"
  for idx in "${!selectable[@]}"; do
    printf '  %d) ' "$((idx + 1))" >&2
    lsblk -d -p -o NAME,SIZE,MODEL,TYPE,TRAN,RM,HOTPLUG "${selectable[$idx]}" >&2
  done

  while true; do
    read -r -p "Select target disk [1-${#selectable[@]}] (default: 1): " choice
    choice="${choice:-1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#selectable[@]})); then
      TARGET_DISK="${selectable[$((choice - 1))]}"
      return 0
    fi
    warn "Invalid disk selection."
  done
}

partition_type() {
  local partition="$1"
  lsblk -dnro TYPE "$partition" 2>/dev/null || true
}

partition_fstype() {
  local partition="$1"
  lsblk -dnro FSTYPE "$partition" 2>/dev/null || true
}

detect_boot_partition() {
  local -n out_candidates="$1"
  local name=""
  local type=""
  local fstype=""
  local parttype=""

  out_candidates=()
  while read -r name type; do
    [[ "$type" == "part" ]] || continue
    fstype="$(partition_fstype "$name")"
    parttype="$(lsblk -dnro PARTTYPE "$name" 2>/dev/null || true)"
    if [[ "$fstype" == "vfat" || "$parttype" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]; then
      out_candidates+=("$name")
    fi
  done < <(lsblk -rpno NAME,TYPE "$TARGET_DISK")
}

detect_root_partition() {
  local -n out_candidates="$1"
  local boot_partition="${2:-}"
  local name=""
  local type=""
  local fstype=""
  local parttype=""
  local mountpoints=""

  out_candidates=()
  while read -r name type; do
    [[ "$type" == "part" ]] || continue
    fstype="$(partition_fstype "$name")"
    parttype="$(lsblk -dnro PARTTYPE "$name" 2>/dev/null || true)"
    mountpoints="$(lsblk -dnro MOUNTPOINTS "$name" 2>/dev/null || true)"
    [[ "$name" == "$boot_partition" ]] && continue
    [[ "$parttype" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]] && continue
    [[ -n "$mountpoints" ]] && continue
    case "$fstype" in
      ext4|xfs|btrfs) out_candidates+=("$name") ;;
    esac
  done < <(lsblk -rpno NAME,TYPE "$TARGET_DISK" | sort)
}

pick_from_candidates() {
  local label="$1"
  local default_value="$2"
  shift 2
  local candidates=("$@")
  local idx=1
  local choice=""

  for idx in "${!candidates[@]}"; do
    printf '  %d) %s\n' "$((idx + 1))" "${candidates[$idx]}" >&2
  done

  while true; do
    read -r -p "$label [1-${#candidates[@]}] or path: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#candidates[@]})); then
      printf '%s\n' "${candidates[$((choice - 1))]}"
      return 0
    fi
    if [[ -b "$choice" ]]; then
      printf '%s\n' "$choice"
      return 0
    fi
    warn "Invalid selection."
  done
}

select_boot_partition() {
  local boot_candidates=()
  local default_boot=""

  detect_boot_partition boot_candidates
  if [[ ${#boot_candidates[@]} -eq 0 ]]; then
    warn "No EFI partition was auto-detected."
    read -r -p "Enter boot partition for /boot: " BOOT_PARTITION
    return
  fi

  if [[ ${#boot_candidates[@]} -ge 2 ]]; then
    default_boot="${boot_candidates[1]}"
  else
    default_boot="${boot_candidates[0]}"
  fi

  detail "Boot guess" "$default_boot"
  if ask_yes_no "Use this boot partition?" "yes"; then
    BOOT_PARTITION="$default_boot"
    return
  fi

  info "EFI partition candidates:"
  BOOT_PARTITION="$(pick_from_candidates "Choose /boot partition" "$default_boot" "${boot_candidates[@]}")"
}

select_root_partition() {
  local root_candidates=()
  local default_root=""

  detect_root_partition root_candidates "$BOOT_PARTITION"
  if [[ ${#root_candidates[@]} -eq 0 ]]; then
    warn "No Linux filesystem partition (ext4/xfs/btrfs) was auto-detected."
    read -r -p "Enter root partition for /: " ROOT_PARTITION
    return
  fi

  default_root="${root_candidates[$((${#root_candidates[@]} - 1))]}"
  detail "Root guess" "$default_root"
  if ask_yes_no "Use this root partition?" "yes"; then
    ROOT_PARTITION="$default_root"
    return
  fi

  info "Linux root partition candidates:"
  ROOT_PARTITION="$(pick_from_candidates "Choose / partition" "$default_root" "${root_candidates[@]}")"
}

choose_partitions() {
  while true; do
    info "Current partition layout:"
    lsblk -fp "$TARGET_DISK" >&2

    if ask_yes_no "Open cfdisk for this disk before selecting partitions?" "no"; then
      cfdisk "$TARGET_DISK"
      continue
    fi

    select_boot_partition
    select_root_partition

    if validate_partitions; then
      return 0
    fi

    warn "Partition selection is incomplete or invalid."
    ask_yes_no "Run detection again?" "yes" || die "No valid partition selection."
  done
}

validate_partitions() {
  [[ -n "$BOOT_PARTITION" && -n "$ROOT_PARTITION" ]] || return 1
  [[ "$BOOT_PARTITION" != "$ROOT_PARTITION" ]] || return 1
  [[ -b "$BOOT_PARTITION" && -b "$ROOT_PARTITION" ]] || return 1
  [[ "$(partition_type "$BOOT_PARTITION")" == "part" ]] || return 1
  [[ "$(partition_type "$ROOT_PARTITION")" == "part" ]] || return 1
}

collect_system_config() {
  local extra_user=""
  local extra_password=""
  local locale_list=""
  local locale=""

  TIMEZONE="$(prompt_choice "Timezone options" "$TIMEZONE" "${TIMEZONE_OPTIONS[@]}")"
  LOCALE="$(prompt_choice "Locale options" "$LOCALE" "${LOCALE_OPTIONS[@]}")"
  locale_list="$(prompt_default "Additional locales, space separated, or none" "none")"
  if [[ "$locale_list" != "none" ]]; then
    for locale in $locale_list; do
      ADDITIONAL_LOCALES+=("$locale")
    done
  fi
  KEYMAP="$(prompt_default "Console keymap, or none" "none")"
  [[ "$KEYMAP" == "none" ]] && KEYMAP=""
  while true; do
    read -r -p "Hostname: " HOSTNAME
    [[ -n "$HOSTNAME" ]] && break
    warn "Hostname cannot be empty."
  done

  ROOT_FILESYSTEM="$(prompt_choice "Root filesystem options" "$ROOT_FILESYSTEM" "${FILESYSTEM_OPTIONS[@]}")"
  case "$ROOT_FILESYSTEM" in
    xfs)
      BASE_PACKAGES+=(xfsprogs)
      ;;
    ext4) ;;
    btrfs)
      command -v mkfs.btrfs >/dev/null 2>&1 || die "mkfs.btrfs is not available in this live ISO."
      BASE_PACKAGES+=(btrfs-progs)
      ;;
    *) die "Unsupported root filesystem: $ROOT_FILESYSTEM" ;;
  esac
  SWAPFILE_SIZE="$(prompt_default "Swap file size, or 0 to skip" "$SWAPFILE_SIZE")"

  ROOT_PASSWORD="$(prompt_secret "root password")"

  read -r -p "Primary username: " PRIMARY_USER
  [[ "$PRIMARY_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid primary username."
  PRIMARY_PASSWORD="$(prompt_secret "$PRIMARY_USER password")"

  while ask_yes_no "Add another user?" "no"; do
    read -r -p "Username: " extra_user
    [[ "$extra_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username: $extra_user"
    extra_password="$(prompt_secret "$extra_user password")"
    EXTRA_USERS+=("$extra_user")
    EXTRA_PASSWORDS+=("$extra_password")
    if ask_yes_no "Give $extra_user sudo powers?" "no"; then
      EXTRA_SUDO+=("1")
    else
      EXTRA_SUDO+=("0")
    fi
  done
}

confirm_install_plan() {
  printf '\n' >&2
  info "Install plan:"
  detail "Disk" "$TARGET_DISK"
  detail "Boot" "$BOOT_PARTITION -> /boot"
  detail "Root" "$ROOT_PARTITION -> /"
  detail "Root fs" "$ROOT_FILESYSTEM"
  detail "Timezone" "$TIMEZONE"
  detail "Locale" "$LOCALE"
  if [[ ${#ADDITIONAL_LOCALES[@]} -gt 0 ]]; then
    detail "Extra locales" "${ADDITIONAL_LOCALES[*]}"
  fi
  detail "Hostname" "$HOSTNAME"
  detail "Primary user" "$PRIMARY_USER"
  detail "Swap file" "$SWAPFILE_SIZE"

  printf '\n%b%s%b\n' "${UI_DANGER}${UI_BOLD}" "Destructive action" "$UI_RESET" >&2
  log "The root partition will be formatted. Data on $ROOT_PARTITION will be erased."
  read -r -p "Type FORMAT to continue: " confirm
  [[ "$confirm" == "FORMAT" ]] || die "Install cancelled."
}

format_and_mount() {
  local boot_fstype=""

  case "$ROOT_FILESYSTEM" in
    ext4)
      mkfs.ext4 -F "$ROOT_PARTITION"
      ;;
    xfs)
      mkfs.xfs -f "$ROOT_PARTITION"
      ;;
    btrfs)
      mkfs.btrfs -f "$ROOT_PARTITION"
      ;;
    *)
      die "Unsupported root filesystem for this first version: $ROOT_FILESYSTEM"
      ;;
  esac

  boot_fstype="$(partition_fstype "$BOOT_PARTITION")"
  if [[ "$boot_fstype" != "vfat" ]]; then
    warn "$BOOT_PARTITION is not vfat. It must be an EFI system partition for this installer."
    read -r -p "Type FORMAT-BOOT to format it as FAT32, or anything else to stop: " confirm
    [[ "$confirm" == "FORMAT-BOOT" ]] || die "Boot partition was not formatted."
    mkfs.fat -F 32 "$BOOT_PARTITION"
  fi

  mount "$ROOT_PARTITION" "$MOUNT_POINT"
  mount --mkdir "$BOOT_PARTITION" "$MOUNT_POINT/boot"
  success "Mounted / and /boot."
  findmnt "$MOUNT_POINT" >&2
}

setup_time() {
  timedatectl set-timezone "$TIMEZONE"
  timedatectl set-ntp true
  timedatectl status
}

install_base_system() {
  info "Installing minimal base packages"
  pacstrap -K "$MOUNT_POINT" "${BASE_PACKAGES[@]}"
  genfstab -U "$MOUNT_POINT" >> "$MOUNT_POINT/etc/fstab"
  success "Base system installed and fstab generated."
}

configure_target_system() {
  local user=""
  local index=0

  arch-chroot "$MOUNT_POINT" ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  arch-chroot "$MOUNT_POINT" hwclock --systohc

  enable_locale "$LOCALE"
  for locale in "${ADDITIONAL_LOCALES[@]}"; do
    enable_locale "$locale"
  done
  arch-chroot "$MOUNT_POINT" locale-gen
  printf 'LANG=%s\n' "$LOCALE" > "$MOUNT_POINT/etc/locale.conf"

  if [[ -n "$KEYMAP" ]]; then
    printf 'KEYMAP=%s\n' "$KEYMAP" > "$MOUNT_POINT/etc/vconsole.conf"
  fi

  printf '%s\n' "$HOSTNAME" > "$MOUNT_POINT/etc/hostname"
  {
    printf '127.0.0.1 localhost\n'
    printf '::1 localhost\n'
    printf '127.0.1.1 %s.localdomain %s\n' "$HOSTNAME" "$HOSTNAME"
  } > "$MOUNT_POINT/etc/hosts"

  set_user_password "root" "$ROOT_PASSWORD"
  create_user "$PRIMARY_USER" "$PRIMARY_PASSWORD" "1"

  for user in "${EXTRA_USERS[@]}"; do
    create_user "$user" "${EXTRA_PASSWORDS[$index]}" "${EXTRA_SUDO[$index]}"
    ((index += 1))
  done

  install -Dm0440 /dev/stdin "$MOUNT_POINT/etc/sudoers.d/00-wheel" <<'SUDOERS'
%wheel ALL=(ALL:ALL) ALL
SUDOERS

  create_swapfile
  unset ROOT_PASSWORD PRIMARY_PASSWORD
  EXTRA_PASSWORDS=()
  success "Target system basics configured."
}

enable_locale() {
  local locale="$1"
  local locale_file="$MOUNT_POINT/etc/locale.gen"

  if grep -q "^#$locale UTF-8" "$locale_file"; then
    sed -i "s/^#$locale UTF-8/$locale UTF-8/" "$locale_file"
  elif ! grep -q "^$locale UTF-8" "$locale_file"; then
    printf '%s UTF-8\n' "$locale" >> "$locale_file"
  fi
}

create_user() {
  local username="$1"
  local password="$2"
  local sudo_power="$3"
  local groups=""

  if [[ "$sudo_power" == "1" ]]; then
    groups="wheel"
  fi

  if [[ -n "$groups" ]]; then
    arch-chroot "$MOUNT_POINT" useradd -m -G "$groups" -s /bin/bash "$username"
  else
    arch-chroot "$MOUNT_POINT" useradd -m -s /bin/bash "$username"
  fi
  set_user_password "$username" "$password"
}

set_user_password() {
  local username="$1"
  local password="$2"

  if [[ -n "$password" ]]; then
    printf '%s:%s\n' "$username" "$password" | arch-chroot "$MOUNT_POINT" chpasswd
  else
    arch-chroot "$MOUNT_POINT" passwd -d "$username"
    warn "No password set for $username."
  fi
}

create_swapfile() {
  [[ "$SWAPFILE_SIZE" != "0" ]] || return 0

  arch-chroot "$MOUNT_POINT" fallocate -l "$SWAPFILE_SIZE" /swapfile
  arch-chroot "$MOUNT_POINT" chmod 600 /swapfile
  arch-chroot "$MOUNT_POINT" mkswap /swapfile
  printf '/swapfile none swap defaults 0 0\n' >> "$MOUNT_POINT/etc/fstab"
  success "Swap file configured: $SWAPFILE_SIZE"
}

main() {
  init_ui
  print_banner
  require_root
  require_tools

  advance_step "Verifying live environment"
  verify_boot_mode

  advance_step "Selecting disk and partitions"
  select_disk
  choose_partitions

  advance_step "Collecting base configuration"
  collect_system_config
  confirm_install_plan

  advance_step "Formatting and mounting"
  format_and_mount

  advance_step "Setting live system time"
  setup_time

  advance_step "Installing base system"
  install_base_system

  advance_step "Configuring target system"
  configure_target_system

  final_success "Base Arch system prepared. Bootloader installation is the next stage."
}

main "$@"
