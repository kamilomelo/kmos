#!/bin/bash
# KMOS Arch Linux Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
MOUNT_POINT="/mnt"
WIFI_HANDOFF_DIR="/run/kmos/wifi"
MINIMAL_METAPACKAGE_DIR="$SCRIPT_DIR/metapackages/minimal"
KDE_INSTALLER_URL="https://raw.githubusercontent.com/kamilomelo/KMOS/main/kmos-kde-install.sh"
STARSHIP_PRESET_DIR="$SCRIPT_DIR/assets/starship-presets"
STARSHIP_PRESET_MODE="holow"
STARSHIP_PRESET_THEME="light"
DEBUG_MODE="${KMOS_DEBUG:-0}"
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
ROOT_FILESYSTEM="xfs"
TIMEZONE="Europe/Zurich"
LOCALE="en_US.UTF-8"
KEYMAP=""
HOSTNAME=""
SWAPFILE_SIZE="4G"
KRUB_ID="krub"
ENABLE_OS_PROBER="no"
ENABLE_WIFI_AFTER_BOOT="no"
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
  wpa_supplicant
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

  if [[ "${TERM:-}" == "linux" || "${ASCII_UI:-${KMOS_ASCII_UI:-0}}" == "1" ]]; then
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

load_minimal_metapackage() {
  local pkgbuild="$MINIMAL_METAPACKAGE_DIR/PKGBUILD"
  local package=""

  if [[ ! -r "$pkgbuild" ]]; then
    warn "Minimal metapackage not found: $pkgbuild"
    return 0
  fi

  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    add_package "$package"
  done < <(source "$pkgbuild"; printf '%s\n' "${depends[@]}")

  success "Minimal metapackage loaded."
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
  local tools=(arch-chroot awk blkid cat cfdisk chmod dd df dirname findmnt fsck.fat genfstab grep install ln lspci lsblk mkdir mkfs.fat mount pacstrap partprobe rm rmdir sed sort timedatectl touch udevadm umount)
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
  while true; do
    info "Current partition layout:"
    lsblk -fp "$TARGET_DISK" >&2

    if ask_yes_no "Open cfdisk for this disk before selecting partitions?" "no"; then
      cfdisk "$TARGET_DISK"
      partprobe "$TARGET_DISK" || true
      udevadm settle || true
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

detect_other_os_candidate() {
  local name=""
  local type=""
  local fstype=""
  local parttype=""

  while read -r name type fstype parttype; do
    [[ "$type" == "part" ]] || continue
    [[ "$name" == "$ROOT_PARTITION" || "$name" == "$BOOT_PARTITION" ]] && continue
    case "$fstype" in
      ntfs|vfat) return 0 ;;
    esac
    [[ "$parttype" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]] && return 0
  done < <(lsblk -rpno NAME,TYPE,FSTYPE,PARTTYPE "$TARGET_DISK")

  return 1
}

collect_krub_config() {
  local package=""

  for package in "${KRUB_PACKAGES[@]}"; do
    add_package "$package"
  done

  if detect_other_os_candidate; then
    detail "Other OS" "candidate detected"
  fi

  if ask_yes_no "Add Windows/other OS entries to krub?" "no"; then
    ENABLE_OS_PROBER="yes"
    add_package "os-prober"
    add_package "ntfs-3g"
  else
    ENABLE_OS_PROBER="no"
  fi
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
    warn "Wi-Fi handoff data is incomplete. Run kmos-wifi-connect.sh again if you need Wi-Fi after reboot."
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
  load_minimal_metapackage
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

confirm_install_plan() {
  local extra_user_summary=""
  local extra_sudo_summary=""
  local idx=0

  printf '\n' >&2
  info "Install plan:"
  detail "Disk" "$TARGET_DISK"
  detail "Boot" "$BOOT_PARTITION -> /boot"
  detail "Root" "$ROOT_PARTITION -> /"
  detail "Root fs" "$ROOT_FILESYSTEM"
  detail "Bootloader" "$KRUB_ID"
  detail "OS detection" "$ENABLE_OS_PROBER"
  detail "Graphics" "$GRAPHICS_SUMMARY"
  detail "GPU pkgs" "$GRAPHICS_PACKAGE_SUMMARY"
  detail "Microcode" "$MICROCODE_SUMMARY"
  detail "Metapackage" "kmos-minimal"
  detail "SSH" "enabled"
  detail "Starship" "$STARSHIP_PRESET_MODE/$STARSHIP_PRESET_THEME"
  if [[ "$ENABLE_WIFI_AFTER_BOOT" == "yes" ]]; then
    detail "Wi-Fi boot" "$WIFI_ADAPTER -> $WIFI_SSID"
  else
    detail "Wi-Fi boot" "not configured"
  fi
  detail "Timezone" "$TIMEZONE"
  detail "Locale" "$LOCALE"
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

  printf '\n%b%s%b\n' "${UI_DANGER}${UI_BOLD}" "Destructive action" "$UI_RESET" >&2
  log "The root partition will be formatted. Data on $ROOT_PARTITION will be erased."
  log "The boot partition will be formatted as FAT32. Data on $BOOT_PARTITION will be erased."
  read -r -p "Type FORMAT to continue: " confirm
  [[ "$confirm" == "FORMAT" ]] || die "Install cancelled."
}

format_and_mount() {
  local detected_root_fstype=""

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

  run_cmd mkfs.fat -F 32 "$BOOT_PARTITION"
  run_cmd partprobe "$TARGET_DISK" || true
  udevadm settle || true

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
  cleanup_boot_artifacts
  info "Installing minimal base packages"
  pacstrap -K "$MOUNT_POINT" "${BASE_PACKAGES[@]}"
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
    sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 9/' "$pacman_conf"
  elif grep -q '^ParallelDownloads = ' "$pacman_conf"; then
    sed -i 's/^ParallelDownloads = .*/ParallelDownloads = 9/' "$pacman_conf"
  else
    printf '\nParallelDownloads = 9\n' >> "$pacman_conf"
  fi

  if ! grep -q '^ILoveCandy$' "$pacman_conf"; then
    sed -i '/^ParallelDownloads = 9$/a ILoveCandy' "$pacman_conf"
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

install_kmos_assets() {
  local preset=""

  if [[ -r "$MINIMAL_METAPACKAGE_DIR/PKGBUILD" ]]; then
    install -Dm0644 "$MINIMAL_METAPACKAGE_DIR/PKGBUILD" "$MOUNT_POINT/usr/share/kmos/metapackages/minimal/PKGBUILD"
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
  local preset="$STARSHIP_PRESET_DIR/$STARSHIP_PRESET_MODE-$STARSHIP_PRESET_THEME.toml"
  local bashrc="$MOUNT_POINT/etc/bash.bashrc"

  if [[ ! -r "$preset" ]]; then
    warn "Starship preset not found: $preset"
    return 0
  fi

  install -Dm0644 "$preset" "$MOUNT_POINT/etc/starship.toml"
  install -Dm0644 /dev/stdin "$MOUNT_POINT/etc/profile.d/10-kmos-starship.sh" <<'STARSHIP_PROFILE'
export STARSHIP_CONFIG=/etc/starship.toml
STARSHIP_PROFILE

  touch "$bashrc"
  if ! grep -q 'starship init bash' "$bashrc"; then
    cat >> "$bashrc" <<'BASHRC'

# KMOS Starship prompt
if [[ $- == *i* ]] && command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
BASHRC
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

  [[ "$ENABLE_WIFI_AFTER_BOOT" == "yes" ]] || return 0

  install -d -m 0755 "$MOUNT_POINT/etc/wpa_supplicant" "$MOUNT_POINT/etc/systemd/network"

  {
    printf 'ctrl_interface=DIR=/run/wpa_supplicant GROUP=wheel\n'
    printf 'update_config=0\n'
    printf '\n'
    printf 'network={\n'
    printf '    ssid=%s\n' "$(wpa_quote "$WIFI_SSID")"
    if [[ "$WIFI_HIDDEN" == "1" ]]; then
      printf '    scan_ssid=1\n'
    fi
    printf '    psk=%s\n' "$(wpa_quote "$WIFI_PASSWORD")"
    printf '    key_mgmt=WPA-PSK\n'
    printf '}\n'
  } > "$wpa_config"

  chmod 600 "$wpa_config"

  if [[ -n "$WIFI_MAC" ]]; then
    install -Dm0644 /dev/stdin "$link_config" <<WIFI_LINK
[Match]
MACAddress=$WIFI_MAC

[Link]
Name=$WIFI_ADAPTER
WIFI_LINK
  fi

  if ! arch-chroot "$MOUNT_POINT" systemctl enable "wpa_supplicant@$WIFI_ADAPTER.service"; then
    warn "Could not enable wpa_supplicant@$WIFI_ADAPTER.service. The base install will continue."
    return 0
  fi
  if ! arch-chroot "$MOUNT_POINT" systemctl enable "dhcpcd@$WIFI_ADAPTER.service"; then
    warn "Could not enable dhcpcd@$WIFI_ADAPTER.service. The base install will continue."
    return 0
  fi
  rm -f "$WIFI_HANDOFF_DIR/adapter" "$WIFI_HANDOFF_DIR/ssid" "$WIFI_HANDOFF_DIR/password" "$WIFI_HANDOFF_DIR/hidden"
  rmdir "$WIFI_HANDOFF_DIR" 2>/dev/null || true
  success "Wi-Fi configured for first boot."
}

configure_wired_network_after_boot() {
  [[ "$ENABLE_WIFI_AFTER_BOOT" == "yes" ]] && return 0

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

enable_krub_os_detection() {
  local grub_defaults="$MOUNT_POINT/etc/default/grub"

  [[ "$ENABLE_OS_PROBER" == "yes" ]] || return 0

  if [[ ! -f "$grub_defaults" ]]; then
    warn "Could not find /etc/default/grub to enable OS detection."
    return 0
  fi

  if grep -q '^#\?GRUB_DISABLE_OS_PROBER=' "$grub_defaults"; then
    sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$grub_defaults"
  else
    printf '\nGRUB_DISABLE_OS_PROBER=false\n' >> "$grub_defaults"
  fi

  success "krub OS detection enabled."
}

find_windows_boot_partition() {
  local name=""
  local type=""
  local fstype=""
  local tmp_mount="/tmp/kmos-windows-efi"

  if [[ -f "$MOUNT_POINT/boot/EFI/Microsoft/Boot/bootmgfw.efi" ]]; then
    printf '%s\n' "$BOOT_PARTITION"
    return 0
  fi

  mkdir -p "$tmp_mount"
  if findmnt -rn --mountpoint "$tmp_mount" >/dev/null 2>&1; then
    umount "$tmp_mount" || die "$tmp_mount is already mounted and could not be unmounted."
  fi

  while read -r name type fstype; do
    [[ "$type" == "part" && "$fstype" == "vfat" ]] || continue
    [[ "$name" == "$BOOT_PARTITION" ]] && continue

    if mount -o ro "$name" "$tmp_mount" 2>/dev/null; then
      if [[ -f "$tmp_mount/EFI/Microsoft/Boot/bootmgfw.efi" ]]; then
        umount "$tmp_mount"
        rmdir "$tmp_mount" 2>/dev/null || true
        printf '%s\n' "$name"
        return 0
      fi
      umount "$tmp_mount"
    fi
  done < <(lsblk -rpno NAME,TYPE,FSTYPE "$TARGET_DISK")

  rmdir "$tmp_mount" 2>/dev/null || true
  return 1
}

write_windows_krub_entry() {
  local windows_partition=""
  local windows_uuid=""
  local entry_file="$MOUNT_POINT/etc/grub.d/41_windows"

  [[ "$ENABLE_OS_PROBER" == "yes" ]] || return 0

  windows_partition="$(find_windows_boot_partition || true)"
  if [[ -z "$windows_partition" ]]; then
    warn "No Windows Boot Manager was found on the EFI partitions."
    return 0
  fi

  windows_uuid="$(blkid -o value -s UUID "$windows_partition" 2>/dev/null || true)"
  if [[ -z "$windows_uuid" ]]; then
    warn "Could not read the EFI filesystem UUID for $windows_partition."
    return 0
  fi

  install -Dm0755 /dev/stdin "$entry_file" <<WINDOWS_ENTRY
#!/bin/sh
cat <<'GRUB_ENTRY'
menuentry "Windows Boot Manager" {
    insmod part_gpt
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root $windows_uuid
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
GRUB_ENTRY
WINDOWS_ENTRY

  success "Windows Boot Manager entry prepared for krub."
}

verify_krub_mounts() {
  findmnt -rn --mountpoint "$MOUNT_POINT" >/dev/null 2>&1 || die "$MOUNT_POINT is not mounted."
  findmnt -rn --mountpoint "$MOUNT_POINT/boot" >/dev/null 2>&1 || die "$MOUNT_POINT/boot is not mounted."

  findmnt "$MOUNT_POINT" >&2
  findmnt "$MOUNT_POINT/boot" >&2
}

install_krub_bootloader() {
  verify_krub_mounts
  enable_krub_os_detection
  write_windows_krub_entry

  arch-chroot "$MOUNT_POINT" mkinitcpio -p linux
  arch-chroot "$MOUNT_POINT" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot \
    --bootloader-id="$KRUB_ID" \
    --boot-directory=/boot \
    --recheck
  arch-chroot "$MOUNT_POINT" grub-mkconfig -o /boot/grub/grub.cfg
  [[ -s "$MOUNT_POINT/boot/grub/grub.cfg" ]] || die "krub did not generate /boot/grub/grub.cfg."
  grep -q '^[[:space:]]*menuentry ' "$MOUNT_POINT/boot/grub/grub.cfg" || die "krub config has no bootable menu entries."
  if [[ "$ENABLE_OS_PROBER" == "yes" ]] && ! grep -qi 'windows\|microsoft' "$MOUNT_POINT/boot/grub/grub.cfg"; then
    warn "krub did not find a Windows entry. BitLocker, Windows fast startup, or the selected EFI partition may still need attention."
  fi

  success "krub bootloader installed."
}

update_target_system() {
  arch-chroot "$MOUNT_POINT" pacman -Syyuu --noconfirm
  success "Target system updated."
}

run_kde_installer() {
  local local_installer="$SCRIPT_DIR/kmos-kde-install.sh"
  local fetched_installer="/tmp/kmos-kde-install.sh"

  if [[ -f "$local_installer" ]]; then
    bash "$local_installer" --target "$MOUNT_POINT"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$KDE_INSTALLER_URL" -o "$fetched_installer" || die "Could not fetch KDE installer."
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$fetched_installer" "$KDE_INSTALLER_URL" || die "Could not fetch KDE installer."
  else
    die "KDE installer not found locally and neither curl nor wget is available."
  fi

  bash "$fetched_installer" --target "$MOUNT_POINT"
}

offer_kde_desktop() {
  printf '\n' >&2
  info "You have a minimal install of Arch Linux."
  if ask_yes_no "Do you want to install KDE desktop?" "no"; then
    run_kde_installer
  fi
}

unmount_target() {
  sync
  if findmnt -rn --mountpoint "$MOUNT_POINT" >/dev/null 2>&1; then
    umount -R "$MOUNT_POINT" || warn "$MOUNT_POINT could not be unmounted cleanly."
  fi
}

offer_power_action() {
  local choice=""

  printf '\n' >&2
  info "What now?"
  log "  1) Reboot"
  log "  2) Shutdown"
  log "  3) Return to shell"

  while true; do
    read -r -p "Select [1-3] (default: 1): " choice
    choice="${choice:-1}"
    case "$choice" in
      1)
        final_success "Install complete. Rebooting."
        unmount_target
        reboot
        return 0
        ;;
      2)
        final_success "Install complete. Shutting down."
        unmount_target
        shutdown -h now
        return 0
        ;;
      3)
        final_success "Install complete. Returning to shell."
        return 0
        ;;
      *)
        warn "Invalid selection."
        ;;
    esac
  done
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

  advance_step "Updating target system"
  update_target_system

  advance_step "Installing krub bootloader"
  install_krub_bootloader

  offer_kde_desktop
  offer_power_action
}

main "$@"
