#!/bin/bash
# kmos Arch Linux Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
MOUNT_POINT="/mnt"
WIFI_HANDOFF_DIR="/run/kmos/wifi"
NODESKTOP_METAPACKAGE_DIR="$SCRIPT_DIR/packages/metapackages/nodesktop"
KDE_INSTALLER_URL="https://raw.githubusercontent.com/kamilomelo/kmos/main/platforms/archlinux/desktop/kde/kmos-kde-install.sh"
STARSHIP_PRESET_DIR="$SCRIPT_DIR/assets/starship-presets"
STARSHIP_PRESET_MODE="holow"
STARSHIP_PRESET_THEME="light"
DEBUG_MODE="${kmos_DEBUG:-0}"
PACMAN_RETRIES="${kmos_PACMAN_RETRIES:-4}"
STEP_INDEX=0
STEP_TOTAL=9

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
BOOT_PARTITION_ACTION=""
FORMAT_APPROVED=0
CONFIRMED_DISK_ID=""
CONFIRMED_DISK_SIZE=""
ROOT_FILESYSTEM="xfs"
TIMEZONE="Europe/Zurich"
LOCALE="en_US.UTF-8"
KEYMAP=""
HOSTNAME=""
SWAPFILE_SIZE="4G"
KRUB_ID="krub"
BOOTNEXT_MODULE="/usr/lib/grub/x86_64-efi/efibootnext.mod"
INCLUDE_WINDOWS="no"
BOOT_MENU_CHOICE_MADE=0
FIRMWARE_BOOT_MENU_ID=""
FIRMWARE_BOOT_MENU_ENABLED=no
WINDOWS_BOOT_PARTITION=""
WINDOWS_BOOT_UUID=""
WINDOWS_BOOT_PARTITION_ID=""
INSTALL_KDE_AUR="yes"
INSTALL_KDE="no"
INSTALL_HEADLESS_AUR="no"
DESKTOP_CHOICE_MADE=0
AUR_HELPER="${kmos_AUR_HELPER:-paru}"
KDE_PROFILE="${kmos_KDE_PROFILE:-full}"
ENABLE_WIFI_AFTER_BOOT="no"
WIFI_BACKEND="unconfigured"
WIFI_ADAPTER=""
WIFI_MAC=""
WIFI_SSID=""
WIFI_PASSWORD=""
WIFI_HIDDEN="0"
ROOT_PASSWORD=""
PRIMARY_USER=""
PRIMARY_PASSWORD=""
GRAPHICS_SUMMARY="not detected"
GRAPHICS_PACKAGE_SUMMARY="none"
MICROCODE_SUMMARY="not detected"
ADDITIONAL_LOCALES=()
declare -a EXTRA_USERS=()
declare -a EXTRA_PASSWORDS=()
declare -a EXTRA_SUDO=()

BASE_PACKAGES=(
  base
  base-devel
  git
  linux
  linux-firmware
  dhcpcd
  openssh
  sudo
  nano
)

KRUB_PACKAGES=(
  grub
  efibootmgr
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

  if [[ "${TERM:-}" == "linux" || "${ASCII_UI:-${kmos_ASCII_UI:-0}}" == "1" ]]; then
    SUCCESS_ICON=">"
    FINAL_SUCCESS_ICON="OK"
  fi
}

log() {
  printf '%s\n' "$*" >&2
}

run_cmd() {
  local output=""
  local rc=0

  if [[ "$DEBUG_MODE" == "1" ]]; then
    "$@"
    return $?
  fi

  output="$("$@" 2>&1)" || rc=$?
  if ((rc != 0)); then
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    return "$rc"
  fi
}

run_with_retry() {
  local attempts="$1"
  shift
  local try=1
  local delay=4

  while ((try <= attempts)); do
    if "$@"; then
      return 0
    fi
    if ((try == attempts)); then
      break
    fi
    warn "Command failed (attempt $try/$attempts). Retrying in ${delay}s..."
    sleep "$delay"
    ((try += 1))
  done

  return 1
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
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "kmos Arch Linux Install" "$UI_RESET" >&2
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
      read -r -p "$prompt [Y/n]: " answer || die 'Input closed before installation was approved.'
      answer="${answer:-Y}"
    elif [[ "$default" == "no" ]]; then
      read -r -p "$prompt [y/N]: " answer || die 'Input closed before installation was approved.'
      answer="${answer:-N}"
    else
      read -r -p "$prompt [y/n]: " answer || die 'Input closed before installation was approved.'
    fi

    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        shift
        [[ $# -gt 0 ]] || die "--profile requires a value."
        KDE_PROFILE="$1"
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done

  case "$KDE_PROFILE" in
    full|noapps) ;;
    *)
      die "Unknown KDE profile: $KDE_PROFILE (allowed: full, noapps)"
      ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: ./kmos-install.sh [--profile full|noapps]
       ./kmos-install.sh inspect-krub
       ./kmos-install.sh repair-panel

No argument starts the interactive x86 installation. inspect-krub reports
GRUB and firmware menu entries without changing them. repair-panel disables
only recognized old KMOS panel hooks; it preserves the personal panel layout.
EOF
}

add_package() {
  local package="$1"
  local current=""

  for current in "${BASE_PACKAGES[@]}"; do
    [[ "$current" == "$package" ]] && return 0
  done

  BASE_PACKAGES+=("$package")
}

append_unique() {
  local -n values_ref="$1"
  local value="$2"
  local current=""

  for current in "${values_ref[@]}"; do
    [[ "$current" == "$value" ]] && return 0
  done

  values_ref+=("$value")
}

load_nodesktop_metapackage() {
  local pkgbuild="$NODESKTOP_METAPACKAGE_DIR/PKGBUILD"
  local package=""

  if [[ ! -r "$pkgbuild" ]]; then
    warn "Nodesktop metapackage not found: $pkgbuild"
    return 0
  fi

  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    add_package "$package"
  done < <(source "$pkgbuild"; printf '%s\n' "${depends[@]}")

  success "Nodesktop metapackage loaded."
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value=""

  read -r -p "$prompt [$default]: " value || die 'Input closed while collecting installation choices.'
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
    read -r -p "Select [1-${#options[@]}] (default: $default_index): " choice || die 'Input closed while collecting installation choices.'
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
    read -r -s -p "$prompt: " first || die 'Input closed while collecting a password.'
    printf '\n' >&2
    if [[ -z "$first" ]]; then
      if ask_yes_no "Leave $prompt empty?" "no"; then
        printf '\n'
        return 0
      fi
      continue
    fi

    read -r -s -p "Confirm $prompt: " second || die 'Input closed while confirming a password.'
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
  ((EUID == 0)) && return
  command -v sudo >/dev/null 2>&1 || die "Root access is required, but sudo is not installed."
  info "Root access is needed for Arch installation; sudo will prompt for your password."
  exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
}

require_tools() {
  local missing=()
  local tools=(arch-chroot awk blkid cat cfdisk chmod cp dd df dirname find findmnt fsck.fat genfstab grep head install ln lspci lsblk mkdir mkfs.fat mktemp mount pacstrap partprobe readlink rm rmdir sed sort timedatectl touch tr udevadm umount)
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
      ext4|xfs|btrfs)
        out_candidates+=("$name")
        continue
        ;;
    esac

    # Accept fresh Linux partitions that are not formatted yet.
    case "$parttype" in
      0fc63daf-8483-4772-8e79-3d69d8477de4|4f68bce3-e8cd-4db1-96e7-fbcaf984b709)
        out_candidates+=("$name")
        ;;
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
  local mode=${1:-existing}
  while true; do
    info "Current partition layout:"
    lsblk -fp "$TARGET_DISK" >&2

    if [[ "$mode" == edit ]]; then
      verify_target_disk_snapshot
      if lsblk -nrpo MOUNTPOINTS "$TARGET_DISK" | grep -q .; then
        die 'A partition on the selected disk is mounted. Unmount it before opening cfdisk.'
      fi
      cfdisk "$TARGET_DISK"
      partprobe "$TARGET_DISK" || true
      udevadm settle || true
      mode=existing
      continue
    fi

    select_boot_partition
    select_root_partition

    if validate_partitions; then
      choose_boot_partition_action
      return 0
    fi

    warn "Partition selection is incomplete or invalid."
    ask_yes_no "Run detection again?" "yes" || die "No valid partition selection."
  done
}

choose_partition_mode() {
  if ask_yes_no "Open cfdisk now, before selecting partitions?" no; then
    warn 'cfdisk can write the partition table when you exit it; this cannot be undone by restarting the installer.'
    choose_partitions edit
  else
    choose_partitions
  fi
}

snapshot_target_disk() {
  CONFIRMED_DISK_ID=$(lsblk -dnro MAJ:MIN "$TARGET_DISK") || die 'Could not identify the target disk.'
  CONFIRMED_DISK_SIZE=$(lsblk -bdnro SIZE "$TARGET_DISK") || die 'Could not read target disk size.'
  [[ "$CONFIRMED_DISK_ID" =~ ^[0-9]+:[0-9]+$ && "$CONFIRMED_DISK_SIZE" =~ ^[0-9]+$ ]] \
    || die 'Target disk identity is incomplete.'
}

verify_target_disk_snapshot() {
  [[ -n "$CONFIRMED_DISK_ID" && -n "$CONFIRMED_DISK_SIZE" ]] || die 'Target disk was not confirmed.'
  [[ $(lsblk -dnro MAJ:MIN "$TARGET_DISK") == "$CONFIRMED_DISK_ID" \
    && $(lsblk -bdnro SIZE "$TARGET_DISK") == "$CONFIRMED_DISK_SIZE" ]] \
    || die 'Target disk identity or size changed after selection. Stopping before writes.'
}

validate_partitions() {
  [[ -n "$TARGET_DISK" ]] || return 1
  block_device "$TARGET_DISK" || return 1
  [[ "$(lsblk -dnro TYPE "$TARGET_DISK" 2>/dev/null)" == "disk" ]] || return 1
  [[ -n "$BOOT_PARTITION" && -n "$ROOT_PARTITION" ]] || return 1
  [[ "$(readlink -f -- "$BOOT_PARTITION")" != "$(readlink -f -- "$ROOT_PARTITION")" ]] || return 1
  block_device "$BOOT_PARTITION" && block_device "$ROOT_PARTITION" || return 1
  [[ "$(partition_type "$BOOT_PARTITION")" == "part" ]] || return 1
  [[ "$(partition_type "$ROOT_PARTITION")" == "part" ]] || return 1
  partition_on_target_disk "$BOOT_PARTITION" || return 1
  partition_on_target_disk "$ROOT_PARTITION" || return 1
  [[ "$(lsblk -dnro PARTTYPE "$BOOT_PARTITION" 2>/dev/null | tr '[:upper:]' '[:lower:]')" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]] || return 1
  [[ "$(lsblk -dnro PARTTYPE "$ROOT_PARTITION" 2>/dev/null | tr '[:upper:]' '[:lower:]')" != "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]] || return 1
  case "$(partition_fstype "$ROOT_PARTITION")" in
    ''|ext4|xfs|btrfs) ;;
    *) return 1 ;;
  esac
}

block_device() {
  [[ -b "$1" ]]
}

partition_on_target_disk() {
  local selected=""
  local name=""
  local type=""

  selected="$(readlink -f -- "$1")" || return 1
  [[ -n "$selected" ]] || return 1
  while read -r name type; do
    if [[ "$type" == "part" && "$(readlink -f -- "$name")" == "$selected" ]]; then
      return 0
    fi
  done < <(lsblk -nrpo NAME,TYPE "$TARGET_DISK")
  return 1
}

choose_boot_partition_action() {
  local fstype=""

  fstype="$(partition_fstype "$BOOT_PARTITION")"
  if [[ "$fstype" == "vfat" ]]; then
    BOOT_PARTITION_ACTION="format"
    info "Existing FAT EFI partition $BOOT_PARTITION is selected for formatting. Arch identity and Windows EFI separation will be verified before FORMAT."
  elif [[ -z "$fstype" ]]; then
    BOOT_PARTITION_ACTION="format"
    info "Unformatted EFI partition $BOOT_PARTITION will be formatted as FAT32."
  else
    die "EFI partition $BOOT_PARTITION has filesystem $fstype; refusing to reformat an unexpected filesystem."
  fi
}

collect_krub_config() {
  local package=""

  for package in "${KRUB_PACKAGES[@]}"; do
    add_package "$package"
  done

  BOOT_MENU_CHOICE_MADE=0
  info 'krub always includes Arch Linux, Advanced options and UEFI Firmware Settings; Boot Menu is added when the installed GRUB supports it.'
  select_firmware_boot_menu
  if ask_yes_no 'Also add Windows Boot Manager to krub?' no; then
    INCLUDE_WINDOWS=yes
    select_windows_efi_loader
  else
    INCLUDE_WINDOWS=no
  fi
  BOOT_MENU_CHOICE_MADE=1
}

read_handoff_value() {
  local name="$1"
  local value=""

  [[ -r "$WIFI_HANDOFF_DIR/$name" ]] || return 1
  IFS= read -r value < "$WIFI_HANDOFF_DIR/$name" || true
  printf '%s\n' "$value"
}

collect_wifi_boot_config() {
  [[ -d "$WIFI_HANDOFF_DIR" ]] || return 0

  WIFI_ADAPTER="$(read_handoff_value adapter || true)"
  WIFI_SSID="$(read_handoff_value ssid || true)"
  WIFI_PASSWORD="$(read_handoff_value password || true)"
  WIFI_HIDDEN="$(read_handoff_value hidden || true)"

  if [[ -z "$WIFI_ADAPTER" || -z "$WIFI_SSID" || -z "$WIFI_PASSWORD" ]]; then
    warn "Wi-Fi handoff data is incomplete. Run platforms/archlinux/tools/kmos-wifi-connect.sh again if you need Wi-Fi after reboot."
    ENABLE_WIFI_AFTER_BOOT="no"
    return 0
  fi

  if [[ ! -d "/sys/class/net/$WIFI_ADAPTER/wireless" ]]; then
    warn "$WIFI_ADAPTER does not look like a wireless adapter on this live system."
    ENABLE_WIFI_AFTER_BOOT="no"
    return 0
  fi

  WIFI_MAC="$(cat "/sys/class/net/$WIFI_ADAPTER/address" 2>/dev/null || true)"

  case "$WIFI_HIDDEN" in
    1) WIFI_HIDDEN="1" ;;
    *) WIFI_HIDDEN="0" ;;
  esac

  ENABLE_WIFI_AFTER_BOOT="yes"
  detail "Wi-Fi boot" "$WIFI_ADAPTER -> $WIFI_SSID"
}

detect_graphics_drivers() {
  local controller=""
  local has_intel=0
  local has_amd=0
  local has_nvidia=0
  local -a detected_vendors=()
  local -a detected_packages=()

  while IFS= read -r controller; do
    [[ -n "$controller" ]] || continue

    if [[ "$controller" == *"[8086:"* ]]; then
      has_intel=1
    elif [[ "$controller" == *"[1002:"* || "$controller" == *"[1022:"* ]]; then
      has_amd=1
    elif [[ "$controller" == *"[10de:"* ]]; then
      has_nvidia=1
    fi
  done < <(lspci -nn | grep -E 'VGA compatible controller|3D controller|Display controller' || true)

  if ((has_intel == 1)); then
    append_unique detected_vendors "Intel"
    add_package "mesa"
    add_package "vulkan-intel"
    append_unique detected_packages "mesa"
    append_unique detected_packages "vulkan-intel"
  fi

  if ((has_amd == 1)); then
    append_unique detected_vendors "AMD"
    add_package "mesa"
    add_package "vulkan-radeon"
    append_unique detected_packages "mesa"
    append_unique detected_packages "vulkan-radeon"
  fi

  if ((has_nvidia == 1)); then
    append_unique detected_vendors "NVIDIA"
    if ask_yes_no "NVIDIA GPU detected. Install nvidia-open driver?" "yes"; then
      add_package "nvidia-open"
      add_package "nvidia-utils"
      add_package "nvtop"
      append_unique detected_packages "nvidia-open"
      append_unique detected_packages "nvidia-utils"
      append_unique detected_packages "nvtop"
    fi
  fi

  if [[ ${#detected_vendors[@]} -eq 0 ]]; then
    GRAPHICS_SUMMARY="no supported GPU detected"
    GRAPHICS_PACKAGE_SUMMARY="none"
    warn "No Intel, AMD, or NVIDIA display controller was detected from the live system."
    return 0
  fi

  GRAPHICS_SUMMARY="${detected_vendors[*]}"
  if [[ ${#detected_packages[@]} -gt 0 ]]; then
    GRAPHICS_PACKAGE_SUMMARY="${detected_packages[*]}"
  else
    GRAPHICS_PACKAGE_SUMMARY="none"
  fi
  detail "Graphics" "$GRAPHICS_SUMMARY"
  detail "GPU pkgs" "$GRAPHICS_PACKAGE_SUMMARY"
}

detect_cpu_microcode() {
  local cpu_info=""

  cpu_info="$(grep -m1 '^vendor_id[[:space:]]*:' /proc/cpuinfo 2>/dev/null || true)"

  if [[ "$cpu_info" == *"GenuineIntel"* ]]; then
    add_package "intel-ucode"
    MICROCODE_SUMMARY="intel-ucode"
  elif [[ "$cpu_info" == *"AuthenticAMD"* ]]; then
    add_package "amd-ucode"
    MICROCODE_SUMMARY="amd-ucode"
  else
    MICROCODE_SUMMARY="none"
    warn "CPU vendor not recognized for microcode package."
  fi
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
      command -v mkfs.xfs >/dev/null 2>&1 || die "mkfs.xfs is not available in this live ISO."
      add_package "xfsprogs"
      ;;
    ext4)
      command -v mkfs.ext4 >/dev/null 2>&1 || die "mkfs.ext4 is not available in this live ISO."
      ;;
    btrfs)
      command -v mkfs.btrfs >/dev/null 2>&1 || die "mkfs.btrfs is not available in this live ISO."
      add_package "btrfs-progs"
      ;;
    *) die "Unsupported root filesystem: $ROOT_FILESYSTEM" ;;
  esac

  detect_graphics_drivers
  detect_cpu_microcode
  load_nodesktop_metapackage
  collect_krub_config
  collect_wifi_boot_config
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

collect_desktop_config() {
  local choice
  info 'Select desktop and AUR options now; installation will not ask again later.'
  DESKTOP_CHOICE_MADE=0
  printf '  1) Headless (no KDE)\n  2) KDE desktop (%s)\n' "$KDE_PROFILE" >&2
  while true; do
    printf 'Choose system type [1/2] (required, no default): ' >&2
    read -r choice || die 'No desktop/headless choice received; installation cancelled before FORMAT.'
    case "$choice" in
      1) INSTALL_KDE=no; break ;;
      2) INSTALL_KDE=yes; break ;;
      *) warn 'Choose 1 for headless or 2 for KDE. Enter alone does not select KDE.' ;;
    esac
  done
  DESKTOP_CHOICE_MADE=1
  if [[ "$INSTALL_KDE" == yes ]]; then
    # KDE migrates the live Wi-Fi handoff to NetworkManager from its WPA file.
    add_package wpa_supplicant
    WIFI_BACKEND=networkmanager
    if [[ "$KDE_PROFILE" == full ]] && ask_yes_no "Install an AUR helper and AUR desktop packages?" yes; then
      INSTALL_KDE_AUR=yes
      AUR_HELPER="$(prompt_choice "AUR helper options" "$AUR_HELPER" paru yay)"
    else
      INSTALL_KDE_AUR=no
    fi
  elif ask_yes_no "Install an AUR helper for this headless system?" yes; then
    INSTALL_HEADLESS_AUR=yes
    AUR_HELPER="$(prompt_choice "AUR helper options" "$AUR_HELPER" paru yay)"
  else
    INSTALL_HEADLESS_AUR=no
  fi
  if [[ "$INSTALL_KDE" == no ]]; then
    # Impala and iwd come from the nodesktop package manifest.
    pacman -Si impala >/dev/null 2>&1 || die 'Impala is not in the live ISO package databases; cannot approve a headless install that promises it.'
    if [[ "$ENABLE_WIFI_AFTER_BOOT" == yes ]]; then
      if [[ -d "$WIFI_HANDOFF_DIR/iwd" ]] \
        && find "$WIFI_HANDOFF_DIR/iwd" -maxdepth 1 -type f -print -quit | grep -q .; then
        WIFI_BACKEND=iwd
      else
        WIFI_BACKEND=wpa
        add_package wpa_supplicant
        warn 'No working iwd profile was handed off. wpa_supplicant is required for first-boot Wi-Fi as a last-resort fallback; Impala/iwd will still be installed, but not enabled alongside WPA.'
      fi
    fi
  fi
}

confirm_install_plan() {
  local extra_user_summary=""
  local extra_sudo_summary=""
  local idx=0
  local confirm=""
  ((DESKTOP_CHOICE_MADE == 1)) || die 'Desktop/headless choice was not collected; cannot approve formatting.'
  ((BOOT_MENU_CHOICE_MADE == 1)) || die 'Boot Menu and Windows policy were not collected; cannot approve formatting.'

  printf '\n' >&2
  info "Install plan:"
  detail "Disk" "$TARGET_DISK"
  detail "Disk identity" "$CONFIRMED_DISK_ID / $CONFIRMED_DISK_SIZE bytes"
  detail "Boot" "$BOOT_PARTITION -> /boot"
  detail "Boot action" "$BOOT_PARTITION_ACTION"
  detail "Root" "$ROOT_PARTITION -> /"
  detail "Root fs" "$ROOT_FILESYSTEM"
  detail "Bootloader" "$KRUB_ID"
  if [[ -n "$FIRMWARE_BOOT_MENU_ID" ]]; then
    detail "Boot Menu" "Boot$FIRMWARE_BOOT_MENU_ID (if supported by target GRUB)"
  else
    detail "Boot Menu" 'unavailable (optional)'
  fi
  detail "Windows entry" "$INCLUDE_WINDOWS"
  if [[ "$INCLUDE_WINDOWS" == yes ]]; then detail "Windows EFI" "$WINDOWS_BOOT_PARTITION"; fi
  detail "Graphics" "$GRAPHICS_SUMMARY"
  detail "GPU pkgs" "$GRAPHICS_PACKAGE_SUMMARY"
  detail "Microcode" "$MICROCODE_SUMMARY"
  detail "Metapackage" "kmos-nodesktop"
  detail "SSH" "enabled"
  detail "Starship" "$STARSHIP_PRESET_MODE/$STARSHIP_PRESET_THEME"
  if [[ "$ENABLE_WIFI_AFTER_BOOT" == "yes" ]]; then
    detail "Wi-Fi boot" "$WIFI_ADAPTER -> $WIFI_SSID"
  else
    detail "Wi-Fi boot" "not configured"
  fi
  detail "Timezone" "$TIMEZONE"
  detail "Locale" "$LOCALE"
  detail "Keymap" "${KEYMAP:-unchanged}"
  if [[ ${#ADDITIONAL_LOCALES[@]} -gt 0 ]]; then
    detail "Extra locales" "${ADDITIONAL_LOCALES[*]}"
  fi
  detail "Hostname" "$HOSTNAME"
  detail "Primary user" "$PRIMARY_USER"
  if [[ ${#EXTRA_USERS[@]} -gt 0 ]]; then
    extra_user_summary="${EXTRA_USERS[*]}"
    for idx in "${!EXTRA_USERS[@]}"; do
      if [[ "${EXTRA_SUDO[$idx]}" == "1" ]]; then
        extra_sudo_summary+="${EXTRA_USERS[$idx]} "
      fi
    done
    detail "Other users" "$extra_user_summary"
    detail "Other sudo" "${extra_sudo_summary:-none}"
  fi
  detail "Swap file" "$SWAPFILE_SIZE"
  if [[ "$INSTALL_KDE" == yes ]]; then
    detail "Desktop" "KDE $KDE_PROFILE"
    detail "AUR packages" "$INSTALL_KDE_AUR"
  else
    detail "Desktop" "headless"
    detail "Wi-Fi tools" "Impala + iwd; first-boot backend: $WIFI_BACKEND"
    detail "AUR helper" "$INSTALL_HEADLESS_AUR"
  fi
  if [[ "$INSTALL_KDE_AUR" == yes && "$INSTALL_KDE" == yes || "$INSTALL_HEADLESS_AUR" == yes && "$INSTALL_KDE" == no ]]; then
    detail "AUR helper" "$AUR_HELPER"
  fi

  printf '\n%b%s%b\n' "${UI_DANGER}${UI_BOLD}" "Destructive action" "$UI_RESET" >&2
  warn 'If this plan is wrong, press Ctrl+C and restart before FORMAT. Restarting cannot undo changes saved in cfdisk.'
  log "The root partition will be formatted. Data on $ROOT_PARTITION will be erased."
  if [[ "$BOOT_PARTITION_ACTION" == "format" ]]; then
    log "The boot partition will be formatted as FAT32. Data on $BOOT_PARTITION will be erased."
  else
    log "The existing EFI filesystem on $BOOT_PARTITION will NOT be formatted; Arch and GRUB will add files to it."
  fi
  while true; do
    read -r -p 'Type FORMAT to continue or EXIT to cancel: ' confirm || die 'Input closed before final confirmation; no filesystem was formatted.'
    case "$confirm" in
      EXIT)
        die "Install cancelled."
        ;;
    esac
    [[ "$confirm" == FORMAT ]] && break
    warn 'Type FORMAT exactly to approve the displayed partitions and EFI action.'
  done
  FORMAT_APPROVED=1
}

preflight_partitions() {
  local partition=""
  local mounted=""
  local fstype=""
  local size=""

  validate_partitions || die "Partitions no longer match the selected disk or the EFI partition is invalid. Nothing was formatted."
  case "$BOOT_PARTITION_ACTION" in
    format|reuse) ;;
    *) die "No EFI action selected. Nothing was formatted." ;;
  esac
  if [[ "$INCLUDE_WINDOWS" == yes && "$BOOT_PARTITION_ACTION" == format \
    && $(readlink -f -- "$BOOT_PARTITION") == "$(readlink -f -- "$WINDOWS_BOOT_PARTITION")" ]]; then
    die 'The selected boot partition is the Windows EFI partition. It cannot be formatted.'
  fi

  for partition in "$ROOT_PARTITION" "$BOOT_PARTITION"; do
    mounted="$(lsblk -dnro MOUNTPOINTS "$partition" 2>/dev/null)"
    [[ -z "$mounted" ]] || die "$partition is mounted or active ($mounted). Unmount it before installation."
  done

  fstype="$(partition_fstype "$BOOT_PARTITION")"
  if [[ "$BOOT_PARTITION_ACTION" == "reuse" ]]; then
    [[ "$fstype" == "vfat" ]] || die "EFI partition $BOOT_PARTITION is no longer FAT. Nothing was formatted."
    check_reused_efi_space || die "Existing EFI partition has insufficient free space or cannot be mounted read-only. Nothing was formatted."
  else
    [[ -z "$fstype" || "$fstype" == "vfat" ]] || die "EFI partition $BOOT_PARTITION has an unexpected filesystem ($fstype). Nothing was formatted."
    size="$(lsblk -bdnro SIZE "$BOOT_PARTITION")"
    [[ "$size" =~ ^[0-9]+$ ]] || die "Could not read EFI partition size. Nothing was formatted."
    ((size >= 536870912)) || die "EFI partition must be at least 512 MiB. Nothing was formatted."
    if [[ "$fstype" == vfat ]]; then
      verify_existing_efi_is_not_windows \
        || die 'Could not prove the selected existing EFI partition is separate from Windows. No filesystems were formatted.'
    fi
  fi
}

selected_efi_identity() (
  local mount_dir
  mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/kmos-selected-efi.XXXXXXXX") || return 2
  trap 'if findmnt -rn --mountpoint "$mount_dir" >/dev/null 2>&1; then umount "$mount_dir"; fi; rmdir "$mount_dir"' EXIT
  mount -o ro,nosuid,nodev,noexec "$BOOT_PARTITION" "$mount_dir" || return 2
  if [[ -f "$mount_dir/EFI/Microsoft/Boot/bootmgfw.efi" ]]; then
    printf 'windows\n'
  elif [[ -f "$mount_dir/EFI/$KRUB_ID/grubx64.efi" ]]; then
    printf 'arch\n'
  elif find "$mount_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    printf 'unknown\n'
  else
    printf 'empty\n'
  fi
)

verify_existing_efi_is_not_windows() {
  local selected_id windows_id windows_partition windows_uuid scan_output firmware selected_partuuid line identity
  local -a windows_loaders=()

  identity=$(selected_efi_identity) || { warn "Could not inspect $BOOT_PARTITION read-only; refusing to format it."; return 1; }
  case "$identity" in
    arch|empty) ;;
    windows) warn "Windows Boot Manager exists on $BOOT_PARTITION. It will not be formatted."; return 1 ;;
    *) warn "The selected EFI partition is not recognizable as Arch or empty: $BOOT_PARTITION. Refusing to format it."; return 1 ;;
  esac
  scan_output=$(scan_windows_efi_loaders) || { warn 'Could not inspect Windows EFI partitions read-only.'; return 1; }
  [[ -n "$scan_output" ]] || { warn 'A separate Windows EFI partition was not found.'; return 1; }
  mapfile -t windows_loaders <<< "$scan_output"
  ((${#windows_loaders[@]} == 1)) || { warn 'Multiple Windows EFI partitions found; refusing to guess.'; return 1; }
  IFS='|' read -r windows_partition windows_uuid windows_id <<< "${windows_loaders[0]}"
  [[ "$windows_uuid" =~ ^[[:xdigit:]-]{4,40}$ && "$windows_id" =~ ^[0-9]+:[0-9]+$ ]] \
    || { warn 'The Windows EFI identity is incomplete.'; return 1; }
  selected_id=$(lsblk -dnro MAJ:MIN "$BOOT_PARTITION") || return 1
  [[ "$selected_id" =~ ^[0-9]+:[0-9]+$ && "$selected_id" != "$windows_id" ]] \
    || { warn 'The selected EFI partition appears to be the Windows EFI partition.'; return 1; }

  # Cross-check the firmware record as well as the EFI files; never erase an
  # ESP that firmware still identifies as Windows, even if its loader is gone.
  selected_partuuid=$(lsblk -dnro PARTUUID "$BOOT_PARTITION" 2>/dev/null | tr '[:upper:]' '[:lower:]')
  [[ "$selected_partuuid" =~ ^[[:xdigit:]-]{36}$ ]] \
    || { warn 'Could not verify the selected EFI partition GUID.'; return 1; }
  firmware=$(efibootmgr -v 2>/dev/null) \
    || { warn 'Could not verify the firmware Windows Boot Manager location.'; return 1; }
  while IFS= read -r line; do
    if [[ "$line" =~ ^Boot[[:xdigit:]]{4}\*?[[:space:]]+Windows[[:space:]]Boot[[:space:]]Manager([[:space:]]|$) \
      && "$line" =~ HD\([0-9]+,GPT,([[:xdigit:]-]{36}), ]]; then
      if [[ "${BASH_REMATCH[1],,}" == "$selected_partuuid" ]]; then
        warn "Firmware's Windows Boot Manager points to $BOOT_PARTITION; refusing to format it."
        return 1
      fi
    fi
  done <<< "$firmware"
  info "Verified separate Windows EFI at $windows_partition; only $BOOT_PARTITION will be formatted."
}

check_reused_efi_space() (
  local temp_mount=""
  local available_kb=""

  temp_mount="$(mktemp -d /tmp/kmos-efi.XXXXXXXX)" || return 1
  trap 'if findmnt -rn --mountpoint "$temp_mount" >/dev/null 2>&1; then umount "$temp_mount"; fi; rmdir "$temp_mount"' EXIT
  mount -o ro,nosuid,nodev,noexec "$BOOT_PARTITION" "$temp_mount" || return 1
  available_kb="$(df -Pk "$temp_mount" | awk 'NR==2 {print $4}')"
  [[ "$available_kb" =~ ^[0-9]+$ ]] && ((available_kb >= 524288))
)

format_and_mount() {
  local detected_root_fstype=""

  ((FORMAT_APPROVED == 1)) || die 'Formatting requires the explicit FORMAT confirmation.'
  verify_target_disk_snapshot
  preflight_partitions

  case "$ROOT_FILESYSTEM" in
    ext4)
      run_cmd mkfs.ext4 -F "$ROOT_PARTITION"
      ;;
    xfs)
      run_cmd mkfs.xfs -f "$ROOT_PARTITION"
      ;;
    btrfs)
      run_cmd mkfs.btrfs -f "$ROOT_PARTITION"
      ;;
    *)
      die "Unsupported root filesystem for this first version: $ROOT_FILESYSTEM"
      ;;
  esac

  run_cmd partprobe "$TARGET_DISK" || true
  udevadm settle || true
  detected_root_fstype="$(blkid -o value -s TYPE "$ROOT_PARTITION" 2>/dev/null || true)"
  [[ "$detected_root_fstype" == "$ROOT_FILESYSTEM" ]] || die "Expected $ROOT_PARTITION to be formatted as $ROOT_FILESYSTEM, but detected: ${detected_root_fstype:-unknown}"

  if [[ "$BOOT_PARTITION_ACTION" == "format" ]]; then
    run_cmd mkfs.fat -F 32 "$BOOT_PARTITION"
    run_cmd partprobe "$TARGET_DISK" || true
    udevadm settle || true
  fi

  if findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
    umount -R "$MOUNT_POINT" || die "$MOUNT_POINT is already mounted and could not be unmounted."
  fi

  run_cmd mount -t "$ROOT_FILESYSTEM" "$ROOT_PARTITION" "$MOUNT_POINT"
  run_cmd mount --mkdir "$BOOT_PARTITION" "$MOUNT_POINT/boot"
  verify_boot_writable
  success "Mounted / and /boot."
  if [[ "$DEBUG_MODE" == "1" ]]; then
    findmnt "$MOUNT_POINT" >&2
  fi
}

verify_boot_writable() {
  local boot_test_file="$MOUNT_POINT/boot/.kmos-boot-write-test"
  local available_kb=""

  available_kb="$(df -Pk "$MOUNT_POINT/boot" | awk 'NR==2 {print $4}')"
  [[ -n "$available_kb" ]] || die "Could not read free space on $MOUNT_POINT/boot."
  if ((available_kb < 65536)); then
    die "Not enough free space on $MOUNT_POINT/boot (${available_kb}KB). Need at least 65536KB."
  fi

  if ! dd if=/dev/zero of="$boot_test_file" bs=1 count=1 conv=fsync status=none; then
    die "Cannot write to $MOUNT_POINT/boot. Check EFI partition health and hardware before continuing."
  fi
  rm -f "$boot_test_file"
}

setup_time() {
  run_cmd timedatectl set-timezone "$TIMEZONE"
  run_cmd timedatectl set-ntp true
  if [[ "$DEBUG_MODE" == "1" ]]; then
    timedatectl status
  fi
}

install_base_system() {
  local live_pacman_conf="/etc/pacman.conf"
  local pacman_conf="/tmp/kmos-pacman.conf"

  cleanup_boot_artifacts
  info "Installing minimal base packages"
  cp "$live_pacman_conf" "$pacman_conf"
  if ! grep -q '^DisableDownloadTimeout$' "$pacman_conf"; then
    printf '\nDisableDownloadTimeout\n' >> "$pacman_conf"
  fi
  if grep -q '^ParallelDownloads = ' "$pacman_conf"; then
    sed -i 's/^ParallelDownloads = .*/ParallelDownloads = 6/' "$pacman_conf"
  elif grep -q '^#ParallelDownloads = ' "$pacman_conf"; then
    sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 6/' "$pacman_conf"
  else
    printf 'ParallelDownloads = 6\n' >> "$pacman_conf"
  fi

  run_with_retry "$PACMAN_RETRIES" pacstrap -C "$pacman_conf" -K "$MOUNT_POINT" "${BASE_PACKAGES[@]}" || die "pacstrap failed after ${PACMAN_RETRIES} attempts."
  genfstab -U "$MOUNT_POINT" >> "$MOUNT_POINT/etc/fstab"
  success "Base system installed and fstab generated."
}

cleanup_boot_artifacts() {
  local removed=0
  local artifact=""
  local artifacts=(
    "$MOUNT_POINT/boot/intel-ucode.img"
    "$MOUNT_POINT/boot/amd-ucode.img"
    "$MOUNT_POINT/boot/initramfs-linux.img"
    "$MOUNT_POINT/boot/initramfs-linux-fallback.img"
    "$MOUNT_POINT/boot/vmlinuz-linux"
  )

  for artifact in "${artifacts[@]}"; do
    if [[ -e "$artifact" ]]; then
      rm -f "$artifact"
      removed=1
    fi
  done

  if ((removed == 1)); then
    success "Removed stale boot artifacts from /boot before pacstrap."
  fi
}

configure_pacman() {
  local pacman_conf="$MOUNT_POINT/etc/pacman.conf"

  if [[ ! -f "$pacman_conf" ]]; then
    warn "Could not find target pacman.conf."
    return 0
  fi

  sed -i 's/^#Color$/Color/' "$pacman_conf"

  if grep -q '^#ParallelDownloads = ' "$pacman_conf"; then
    sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 6/' "$pacman_conf"
  elif grep -q '^ParallelDownloads = ' "$pacman_conf"; then
    sed -i 's/^ParallelDownloads = .*/ParallelDownloads = 6/' "$pacman_conf"
  else
    printf '\nParallelDownloads = 6\n' >> "$pacman_conf"
  fi

  if ! grep -q '^ILoveCandy$' "$pacman_conf"; then
    sed -i '/^ParallelDownloads = 6$/a ILoveCandy' "$pacman_conf"
  fi

  success "Pacman configured."
}

configure_target_system() {
  local user=""
  local index=0

  configure_pacman

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

  configure_ssh
  install_kmos_assets
  configure_starship_bash
  configure_wifi_after_boot
  configure_wired_network_after_boot
  create_swapfile
  unset ROOT_PASSWORD PRIMARY_PASSWORD WIFI_PASSWORD
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

configure_ssh() {
  local sshd_config="$MOUNT_POINT/etc/ssh/sshd_config"

  if [[ -f "$sshd_config" ]] && ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*.conf' "$sshd_config"; then
    sed -i '1iInclude /etc/ssh/sshd_config.d/*.conf' "$sshd_config"
  fi

  install -Dm0644 /dev/stdin "$MOUNT_POINT/etc/ssh/sshd_config.d/10-kmos.conf" <<'SSHD_CONFIG'
PermitRootLogin no
PermitEmptyPasswords no
PasswordAuthentication yes
SSHD_CONFIG

  arch-chroot "$MOUNT_POINT" systemctl enable sshd.service
  success "OpenSSH enabled for first boot."
}

bootstrap_paru() {
  local sudoers_file="$MOUNT_POINT/etc/sudoers.d/10-kmos-paru-bootstrap"
  local aur_root="/home/$PRIMARY_USER/.kaur"

  if arch-chroot "$MOUNT_POINT" bash -lc "command -v paru >/dev/null 2>&1 && paru --version >/dev/null 2>&1"; then
    return 0
  fi

  arch-chroot "$MOUNT_POINT" mkdir -p "$aur_root"
  arch-chroot "$MOUNT_POINT" rm -rf "$aur_root/paru-bin" "$aur_root/paru"
  arch-chroot "$MOUNT_POINT" chown -R "$PRIMARY_USER:$PRIMARY_USER" "/home/$PRIMARY_USER/.kaur"

  install -Dm0440 /dev/stdin "$sudoers_file" <<EOF
$PRIMARY_USER ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman
EOF

  if arch-chroot "$MOUNT_POINT" runuser -u "$PRIMARY_USER" -- bash -lc "git clone https://aur.archlinux.org/paru-bin.git '$aur_root/paru-bin'"; then
    if arch-chroot "$MOUNT_POINT" runuser -u "$PRIMARY_USER" -- bash -lc "cd '$aur_root/paru-bin' && makepkg -si --noconfirm --needed --clean --cleanbuild"; then
      if arch-chroot "$MOUNT_POINT" bash -lc "command -v paru >/dev/null 2>&1 && paru --version >/dev/null 2>&1"; then
        rm -f "$sudoers_file"
        success "paru-bin bootstrapped in the base system."
        return 0
      fi
      warn "paru-bin installed but is not runnable on this target. Falling back to source build."
    fi
  else
    warn "Could not clone paru-bin from AUR. Falling back to source build."
  fi
  arch-chroot "$MOUNT_POINT" pacman -Rns --noconfirm paru-bin paru-bin-debug >/dev/null 2>&1 || true

  arch-chroot "$MOUNT_POINT" pacman -S --needed --noconfirm rust cargo
  arch-chroot "$MOUNT_POINT" runuser -u "$PRIMARY_USER" -- bash -lc "git clone https://aur.archlinux.org/paru.git '$aur_root/paru'" || die "Could not clone paru from AUR."
  if ! arch-chroot "$MOUNT_POINT" runuser -u "$PRIMARY_USER" -- bash -lc "cd '$aur_root/paru' && makepkg -si --noconfirm --needed --clean --cleanbuild"; then
    rm -f "$sudoers_file"
    die "Could not build/install paru."
  fi

  rm -f "$sudoers_file"
  arch-chroot "$MOUNT_POINT" pacman -Rns --noconfirm rust cargo >/dev/null 2>&1 || warn "Could not remove temporary Rust build packages."
  success "paru bootstrapped in the base system."
}

bootstrap_yay() {
  local sudoers_file="$MOUNT_POINT/etc/sudoers.d/10-kmos-yay-bootstrap"
  local aur_root="/home/$PRIMARY_USER/.kaur"

  if arch-chroot "$MOUNT_POINT" bash -lc "command -v yay >/dev/null 2>&1 && yay --version >/dev/null 2>&1"; then
    return 0
  fi

  arch-chroot "$MOUNT_POINT" mkdir -p "$aur_root"
  arch-chroot "$MOUNT_POINT" rm -rf "$aur_root/yay-bin"
  arch-chroot "$MOUNT_POINT" chown -R "$PRIMARY_USER:$PRIMARY_USER" "/home/$PRIMARY_USER/.kaur"

  install -Dm0440 /dev/stdin "$sudoers_file" <<EOF
$PRIMARY_USER ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman
EOF

  arch-chroot "$MOUNT_POINT" runuser -u "$PRIMARY_USER" -- bash -lc "git clone https://aur.archlinux.org/yay-bin.git '$aur_root/yay-bin'" || {
    rm -f "$sudoers_file"
    die "Could not clone yay-bin from AUR."
  }
  if ! arch-chroot "$MOUNT_POINT" runuser -u "$PRIMARY_USER" -- bash -lc "cd '$aur_root/yay-bin' && makepkg -si --noconfirm --needed --clean --cleanbuild"; then
    rm -f "$sudoers_file"
    die "Could not install yay-bin."
  fi
  if ! arch-chroot "$MOUNT_POINT" bash -lc "command -v yay >/dev/null 2>&1 && yay --version >/dev/null 2>&1"; then
    rm -f "$sudoers_file"
    die "yay-bin installed but yay is not runnable on this target."
  fi

  rm -f "$sudoers_file"
  success "yay-bin bootstrapped in the base system."
}

bootstrap_aur_helper() {
  case "$AUR_HELPER" in
    paru) bootstrap_paru ;;
    yay) bootstrap_yay ;;
    *) die "Unknown AUR helper: $AUR_HELPER" ;;
  esac
}

install_kmos_assets() {
  local preset=""

  if [[ -r "$NODESKTOP_METAPACKAGE_DIR/PKGBUILD" ]]; then
    install -Dm0644 "$NODESKTOP_METAPACKAGE_DIR/PKGBUILD" "$MOUNT_POINT/usr/share/kmos/metapackages/nodesktop/PKGBUILD"
  fi

  if [[ -d "$SCRIPT_DIR/assets" ]]; then
    install -d -m 0755 "$MOUNT_POINT/opt/kmos/assets"
    cp -a "$SCRIPT_DIR/assets/." "$MOUNT_POINT/opt/kmos/assets/"
  fi

  if [[ -d "$STARSHIP_PRESET_DIR" ]]; then
    install -d -m 0755 "$MOUNT_POINT/usr/share/kmos/starship-presets"
    for preset in "$STARSHIP_PRESET_DIR"/*.toml; do
      [[ -e "$preset" ]] || continue
      install -m 0644 "$preset" "$MOUNT_POINT/usr/share/kmos/starship-presets/${preset##*/}"
    done
  fi
}

configure_starship_bash() {
  local bashrc="$MOUNT_POINT/etc/bash.bashrc"

  install -Dm0644 /dev/stdin "$MOUNT_POINT/etc/profile.d/10-kmos-starship.sh" <<'STARSHIP_PROFILE'
if [[ -f /usr/share/kmos/kde-profile || -f /usr/share/xsessions/plasma.desktop || -f /usr/share/wayland-sessions/plasma.desktop ]]; then
  export STARSHIP_CONFIG=/usr/share/kmos/starship-presets/holow-light.toml
elif [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]]; then
  export STARSHIP_CONFIG=/usr/share/kmos/starship-presets/holow-light.toml
else
  export STARSHIP_CONFIG=/usr/share/kmos/starship-presets/tty-term.toml
fi
STARSHIP_PROFILE

  touch "$bashrc"
  if ! grep -q 'starship init bash' "$bashrc"; then
    cat >> "$bashrc" <<'BASHRC'

# kmos Starship prompt
if [[ $- == *i* ]] && command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi

# kmos zoxide
if [[ $- == *i* ]] && command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi
BASHRC
  fi

  if ! grep -q '^# kmos default editor$' "$bashrc"; then
    cat >> "$bashrc" <<'BASHRC_EDITOR'

# kmos default editor
export EDITOR=nano
export VISUAL=nano
BASHRC_EDITOR
  fi

  success "Starship configured for Bash."
}

wpa_quote() {
  local value="$1"

  value="$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '"%s"' "$value"
}

configure_wifi_after_boot() {
  local wpa_config="$MOUNT_POINT/etc/wpa_supplicant/wpa_supplicant-$WIFI_ADAPTER.conf"
  local link_config="$MOUNT_POINT/etc/systemd/network/10-kmos-wifi.link"
  local iwd_handoff="$WIFI_HANDOFF_DIR/iwd"
  local iwd_target="$MOUNT_POINT/var/lib/iwd"
  local use_iwd=0

  [[ "$ENABLE_WIFI_AFTER_BOOT" == "yes" ]] || return 0

  install -d -m 0755 "$MOUNT_POINT/etc/systemd/network"
  if [[ "$INSTALL_KDE" == no && "$WIFI_BACKEND" == iwd ]]; then
    if [[ ! -d "$iwd_handoff" ]] \
      || ! find "$iwd_handoff" -maxdepth 1 -type f -print -quit | grep -q .; then
      die 'The working iwd profile disappeared after the plan was approved; refusing to switch silently to WPA.'
    fi
    install -d -m 0700 "$iwd_target" "$MOUNT_POINT/etc/iwd"
    cp -a "$iwd_handoff/." "$iwd_target/"
    chown -R root:root "$iwd_target"
    chmod -R go-rwx "$iwd_target"
    install -Dm0644 /dev/stdin "$MOUNT_POINT/etc/iwd/main.conf" <<'IWD_CONFIG'
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
IWD_CONFIG
    use_iwd=1
  elif [[ "$INSTALL_KDE" == yes || "$WIFI_BACKEND" == wpa ]]; then
    install -d -m 0755 "$MOUNT_POINT/etc/wpa_supplicant"
    {
      printf 'ctrl_interface=DIR=/run/wpa_supplicant GROUP=wheel\n'
      printf 'update_config=0\n\nnetwork={\n'
      printf '    ssid=%s\n' "$(wpa_quote "$WIFI_SSID")"
      if [[ "$WIFI_HIDDEN" == "1" ]]; then
        printf '    scan_ssid=1\n'
      fi
      printf '    psk=%s\n    key_mgmt=WPA-PSK\n}\n' "$(wpa_quote "$WIFI_PASSWORD")"
    } > "$wpa_config"
    chmod 600 "$wpa_config"
  else
    die 'No persistent Wi-Fi backend was approved before FORMAT.'
  fi

  if [[ -n "$WIFI_MAC" ]]; then
    install -Dm0644 /dev/stdin "$link_config" <<WIFI_LINK
[Match]
MACAddress=$WIFI_MAC

[Link]
Name=$WIFI_ADAPTER
WIFI_LINK
  fi

  if ((use_iwd == 1)); then
    arch-chroot "$MOUNT_POINT" systemctl disable "wpa_supplicant@$WIFI_ADAPTER.service" "dhcpcd@$WIFI_ADAPTER.service" >/dev/null 2>&1 || true
    if ! arch-chroot "$MOUNT_POINT" systemctl enable iwd.service systemd-resolved.service; then
      warn 'Could not enable persistent iwd networking. No WPA fallback was approved or installed.'
      arch-chroot "$MOUNT_POINT" systemctl disable iwd.service systemd-resolved.service >/dev/null 2>&1 || true
      die 'iwd could not be enabled; do not reboot expecting Wi-Fi.'
    else
      arch-chroot "$MOUNT_POINT" ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    fi
  fi

  if ((use_iwd == 0)); then
    if ! arch-chroot "$MOUNT_POINT" systemctl enable "wpa_supplicant@$WIFI_ADAPTER.service"; then
      warn "Could not enable wpa_supplicant@$WIFI_ADAPTER.service. The base install will continue."
      return 0
    fi
    if ! arch-chroot "$MOUNT_POINT" systemctl enable "dhcpcd@$WIFI_ADAPTER.service"; then
      warn "Could not enable dhcpcd@$WIFI_ADAPTER.service. The base install will continue."
      return 0
    fi
  fi
  rm -f "$WIFI_HANDOFF_DIR/adapter" "$WIFI_HANDOFF_DIR/ssid" "$WIFI_HANDOFF_DIR/password" "$WIFI_HANDOFF_DIR/hidden"
  rm -rf "$iwd_handoff"
  rmdir "$WIFI_HANDOFF_DIR" 2>/dev/null || true
  if ((use_iwd == 1)); then
    success "Wi-Fi configured for first boot with the working iwd profile."
  else
    success "Wi-Fi configured for first boot with wpa_supplicant."
  fi
}

configure_wired_network_after_boot() {
  [[ "$ENABLE_WIFI_AFTER_BOOT" == "yes" ]] && return 0

  if [[ "$INSTALL_KDE" == no ]]; then
    arch-chroot "$MOUNT_POINT" systemctl enable iwd.service \
      || die 'Could not enable iwd for future Impala connections on this headless install.'
  fi
  arch-chroot "$MOUNT_POINT" systemctl enable dhcpcd.service
  success "Wired DHCP enabled for first boot."
}

create_swapfile() {
  local size_mib=""

  [[ "$SWAPFILE_SIZE" != "0" ]] || return 0

  size_mib="$(swapfile_size_mib "$SWAPFILE_SIZE")"
  rm -f "$MOUNT_POINT/swapfile"
  sed -i '\|^/swapfile |d' "$MOUNT_POINT/etc/fstab"

  if [[ "$ROOT_FILESYSTEM" == "btrfs" ]]; then
    arch-chroot "$MOUNT_POINT" btrfs filesystem mkswapfile --size "${size_mib}M" /swapfile
    arch-chroot "$MOUNT_POINT" chmod 600 /swapfile
  else
    dd if=/dev/zero of="$MOUNT_POINT/swapfile" bs=1M count="$size_mib" status=progress
    chmod 600 "$MOUNT_POINT/swapfile"
    arch-chroot "$MOUNT_POINT" mkswap /swapfile
  fi

  arch-chroot "$MOUNT_POINT" swapon /swapfile
  arch-chroot "$MOUNT_POINT" swapoff /swapfile
  printf '/swapfile none swap defaults 0 0\n' >> "$MOUNT_POINT/etc/fstab"
  success "Swap file configured: $SWAPFILE_SIZE"
}

swapfile_size_mib() {
  local raw_size="$1"
  local number=""
  local unit=""

  [[ "$raw_size" =~ ^([0-9]+)([GgMm]?)$ ]] || die "Invalid swap file size: $raw_size. Use 0, 4096M, or 4G."

  number="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"
  [[ "$number" != "0" ]] || die "Use 0 to skip swap, not as a swap file size."

  case "$unit" in
    G|g) printf '%s\n' "$((number * 1024))" ;;
    M|m|"") printf '%s\n' "$number" ;;
    *) die "Invalid swap file size: $raw_size" ;;
  esac
}

set_krub_default() {
  local file=$1 key=$2 value=$3
  if grep -Eq "^#?${key}=" "$file"; then
    sed -i -E "s/^#?${key}=.*/${key}=${value}/" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

disable_krub_bootnext_list() {
  local file=$1
  # grub-mkconfig does not export this extension's option to grub.d scripts.
  # Its helper reads the variable from the environment, so export it here.
  if grep -Eq '^#?[[:space:]]*(export[[:space:]]+)?GRUB_DISABLE_BOOTNEXT=' "$file"; then
    sed -i -E 's/^#?[[:space:]]*(export[[:space:]]+)?GRUB_DISABLE_BOOTNEXT=.*/export GRUB_DISABLE_BOOTNEXT=true/' "$file"
  else
    printf 'export GRUB_DISABLE_BOOTNEXT=true\n' >> "$file"
  fi
}

configure_krub_menu_policy() {
  local grub_defaults="$MOUNT_POINT/etc/default/grub"
  local firmware_script="$MOUNT_POINT/etc/grub.d/30_uefi-firmware"
  local bootnext_script="$MOUNT_POINT/etc/grub.d/31_efi_bootnext"

  [[ -f "$grub_defaults" && ! -L "$grub_defaults" ]] || die 'Missing or non-regular GRUB defaults; cannot enforce the selected krub menu policy.'
  ((BOOT_MENU_CHOICE_MADE == 1)) || die 'Boot Menu and Windows policy were not collected.'
  # Never run os-prober: it lists arbitrary disks. The installed BootNext
  # generator provides its own switch; do not alter the generator or NVRAM.
  set_krub_default "$grub_defaults" GRUB_DISABLE_OS_PROBER true
  disable_krub_bootnext_list "$grub_defaults"
  set_krub_default "$grub_defaults" GRUB_DISABLE_RECOVERY true
  set_krub_default "$grub_defaults" GRUB_DISABLE_SUBMENU false
  if [[ -e "$bootnext_script" || -L "$bootnext_script" ]]; then
    [[ -f "$bootnext_script" && ! -L "$bootnext_script" ]] \
      || die 'The installed BootNext generator is not a regular script; refusing to change it.'
    chmod a-x "$bootnext_script"  # Leave the packaged file intact; prevent the all-firmware list.
  fi
  [[ -f "$firmware_script" && ! -L "$firmware_script" && -x "$firmware_script" ]] \
    || die 'UEFI Firmware Settings GRUB script is missing or disabled; cannot build the requested menu.'
  info 'krub will contain Arch Linux, Advanced options and UEFI Firmware Settings, with optional Boot Menu when supported and Windows only if requested.'
}

write_boot_menu_krub_entry() {
  local entry_file="$MOUNT_POINT/etc/grub.d/40_kmos_boot_menu" line found=no firmware_output
  FIRMWARE_BOOT_MENU_ENABLED=no
  [[ "$FIRMWARE_BOOT_MENU_ID" =~ ^[[:xdigit:]]{4}$ ]] || return 0
  if [[ ! -f "$MOUNT_POINT$BOOTNEXT_MODULE" ]]; then
    warn 'Installed GRUB has no efibootnext module. Skipping optional Boot Menu; Arch and UEFI Firmware Settings remain available.'
    return 0
  fi
  firmware_output=$(efibootmgr) || { warn 'Could not recheck the optional Boot Menu; skipping it.'; return 0; }
  while IFS= read -r line; do
    if [[ "$line" =~ ^Boot${FIRMWARE_BOOT_MENU_ID}\*?[[:space:]]+Boot[[:space:]]Menu([[:space:]]|$) ]]; then
      found=yes
      break
    fi
  done <<< "$firmware_output"
  if [[ "$found" != yes ]]; then
    warn 'The optional Boot Menu firmware entry changed; skipping it without changing NVRAM.'
    return 0
  fi
  [[ ! -e "$entry_file" && ! -L "$entry_file" ]] || die 'Existing Boot Menu script preserved; refusing to replace it.'
  install -Dm0755 /dev/stdin "$entry_file" <<BOOT_MENU_SCRIPT
#!/bin/sh
cat <<'GRUB_ENTRY'
if [ "\$grub_platform" = "efi" ]; then
  menuentry 'Boot Menu (EFI BootNext)' --class boot --class os \$menuentry_id_option 'efi-bootnext-$FIRMWARE_BOOT_MENU_ID' {
    insmod efibootnext
    if bootnext $FIRMWARE_BOOT_MENU_ID; then
      reboot
    fi
  }
fi
GRUB_ENTRY
BOOT_MENU_SCRIPT
  FIRMWARE_BOOT_MENU_ENABLED=yes
}

write_windows_krub_entry() {
  local entry_file="$MOUNT_POINT/etc/grub.d/41_kmos_windows" device_id uuid
  [[ "$INCLUDE_WINDOWS" == yes ]] || return 0
  [[ "$WINDOWS_BOOT_UUID" =~ ^[[:xdigit:]-]{4,40}$ && "$WINDOWS_BOOT_PARTITION_ID" =~ ^[0-9]+:[0-9]+$ ]] \
    || die 'Windows EFI selection is incomplete; the existing GRUB menu was preserved.'
  device_id=$(lsblk -dnro MAJ:MIN "$WINDOWS_BOOT_PARTITION") || die 'Selected Windows EFI device is missing.'
  uuid=$(blkid -o value -s UUID "$WINDOWS_BOOT_PARTITION") || die 'Selected Windows EFI filesystem is missing.'
  [[ "$device_id" == "$WINDOWS_BOOT_PARTITION_ID" && "$uuid" == "$WINDOWS_BOOT_UUID" ]] \
    || die 'Windows EFI filesystem or device changed; the existing GRUB menu was preserved.'
  [[ ! -e "$entry_file" && ! -L "$entry_file" ]] || die 'Existing Windows menu script preserved; refusing to replace it.'
  install -Dm0755 /dev/stdin "$entry_file" <<WINDOWS_SCRIPT
#!/bin/sh
cat <<'GRUB_ENTRY'
menuentry 'Windows Boot Manager' --class windows --class os \$menuentry_id_option 'kmos-windows' {
  insmod part_gpt
  insmod fat
  insmod chain
  search --no-floppy --fs-uuid --set=root $WINDOWS_BOOT_UUID
  chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
GRUB_ENTRY
WINDOWS_SCRIPT
}

verify_krub_menu_policy() {
  local config=$1 expected_windows=0
  [[ -s "$config" ]] || die "krub did not generate a boot menu: $config"
  [[ "$INCLUDE_WINDOWS" != yes ]] || expected_windows=1
  if ! awk -v windows="$expected_windows" -v boot="$FIRMWARE_BOOT_MENU_ENABLED" -v bootid="$FIRMWARE_BOOT_MENU_ID" '
    /^### BEGIN \/etc\/grub.d\// { section=$0 }
    /^[[:space:]]*submenu[[:space:]]/ {
      if (section ~ /\/10_linux ###$/ && $0 ~ /^submenu '\''Advanced options for Arch Linux'\''/ && ! submenu_open) {
        advanced++
        submenu_open=1
      }
      else bad=1
    }
    section ~ /\/10_linux ###$/ && /^}/ { submenu_open=0 }
    /^[[:space:]]*menuentry[[:space:]]/ {
      if (section ~ /\/10_linux ###$/) {
        if ($0 ~ /^menuentry '\''Arch Linux'\''/ && ! submenu_open) arch++
        else if ($0 ~ /^[[:space:]]+menuentry '\''Arch Linux, with Linux / && submenu_open) { }
        else bad=1
      } else if (section ~ /\/30_uefi-firmware ###$/ && index($0, "menuentry '\''UEFI Firmware Settings'\''")) {
        firmware++
      } else if (section ~ /\/40_kmos_boot_menu ###$/ &&
                 index($0, "menuentry '\''Boot Menu (EFI BootNext)'\''") &&
                 index(tolower($0), "efi-bootnext-" tolower(bootid) "'\''")) {
        bootmenu++
      } else if (section ~ /\/41_kmos_windows ###$/ &&
                 index($0, "menuentry '\''Windows Boot Manager'\''")) {
        found_windows++
      } else bad=1
    }
    END {
      if (bad || arch != 1 || advanced != 1 || firmware != 1 || bootmenu != (boot == "yes") || found_windows != windows) {
        printf "Unexpected krub menu (Arch=%d, Advanced=%d, UEFI=%d, Boot Menu=%d; supported=%s, Windows=%d; requested=%d)\n", arch, advanced, firmware, bootmenu, boot, found_windows, windows > "/dev/stderr"
        exit 1
      }
    }
  ' "$config"; then
    die 'krub menu differs from Arch Linux, Advanced options, UEFI Firmware Settings, and the supported optional entries. Existing menu preserved.'
  fi
}

inspect_krub_menu() {
  local root=${1:-} config defaults
  config="$root/boot/grub/grub.cfg"
  defaults="$root/etc/default/grub"
  [[ -r "$config" ]] || die "Cannot read $config; no menu was changed."
  info 'Generated krub menu entries (the source script is shown for each entry):'
  awk '
    /^### BEGIN \/etc\/grub.d\// { source=$0 }
    /^[[:space:]]*(menuentry|submenu)[[:space:]]/ { print source " :: " $0 }
  ' "$config" >&2
  if [[ -r "$defaults" ]]; then
    info 'OS probing and recovery defaults:'
    grep -E '^#?GRUB_DISABLE_(OS_PROBER|RECOVERY|SUBMENU)=' "$defaults" >&2 || true
  fi
  if [[ -z "$root" ]] && command -v efibootmgr >/dev/null 2>&1; then
    info 'Firmware BootNext/BootOrder (separate from the krub menu):'
    efibootmgr 2>/dev/null | grep -E '^(BootNext|BootOrder|Boot[[:xdigit:]]{4}\*?)' >&2 \
      || warn 'Firmware entries could not be read; no firmware settings were changed.'
  fi
}

scan_windows_efi_loaders() (
  local name type fstype uuid device_id mount_dir
  mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/kmos-windows-efi.XXXXXXXX") || return 1
  trap 'if findmnt -rn --mountpoint "$mount_dir" >/dev/null 2>&1; then umount "$mount_dir"; fi; rmdir "$mount_dir"' EXIT
  while read -r name type fstype; do
    [[ "$type" == part && "$fstype" == vfat ]] || continue
    if mount -o ro,nosuid,nodev,noexec "$name" "$mount_dir" 2>/dev/null; then
      if [[ -f "$mount_dir/EFI/Microsoft/Boot/bootmgfw.efi" ]]; then
        uuid=$(blkid -o value -s UUID "$name" 2>/dev/null || true)
        device_id=$(lsblk -dnro MAJ:MIN "$name" 2>/dev/null || true)
        if [[ "$uuid" =~ ^[[:xdigit:]-]{4,40}$ && "$device_id" =~ ^[0-9]+:[0-9]+$ ]]; then
          printf '%s|%s|%s\n' "$name" "$uuid" "$device_id"
        fi
      fi
      umount "$mount_dir" || return 1
    fi
  done < <(lsblk -rpno NAME,TYPE,FSTYPE)
)

select_windows_efi_loader() {
  local candidates_output
  local -a candidates=()
  candidates_output=$(scan_windows_efi_loaders) || die 'Could not inspect Windows EFI files before formatting.'
  [[ -n "$candidates_output" ]] || die 'Windows was requested but no Windows EFI loader was found before formatting.'
  mapfile -t candidates <<< "$candidates_output"
  ((${#candidates[@]} == 1)) || die 'Multiple Windows EFI loaders were found. Refusing to guess which one to boot or format.'
  IFS='|' read -r WINDOWS_BOOT_PARTITION WINDOWS_BOOT_UUID WINDOWS_BOOT_PARTITION_ID <<< "${candidates[0]}"
  detail 'Windows EFI' "$WINDOWS_BOOT_PARTITION (reused, never formatted)"
}

select_firmware_boot_menu() {
  local line firmware_output
  local -a candidates=()
  FIRMWARE_BOOT_MENU_ID=""
  if ! command -v efibootmgr >/dev/null 2>&1; then
    warn 'No efibootmgr in the live ISO; optional Boot Menu will be skipped.'
    return 0
  fi
  firmware_output=$(efibootmgr) || { warn 'Could not read firmware Boot Menu; it will be skipped.'; return 0; }
  while IFS= read -r line; do
    if [[ "$line" =~ ^Boot([[:xdigit:]]{4})\*?[[:space:]]+Boot[[:space:]]Menu([[:space:]]|$) ]]; then
      candidates+=("${BASH_REMATCH[1]^^}")
    fi
  done <<< "$firmware_output"
  if ((${#candidates[@]} != 1)); then
    warn 'No unique firmware Boot Menu entry; optional Boot Menu will be skipped. No firmware entries were changed.'
    return 0
  fi
  FIRMWARE_BOOT_MENU_ID=${candidates[0]}
  detail 'Boot Menu' "Boot$FIRMWARE_BOOT_MENU_ID"
}

verify_krub_mounts() {
  findmnt -rn --mountpoint "$MOUNT_POINT" >/dev/null 2>&1 || die "$MOUNT_POINT is not mounted."
  findmnt -rn --mountpoint "$MOUNT_POINT/boot" >/dev/null 2>&1 || die "$MOUNT_POINT/boot is not mounted."

  findmnt "$MOUNT_POINT" >&2
  findmnt "$MOUNT_POINT/boot" >&2
}

install_krub_bootloader() {
  local config="$MOUNT_POINT/boot/grub/grub.cfg" staged backup generation_log
  verify_krub_mounts
  configure_krub_menu_policy
  write_boot_menu_krub_entry
  write_windows_krub_entry

  arch-chroot "$MOUNT_POINT" mkinitcpio -p linux
  arch-chroot "$MOUNT_POINT" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot \
    --bootloader-id="$KRUB_ID" \
    --boot-directory=/boot \
    --recheck
  staged=$(mktemp "$config.kmos.XXXXXXXX") || die 'Could not stage a new krub menu.'
  generation_log=$(mktemp "$config.kmos-log.XXXXXXXX") || die 'Could not stage the krub generation log.'
  if ! arch-chroot "$MOUNT_POINT" grub-mkconfig -o "/boot/grub/${staged##*/}" 2> "$generation_log"; then
    cat "$generation_log" >&2
    die "krub generation failed; the existing menu was preserved. Inspect $staged and $generation_log."
  fi
  if grep -Eq 'Warning: os-prober will be executed|Adding boot menu entry for EFI BootNext:' "$generation_log"; then
    die "An unapproved GRUB generator ran; the existing menu was preserved. Inspect $generation_log and $staged before rebooting."
  fi
  cat "$generation_log" >&2
  verify_krub_menu_policy "$staged"
  if [[ "$INCLUDE_WINDOWS" == yes ]] \
    && ! grep -Fq "search --no-floppy --fs-uuid --set=root $WINDOWS_BOOT_UUID" "$staged"; then
    die 'Windows EFI filesystem search is missing from the staged menu; the existing menu was preserved.'
  fi
  arch-chroot "$MOUNT_POINT" grub-script-check "/boot/grub/${staged##*/}" \
    || die "krub menu syntax check failed; the existing menu was preserved. Inspect $staged."
  if [[ -e "$config" || -L "$config" ]]; then
    [[ -f "$config" && ! -L "$config" ]] || die 'Existing krub menu is not a regular file; refusing to overwrite it.'
    backup=$(mktemp "$config.kmos-before.XXXXXXXX") || die 'Could not reserve a krub menu backup.'
    cp -p -- "$config" "$backup" || die "Could not back up the old krub menu to $backup."
    info "Old krub menu backed up at $backup"
  fi
  mv -- "$staged" "$config" || die "Could not activate the verified krub menu; staged copy: $staged"
  rm -f -- "$generation_log"

  success "krub bootloader installed."
}

update_target_system() {
  run_with_retry "$PACMAN_RETRIES" arch-chroot "$MOUNT_POINT" pacman --disable-download-timeout -Syyuu --noconfirm || die "Target update failed after ${PACMAN_RETRIES} attempts."
  success "Target system updated."
}

run_kde_installer() {
  local local_installer="$SCRIPT_DIR/desktop/kde/kmos-kde-install.sh"
  local fetched_installer="/tmp/kmos-kde-install.sh"

  if [[ -f "$local_installer" ]]; then
    kmos_KDE_PROFILE="$KDE_PROFILE" kmos_INSTALL_AUR="$INSTALL_KDE_AUR" kmos_AUR_HELPER="$AUR_HELPER" bash "$local_installer" --target "$MOUNT_POINT"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$KDE_INSTALLER_URL" -o "$fetched_installer" || die "Could not fetch KDE installer."
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$fetched_installer" "$KDE_INSTALLER_URL" || die "Could not fetch KDE installer."
  else
    die "KDE installer not found locally and neither curl nor wget is available."
  fi

  kmos_KDE_PROFILE="$KDE_PROFILE" kmos_INSTALL_AUR="$INSTALL_KDE_AUR" kmos_AUR_HELPER="$AUR_HELPER" bash "$fetched_installer" --target "$MOUNT_POINT"
}

offer_kde_desktop() {
  ((DESKTOP_CHOICE_MADE == 1)) || die 'Desktop/headless choice was not collected; refusing automatic KDE installation.'
  if [[ "$INSTALL_KDE" == yes ]]; then
    run_kde_installer
  elif [[ "$INSTALL_HEADLESS_AUR" == yes ]]; then
    bootstrap_aur_helper
  fi
}

unmount_target() {
  sync
  if findmnt -rn --mountpoint "$MOUNT_POINT" >/dev/null 2>&1; then
    umount -R "$MOUNT_POINT" || warn "$MOUNT_POINT could not be unmounted cleanly."
  fi
}

final_reboot() {
  final_success "Install complete. Rebooting."
  unmount_target
  sync

  if ! systemctl reboot -i >/dev/null 2>&1; then
    reboot -f >/dev/null 2>&1 || shutdown -r now >/dev/null 2>&1 || {
      if [[ -w /proc/sysrq-trigger ]]; then
        printf 'b' > /proc/sysrq-trigger
      fi
      die "Unable to reboot automatically."
    }
  fi
  exit 0
}

main() {
  init_ui
  if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
    (($# == 1)) || die 'Help does not accept additional arguments.'
    usage
    return
  fi
  if [[ "${1:-}" == inspect-krub ]]; then
    (($# == 1)) || die 'inspect-krub does not accept additional arguments.'
    inspect_krub_menu
    return
  fi
  if [[ "${1:-}" == repair-panel ]]; then
    (($# == 1)) || die 'repair-panel does not accept additional arguments.'
    require_root "$@"
    bash "$SCRIPT_DIR/desktop/kde/kmos-kde-post.sh" --target / --disable-panel-hooks
    return
  fi
  parse_args "$@"
  print_banner
  require_root "$@"
  require_tools

  advance_step "Verifying live environment"
  verify_boot_mode

  advance_step "Planning target disk"
  select_disk
  snapshot_target_disk
  choose_partition_mode

  advance_step "Collecting all installation choices"
  collect_system_config
  collect_desktop_config
  preflight_partitions
  verify_target_disk_snapshot
  confirm_install_plan
  verify_target_disk_snapshot

  advance_step "Formatting and mounting"
  format_and_mount

  advance_step "Setting live system time"
  setup_time

  advance_step "Installing base system"
  install_base_system

  advance_step "Configuring target system"
  configure_target_system

  advance_step "Updating target system"
  update_target_system

  advance_step "Installing krub bootloader"
  install_krub_bootloader

  offer_kde_desktop
  final_reboot
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
