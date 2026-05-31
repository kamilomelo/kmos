#!/bin/bash
# kmos Rocky Linux Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
WIFI_HELPER="$SCRIPT_DIR/tools/kmos-rockylinux-wifi-connect.sh"
STEP_INDEX=0
STEP_TOTAL=12
STATE_DIR="/var/lib/kmos/rockylinux"
REBOOT_MARKER="$STATE_DIR/reboot-required-after-update"
UPDATE_DONE_MARKER="$STATE_DIR/update-baseline-complete"
NVIDIA_REBOOT_MARKER="$STATE_DIR/reboot-required-after-nvidia"
NVIDIA_DONE_MARKER="$STATE_DIR/nvidia-open-complete"
STARSHIP_PRESET_DIR="$SCRIPT_DIR/../archlinux/assets/starship-presets"

UI_RESET=""
UI_BOLD=""
UI_DIM=""
UI_HEADER=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""

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
  printf '%bOK%b %s\n' "$UI_SUCCESS" "$UI_RESET" "$*" >&2
}

die() {
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

advance_step() {
  local label="$1"

  ((STEP_INDEX += 1))
  printf '\n%bStep %d/%d%b %s\n' "${UI_HEADER}${UI_BOLD}" "$STEP_INDEX" "$STEP_TOTAL" "$UI_RESET" "$label" >&2
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

ask_text() {
  local prompt="$1"
  local default="${2:-}"
  local answer=""

  read -r -p "$prompt${default:+ [$default]}: " answer
  if [[ -z "$answer" && -n "$default" ]]; then
    answer="$default"
  fi

  printf '%s\n' "$answer"
}

ask_password() {
  local prompt="$1"
  local password=""
  local confirm=""

  while true; do
    read -r -s -p "$prompt: " password
    printf '\n' >&2
    [[ -n "$password" ]] || continue
    read -r -s -p "Confirm password: " confirm
    printf '\n' >&2
    [[ "$password" == "$confirm" ]] && break
    warn "Passwords do not match."
  done

  printf '%s\n' "$password"
}

print_banner() {
  printf '\n' >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$(repeat_char "=" 24)" "$UI_RESET" >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "kmos Rocky Linux Install" "$UI_RESET" >&2
  printf '%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$(repeat_char "=" 24)" "$UI_RESET" >&2
  log "Initial Rocky Linux post-install scaffold for Rocky 10 minimal."
  log "This stage assumes Rocky is already installed and booted."
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Run this script as root."
}

require_tools() {
  local missing=()
  local tools=(dnf ping systemctl hostnamectl mkdir cat id useradd chpasswd usermod rpm cp curl)
  local t

  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done

  [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}

current_hostname() {
  hostnamectl --static 2>/dev/null | awk 'NR==1 { print $1 }'
}

configure_hostname() {
  local hostname=""
  local current=""

  advance_step "Set hostname"

  current="$(current_hostname)"
  if [[ -n "$current" && "$current" != "localhost" && "$current" != "localhost.localdomain" ]]; then
    success "Hostname is already set to: $current"
    return
  fi

  hostname="$(ask_text 'Enter the desired hostname' 'rocky')"
  [[ -n "$hostname" ]] || die "Hostname cannot be empty."

  hostnamectl set-hostname "$hostname"
  success "Hostname set to: $hostname"
}

detect_linux_id() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  printf '%s\n' "${ID:-}"
}

is_rocky() {
  [[ "$(detect_linux_id || true)" == "rocky" ]]
}

has_internet() {
  ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1
}

has_wifi_adapter() {
  local path=""

  for path in /sys/class/net/*; do
    [[ -e "$path" ]] || continue
    [[ -d "$path/wireless" ]] && return 0
  done

  return 1
}

has_wired_carrier() {
  local path=""
  local dev=""

  for path in /sys/class/net/*; do
    [[ -e "$path" ]] || continue
    dev="${path##*/}"
    [[ "$dev" == "lo" ]] && continue
    [[ -d "$path/wireless" ]] && continue
    if [[ -r "$path/carrier" ]] && [[ "$(cat "$path/carrier")" == "1" ]]; then
      return 0
    fi
  done

  return 1
}

has_wifi_stack() {
  rpm -q NetworkManager-wifi >/dev/null 2>&1 && rpm -q wpa_supplicant >/dev/null 2>&1
}

has_nvidia_gpu() {
  command -v lspci >/dev/null 2>&1 || return 1
  lspci | grep -Eiq 'VGA|3D' && lspci | grep -iq 'NVIDIA'
}

running_kernel_release() {
  uname -r
}

latest_installed_kernel_release() {
  rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core 2>/dev/null | sort -V | tail -n 1
}

require_running_latest_kernel() {
  local running_kernel=""
  local newest_kernel=""

  running_kernel="$(running_kernel_release)"
  newest_kernel="$(latest_installed_kernel_release)"

  [[ -n "$newest_kernel" ]] || return 0

  if [[ "$running_kernel" != "$newest_kernel" ]]; then
    die "A newer kernel is installed ($newest_kernel) but Rocky is still running $running_kernel. Reboot before continuing so DKMS/NVIDIA stays aligned with the running kernel."
  fi
}

secure_boot_enabled() {
  command -v mokutil >/dev/null 2>&1 || return 1
  mokutil --sb-state 2>/dev/null | grep -qi 'enabled'
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

ensure_network() {
  advance_step "Ensure network access"

  if has_internet; then
    success "Internet access is already available."
    return
  fi

  warn "No internet access detected."

  if has_wired_carrier; then
    die "A wired link is present, but internet is still unavailable. Fix the wired connection first."
  fi

  if [[ -x "$WIFI_HELPER" ]] && has_wifi_adapter; then
    if ask_yes_no "Run the Rocky Wi-Fi helper now?" "yes"; then
      bash "$WIFI_HELPER"
    fi
  fi

  has_internet || die "Internet is still unavailable. Connect Rocky to the network, then rerun kmos."
  success "Internet access confirmed."
}

prepare_wifi_support() {
  advance_step "Prepare Rocky Wi-Fi support"

  if ! has_wifi_adapter; then
    info "No Wi-Fi adapter detected. Skipping Rocky Wi-Fi preparation."
    return
  fi

  if has_wifi_stack; then
    success "Rocky Wi-Fi packages are already installed."
    return
  fi

  info "Installing Rocky Wi-Fi packages while internet is available."
  dnf -y --setopt=install_weak_deps=False install NetworkManager-wifi wpa_supplicant
  systemctl enable --now NetworkManager >/dev/null 2>&1 || true
  success "Rocky Wi-Fi support packages installed."
}

update_system_baseline() {
  local current_boot_id=""
  local recorded_boot_id=""

  advance_step "Update Rocky baseline"
  ensure_state_dir
  current_boot_id="$(cat /proc/sys/kernel/random/boot_id)"

  if [[ -f "$REBOOT_MARKER" ]]; then
    recorded_boot_id="$(cat "$REBOOT_MARKER")"
    if [[ "$current_boot_id" == "$recorded_boot_id" ]]; then
      die "A full system update already ran. Reboot Rocky before continuing."
    fi

    rm -f "$REBOOT_MARKER"
    touch "$UPDATE_DONE_MARKER"
    success "Reboot after the baseline update confirmed."
    return
  fi

  if [[ -f "$UPDATE_DONE_MARKER" ]]; then
    success "Baseline update already completed. Skipping."
    return
  fi

  info "Running full system update before any NVIDIA or workstation tooling."
  dnf -y upgrade --refresh
  printf '%s\n' "$current_boot_id" > "$REBOOT_MARKER"
  warn "Baseline update completed. Reboot Rocky now, then rerun kmos to continue."
  exit 0
}

configure_swapfile() {
  local swap_size=""

  advance_step "Configure swapfile"

  if swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/swapfile'; then
    success "/swapfile is already active."
    return
  fi

  if grep -Eq '^[^#]+\s+none\s+swap\s' /etc/fstab 2>/dev/null; then
    warn "A swap entry already exists in /etc/fstab. Leaving swap configuration unchanged."
    return
  fi

  if [[ -e /swapfile ]]; then
    warn "/swapfile already exists, but it is not active."
    if ask_yes_no "Activate the existing /swapfile and keep it in /etc/fstab?" "yes"; then
      chmod 600 /swapfile
      mkswap /swapfile >/dev/null
      swapon /swapfile
      grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
      success "Existing /swapfile activated and persisted."
      return
    fi
    warn "Skipping swapfile changes."
    return
  fi

  if ! ask_yes_no "Create a swapfile now?" "yes"; then
    warn "Skipping swapfile creation."
    return
  fi

  swap_size="$(ask_text 'Enter swapfile size in GiB' '8')"
  [[ "$swap_size" =~ ^[0-9]+$ ]] || die "Swapfile size must be an integer number of GiB."
  (( swap_size > 0 )) || die "Swapfile size must be greater than zero."

  dd if=/dev/zero of=/swapfile bs=1M count=$((swap_size * 1024)) status=progress
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
  success "Created ${swap_size} GiB swapfile at /swapfile."
}

enable_cli_repositories() {
  advance_step "Enable Rocky CLI repositories"

  rpm -q dnf-plugins-core >/dev/null 2>&1 || dnf -y --setopt=install_weak_deps=False install dnf-plugins-core
  rpm -q epel-release >/dev/null 2>&1 || dnf -y --setopt=install_weak_deps=False install epel-release
  dnf -y makecache
  success "EPEL is ready."
}

install_cli_tooling() {
  advance_step "Install Rocky CLI tooling"
  export PATH="/usr/local/bin:/root/.local/bin:$HOME/.local/bin:$PATH"

  if ! dnf -y --setopt=install_weak_deps=False install tar nano btop fastfetch; then
    warn "CLI tooling install failed without CRB. Enabling CRB and retrying."
    dnf config-manager --set-enabled crb
    dnf -y makecache
    dnf -y --setopt=install_weak_deps=False install tar nano btop fastfetch
  fi

  if ! command -v zoxide >/dev/null 2>&1; then
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    export PATH="/usr/local/bin:/root/.local/bin:$HOME/.local/bin:$PATH"
  fi

  if ! command -v starship >/dev/null 2>&1; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b /usr/local/bin
    export PATH="/usr/local/bin:/root/.local/bin:$HOME/.local/bin:$PATH"
  fi

  if [[ ! -x /usr/local/bin/zoxide ]]; then
    if [[ -x /root/.local/bin/zoxide ]]; then
      install -m 0755 /root/.local/bin/zoxide /usr/local/bin/zoxide
    elif [[ -x "$HOME/.local/bin/zoxide" ]]; then
      install -m 0755 "$HOME/.local/bin/zoxide" /usr/local/bin/zoxide
    fi
  fi

  if [[ ! -x /usr/local/bin/starship ]]; then
    if [[ -x /root/.local/bin/starship ]]; then
      install -m 0755 /root/.local/bin/starship /usr/local/bin/starship
    elif [[ -x "$HOME/.local/bin/starship" ]]; then
      install -m 0755 "$HOME/.local/bin/starship" /usr/local/bin/starship
    fi
  fi

  if ! command -v zoxide >/dev/null 2>&1; then
    die "zoxide installation did not produce a usable binary."
  fi

  if ! command -v starship >/dev/null 2>&1; then
    die "starship installation did not produce a usable binary."
  fi

  success "Rocky CLI tooling installed."
}

stage_shell_presets() {
  local target_dir="/opt/kmos/starship-presets"
  local user_bashrc=""
  local home_dir=""
  local bashrc_block=""
  local bashrc_marker_begin="# >>> kmos shell init >>>"
  local bashrc_marker_end="# <<< kmos shell init <<<"

  advance_step "Stage shell presets"

  [[ -d "$STARSHIP_PRESET_DIR" ]] || die "Missing starship presets: $STARSHIP_PRESET_DIR"

  mkdir -p "$target_dir"
  cp "$STARSHIP_PRESET_DIR"/*.toml "$target_dir"/

  bashrc_block=$(cat <<'EOF'

# >>> kmos shell init >>>
if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]]; then
  export STARSHIP_CONFIG=/opt/kmos/starship-presets/holow-light.toml
else
  export STARSHIP_CONFIG=/opt/kmos/starship-presets/tty-term.toml
fi
eval "$(starship init bash)"
eval "$(zoxide init bash)"
# <<< kmos shell init <<<
EOF
)

  rewrite_bashrc_block() {
    local target_file="$1"

    touch "$target_file"
    if grep -qF "$bashrc_marker_begin" "$target_file"; then
      awk -v begin="$bashrc_marker_begin" -v end="$bashrc_marker_end" '
        $0 == begin { skipping=1; next }
        $0 == end { skipping=0; next }
        skipping != 1 { print }
      ' "$target_file" > "${target_file}.kmos.tmp"
      mv "${target_file}.kmos.tmp" "$target_file"
    fi

    printf '%s\n' "$bashrc_block" >> "$target_file"
  }

  mkdir -p /etc/skel
  rewrite_bashrc_block /etc/skel/.bashrc

  for home_dir in /root /home/*; do
    [[ -d "$home_dir" ]] || continue
    user_bashrc="$home_dir/.bashrc"
    rewrite_bashrc_block "$user_bashrc"
  done

  if [[ -f "$HOME/.bashrc" ]]; then
    set +u
    BASHRCSOURCED="" source "$HOME/.bashrc" >/dev/null 2>&1 || true
    set -u
  fi

  success "Starship presets and bashrc hooks staged."
  warn "Open a new shell or run: exec bash -l"
}

install_nvidia_open() {
  local current_boot_id=""
  local recorded_boot_id=""
  local gpu_lines=""
  local cuda_repo="/etc/yum.repos.d/cuda-rhel10.repo"

  advance_step "Install Rocky NVIDIA open driver"
  ensure_state_dir
  dnf -y --setopt=install_weak_deps=False install dnf-plugins-core pciutils kernel-devel-matched kernel-headers mokutil
  require_running_latest_kernel

  if ! has_nvidia_gpu; then
    info "No NVIDIA GPU detected. Skipping Rocky NVIDIA setup."
    return
  fi

  gpu_lines="$(lspci | grep -i 'NVIDIA' || true)"
  info "Detected NVIDIA hardware:"
  while IFS= read -r line; do
    [[ -n "$line" ]] && log "  - $line"
  done <<< "$gpu_lines"
  info "kmos assumes Rocky 10 plus Turing-or-newer NVIDIA hardware here and uses nvidia-open."

  current_boot_id="$(cat /proc/sys/kernel/random/boot_id)"

  if [[ -f "$NVIDIA_REBOOT_MARKER" ]]; then
    recorded_boot_id="$(cat "$NVIDIA_REBOOT_MARKER")"
    if [[ "$current_boot_id" == "$recorded_boot_id" ]]; then
      die "The NVIDIA driver install already ran. Reboot Rocky before continuing."
    fi

    rm -f "$NVIDIA_REBOOT_MARKER"

    if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
      die "Reboot after NVIDIA install was detected, but nvidia-smi is still not working. Check Secure Boot enrollment or driver load state before continuing."
    fi

    touch "$NVIDIA_DONE_MARKER"
    success "NVIDIA reboot confirmed and nvidia-smi is working."
  fi

  if [[ -f "$NVIDIA_DONE_MARKER" ]]; then
    success "Rocky NVIDIA driver is already installed and verified."
  elif command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    touch "$NVIDIA_DONE_MARKER"
    success "NVIDIA driver is already active."
  else
    [[ -f "$cuda_repo" ]] || dnf config-manager --add-repo "https://developer.download.nvidia.com/compute/cuda/repos/rhel10/$(uname -m)/cuda-rhel10.repo"
    dnf clean expire-cache
    dnf -y --setopt=install_weak_deps=False install nvidia-open

    if secure_boot_enabled; then
      warn "UEFI Secure Boot is enabled."
      if [[ -f /var/lib/dkms/mok.pub ]]; then
        if ask_yes_no "Import the DKMS MOK key now so the NVIDIA modules can be enrolled on reboot?" "yes"; then
          mokutil --import /var/lib/dkms/mok.pub
          warn "At the next reboot, enroll the MOK key in the firmware screen or the NVIDIA modules may not load."
        else
          warn "Skipping MOK import. If Secure Boot stays enabled, the NVIDIA modules may fail to load after reboot."
        fi
      else
        warn "Secure Boot is enabled, but /var/lib/dkms/mok.pub is missing. If the driver fails to load after reboot, inspect the DKMS signing state."
      fi
    fi

    printf '%s\n' "$current_boot_id" > "$NVIDIA_REBOOT_MARKER"
    warn "NVIDIA packages installed. Reboot Rocky now, then rerun kmos to verify nvidia-smi and continue."
    exit 0
  fi

  success "Rocky NVIDIA driver is already installed and verified."
}

configure_additional_users() {
  local username=""
  local password=""

  advance_step "Configure additional users"

  if ! ask_yes_no "Add another local user now?" "no"; then
    info "Skipping additional user creation."
    return
  fi

  while true; do
    username="$(ask_text 'Enter the username')"
    id "$username" >/dev/null 2>&1 && die "User already exists: $username"
    password="$(ask_password 'Enter password')"

    useradd -m "$username"
    printf '%s:%s\n' "$username" "$password" | chpasswd

    if ask_yes_no "Grant sudo access to $username?" "yes"; then
      usermod -aG wheel "$username"
      success "Created user $username with sudo access."
    else
      success "Created user $username."
    fi

    ask_yes_no "Add another local user?" "no" || break
  done
}

describe_scope() {
  advance_step "Describe current Rocky scope"
  info "Rocky support is now scaffolded for the post-install minimal workflow."
  log "Current scope:"
  log "  - assumes Rocky 10 minimal is already installed"
  log "  - assumes /boot/efi, /boot, and / only"
  log "  - sets the hostname before network and Wi-Fi setup"
  log "  - creates swap as a swapfile instead of a swap partition"
  log "  - forces a full update and reboot boundary before NVIDIA or tooling"
  log "  - prepares Wi-Fi support on Rocky minimal while ethernet is available"
  log "  - enables EPEL first and only falls back to CRB if needed"
  log "  - installs tar, nano, btop, fastfetch, starship, and zoxide"
  log "  - installs Rocky 10 NVIDIA drivers with the official nvidia-open path when NVIDIA hardware is present"
  log "  - verifies the NVIDIA stage with nvidia-smi"
  log "  - stages the 4 kmos starship presets"
  log "  - brings up Wi-Fi first when ethernet is not available"
  log "  - can already create additional local users"
}

next_steps() {
  advance_step "Next Rocky work"
  log "Next implementation step:"
  log "  - continue the headless Rocky workflow"
  log "  - extend Rocky support with future non-desktop stages as needed"
}

main() {
  init_ui
  print_banner
  require_root
  require_tools
  is_rocky || die "This installer only supports Rocky Linux."
  configure_hostname
  ensure_network
  prepare_wifi_support
  configure_swapfile
  update_system_baseline
  enable_cli_repositories
  install_cli_tooling
  stage_shell_presets
  install_nvidia_open
  configure_additional_users
  describe_scope
  next_steps
}

main "$@"
