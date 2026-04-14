#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
WORK_DIR="$SCRIPT_DIR/work"
ARCH_BASE_URL="${ARCH_BASE_URL:-https://theswissbay.ch/archlinux/iso/latest}"
ARCH_BASE_URL_FALLBACKS="${ARCH_BASE_URL_FALLBACKS:-https://mirror.puzzle.ch/archlinux/iso/latest https://mirror.init7.net/archlinux/iso/latest https://mirror.arch-linux.ch/archlinux/iso/latest https://mirror.metanet.ch/archlinux/iso/latest https://geo.mirror.pkgbuild.com/iso/latest}"
ROCKY_BASE_URL="${ROCKY_BASE_URL:-https://mirror.init7.net/rockylinux}"
ROCKY_BASE_URL_FALLBACKS="${ROCKY_BASE_URL_FALLBACKS:-https://mirror.puzzle.ch/rockylinux https://rocky-linux-europe-west6.production.gcp.mirrors.ctrliq.cloud/pub/rocky https://dl.rockylinux.org/pub/rocky https://download.rockylinux.org/pub/rocky}"
ARCH="x86_64"
ARCH_BASE_URLS=()
ROCKY_BASE_URLS=()

SCRIPT_DEV="$(findmnt -n -o SOURCE --target "$SCRIPT_DIR" 2>/dev/null || true)"
SCRIPT_DISK=""
if [[ -n "$SCRIPT_DEV" ]]; then
  SCRIPT_DISK="/dev/$(lsblk -no pkname "$SCRIPT_DEV" 2>/dev/null || true)"
fi

ROOT_DEV="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_DISK=""
if [[ -n "$ROOT_DEV" ]]; then
  ROOT_DISK="/dev/$(lsblk -no pkname "$ROOT_DEV" 2>/dev/null || true)"
fi

log() {
  printf '%s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

normalize_url() {
  printf '%s\n' "${1%/}"
}

init_base_urls() {
  local fallback
  ARCH_BASE_URLS=("$(normalize_url "$ARCH_BASE_URL")")
  ROCKY_BASE_URLS=("$(normalize_url "$ROCKY_BASE_URL")")

  for fallback in $ARCH_BASE_URL_FALLBACKS; do
    ARCH_BASE_URLS+=("$(normalize_url "$fallback")")
  done

  for fallback in $ROCKY_BASE_URL_FALLBACKS; do
    ROCKY_BASE_URLS+=("$(normalize_url "$fallback")")
  done
}

resolve_base_url() {
  local -n mirrors_ref="$1"
  local mirror

  for mirror in "${mirrors_ref[@]}"; do
    [[ -n "$mirror" ]] || continue
    if curl -fsSL --connect-timeout 10 --max-time 20 -o /dev/null "$mirror/"; then
      printf '%s\n' "$mirror"
      return 0
    fi
    log "Mirror unavailable: $mirror"
  done

  return 1
}

require_tools() {
  local missing=()
  local tools=(curl awk sed grep sort lsblk findmnt sha256sum b2sum dd sudo)
  local t
  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}"
  fi
}

ensure_workdir() {
  mkdir -p "$WORK_DIR"
}

prompt_menu() {
  local prompt="$1"
  shift
  local options=("$@")
  local i=1
  local choice

  log "$prompt"
  for opt in "${options[@]}"; do
    printf '  %d) %s\n' "$i" "$opt" >&2
    ((i++))
  done

  while true; do
    read -r -p "Select [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      printf '%s\n' "$choice"
      return 0
    fi
    log "Invalid selection."
  done
}

confirm_yes_no() {
  local prompt="$1"
  local default_no="${2:-1}"
  local answer

  while true; do
    if [[ "$default_no" == "1" ]]; then
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-N}"
    else
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-Y}"
    fi

    case "$answer" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) log "Please answer yes or no." ;;
    esac
  done
}

fetch_latest_arch_iso_name() {
  local base_url="$1"
  local index
  index="$(curl -fsSL "$base_url/")" || return 1

  local latest
  latest="$(printf '%s\n' "$index" \
    | grep -Eo 'archlinux-x86_64-[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.iso' \
    | sort -u \
    | tail -n1 || true)"

  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest"
  else
    printf '%s\n' "archlinux-x86_64.iso"
  fi
}

download_file() {
  local url="$1"
  local out="$2"

  curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$out" "$url"
}

verify_arch_download() {
  local iso="$1"
  local sha_file="$2"
  local b2_file="$3"

  grep " $iso$" "$sha_file" | sha256sum -c - >/dev/null
  grep " $iso$" "$b2_file" | b2sum -c - >/dev/null
}

prepare_arch() {
  local arch_base_url
  arch_base_url="$(resolve_base_url ARCH_BASE_URLS)" || die "No reachable Arch mirror found"
  log "Using Arch mirror: $arch_base_url"

  local iso
  iso="$(fetch_latest_arch_iso_name "$arch_base_url")" || die "Cannot read Arch latest index"

  local sha_file="sha256sums.txt"
  local b2_file="b2sums.txt"
  local arch_dir="$WORK_DIR/arch"

  mkdir -p "$arch_dir"
  cd "$arch_dir"

  local needs_download=0
  [[ -f "$iso" && -f "$sha_file" && -f "$b2_file" ]] || needs_download=1

  if (( needs_download == 0 )); then
    if verify_arch_download "$iso" "$sha_file" "$b2_file"; then
      log "Arch ISO already present and verified."
      printf '%s\n' "$arch_dir/$iso"
      return 0
    fi
    log "Existing Arch files failed verification. Re-downloading."
  else
    log "Downloading Arch ISO and checksums."
  fi

  rm -f "$iso" "$sha_file" "$b2_file"
  download_file "$arch_base_url/$iso" "$iso"
  download_file "$arch_base_url/$sha_file" "$sha_file"
  download_file "$arch_base_url/$b2_file" "$b2_file"

  verify_arch_download "$iso" "$sha_file" "$b2_file" || die "Arch checksum verification failed"
  log "Arch ISO verified."
  printf '%s\n' "$arch_dir/$iso"
}

fetch_latest_rocky_major() {
  local base_url="$1"
  local index
  index="$(curl -fsSL "$base_url/")" || return 1

  printf '%s\n' "$index" \
    | grep -Eo 'href="[0-9]+/"' \
    | grep -Eo '[0-9]+' \
    | sort -n \
    | tail -n1
}

verify_rocky_download() {
  local iso_name="$1"
  local checksum_file="$2"
  local expected actual

  expected="$(
    awk -v iso="$iso_name" '
      $0 ~ /^[[:xdigit:]]{64}[[:space:]]+\*?.+/ {
        hash=$1
        file=$2
        sub(/^\*/, "", file)
        if (file == iso) {
          print tolower(hash)
          exit
        }
      }
      $0 ~ /^SHA256 \(.+\) = [[:xdigit:]]{64}$/ {
        line=$0
        sub(/^SHA256 \(/, "", line)
        sub(/\) = [[:xdigit:]]{64}$/, "", line)
        hash=$NF
        if (line == iso) {
          print tolower(hash)
          exit
        }
      }
    ' "$checksum_file"
  )"

  [[ -n "$expected" ]] || return 1
  actual="$(sha256sum "$iso_name" | awk '{print tolower($1)}')"
  [[ "$actual" == "$expected" ]]
}

prepare_rocky() {
  local rocky_base_url
  rocky_base_url="$(resolve_base_url ROCKY_BASE_URLS)" || die "No reachable Rocky mirror found"
  log "Using Rocky mirror: $rocky_base_url"

  local major
  major="$(fetch_latest_rocky_major "$rocky_base_url")"
  [[ -n "$major" ]] || die "Cannot determine latest Rocky major version"

  local rocky_variant_choice
  rocky_variant_choice="$(prompt_menu "Choose Rocky image" "Minimal" "KDE Live")"

  local iso_dir
  local iso_name
  local checksum_name=""

  if [[ "$rocky_variant_choice" == "1" ]]; then
    iso_dir="$rocky_base_url/$major/isos/$ARCH"
    iso_name="Rocky-${major}-latest-${ARCH}-minimal.iso"
  else
    iso_dir="$rocky_base_url/$major/live/$ARCH"
    iso_name="Rocky-${major}-KDE-${ARCH}-latest.iso"
  fi
  checksum_name="${iso_name}.CHECKSUM"

  local rocky_dir="$WORK_DIR/rocky"
  mkdir -p "$rocky_dir"
  cd "$rocky_dir"

  local needs_download=0
  [[ -f "$iso_name" && -f "$checksum_name" ]] || needs_download=1

  if (( needs_download == 0 )); then
    if verify_rocky_download "$iso_name" "$checksum_name"; then
      log "Rocky ISO already present and verified."
      printf '%s\n' "$rocky_dir/$iso_name"
      return 0
    fi
    log "Existing Rocky files failed verification. Re-downloading."
  else
    log "Downloading Rocky ISO and checksum."
  fi

  rm -f "$iso_name" "$checksum_name"
  download_file "$iso_dir/$iso_name" "$iso_name" || die "Failed downloading $iso_name"
  download_file "$iso_dir/$checksum_name" "$checksum_name" || die "Failed downloading CHECKSUM"

  verify_rocky_download "$iso_name" "$checksum_name" || die "Rocky checksum verification failed"
  log "Rocky ISO verified."
  printf '%s\n' "$rocky_dir/$iso_name"
}

list_candidate_usb_disks() {
  lsblk -dn -o NAME,TYPE,TRAN,RM \
    | awk '$2=="disk" && ($3=="usb" || $4=="1") {print "/dev/"$1}'
}

print_disks() {
  log "Available disks:"
  lsblk -d -o NAME,SIZE,TRAN,RM,MODEL >&2
}

validate_target_disk() {
  local dev="$1"
  [[ -b "$dev" ]] || return 1
  [[ "$(lsblk -dn -o TYPE "$dev" 2>/dev/null)" == "disk" ]] || return 1
  return 0
}

select_target_disk() {
  local target=""
  local candidates=()

  mapfile -t candidates < <(list_candidate_usb_disks)

  log "Insert USB drive now, then press Enter."
  read -r

  mapfile -t candidates < <(list_candidate_usb_disks)

  if [[ ${#candidates[@]} -eq 1 ]]; then
    target="${candidates[0]}"
    log "Auto-detected USB device: $target"
    read -r -p "Use this device? [y/N]: " use_auto
    if [[ ! "$use_auto" =~ ^[Yy]$ ]]; then
      target=""
    fi
  fi

  if [[ -z "$target" ]]; then
    print_disks
    read -r -p "Enter target disk (example: /dev/sdb): " target
  fi

  validate_target_disk "$target" || die "Invalid disk: $target"

  if [[ -n "$SCRIPT_DISK" && "$target" == "$SCRIPT_DISK" ]]; then
    die "Refusing to write to the script host disk: $target"
  fi

  if [[ -n "$ROOT_DISK" && "$target" == "$ROOT_DISK" ]]; then
    read -r -p "Selected disk seems to hold current OS ($target). Type 'I understand' to continue: " ack
    [[ "$ack" == "I understand" ]] || die "Cancelled"
  fi

  printf '%s\n' "$target"
}

unmount_target_partitions() {
  local disk="$1"
  local part mp

  while read -r part mp; do
    if [[ -n "$mp" ]]; then
      sudo umount "/dev/$part" || die "Failed to unmount /dev/$part"
    fi
  done < <(lsblk -nr -o NAME,MOUNTPOINT "$disk")
}

flash_iso() {
  local iso_path="$1"
  local target_disk="$2"

  [[ -f "$iso_path" ]] || die "ISO not found: $iso_path"

  log ""
  log "ISO:    $iso_path"
  log "Target: $target_disk"
  confirm_yes_no "Proceed with flashing?" 1 || die "Cancelled"

  unmount_target_partitions "$target_disk"

  log "Writing image..."
  sudo dd if="$iso_path" of="$target_disk" bs=4M status=progress oflag=sync conv=fsync
  sync
  log "Done. USB should be ready."
}

cleanup_workdir_prompt() {
  if confirm_yes_no "Delete work directory ($WORK_DIR)?" 1; then
    rm -rf -- "$WORK_DIR"
    log "Work directory deleted."
  else
    log "Work directory kept."
  fi
}

prepare_iso_for_os() {
  local os_key="$1"
  case "$os_key" in
    arch) prepare_arch ;;
    rocky) prepare_rocky ;;
    *) die "Unsupported OS provider: $os_key" ;;
  esac
}

main() {
  require_tools
  init_base_urls
  ensure_workdir

  log "KMOS USB Flasher"
  log "Work directory: $WORK_DIR"
  log ""

  local os_choice=""
  log "Choose operating system"
  printf '  1) Arch Linux (default)\n' >&2
  printf '  2) Rocky Linux\n' >&2
  while true; do
    read -r -p "Select [1-2] (default: 1): " os_choice
    os_choice="${os_choice:-1}"
    if [[ "$os_choice" =~ ^[12]$ ]]; then
      break
    fi
    log "Invalid selection."
  done

  local os_key
  if [[ "$os_choice" == "1" ]]; then
    os_key="arch"
  else
    os_key="rocky"
  fi

  local iso_path
  iso_path="$(prepare_iso_for_os "$os_key")"

  local target_disk
  target_disk="$(select_target_disk)"

  flash_iso "$iso_path" "$target_disk"
  cleanup_workdir_prompt
}

main "$@"
