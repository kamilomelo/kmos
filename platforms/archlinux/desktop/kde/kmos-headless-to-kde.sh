#!/usr/bin/env bash
# Read-only preflight for adding KDE to an installed KMOS headless system.
# Installation is deliberately unavailable until the live-system path is safe.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --preflight

Read-only: reports KMOS base, KDE, network and SSH state. Does not require
root, install packages, change services, partition disks or modify files.
No KDE upgrade operation is available yet.
EOF
}

os_id() {
  # shellcheck disable=SC1091 # Standard local OS identity file.
  . /etc/os-release
  printf '%s\n' "${ID:-}"
}

package_installed() {
  command -v pacman >/dev/null 2>&1 && pacman -Qq "$1" >/dev/null 2>&1
}

service_state() {
  local state
  state=$(systemctl is-active "$1" 2>/dev/null) || :
  printf '%s\n' "${state:-unknown}"
}

service_enabled() {
  local state
  state=$(systemctl is-enabled "$1" 2>/dev/null) || :
  printf '%s\n' "${state:-unknown}"
}

headless_marker_present() {
  [[ -r /usr/share/kmos/metapackages/nodesktop/PKGBUILD ]]
}

kde_profile_present() {
  [[ -e /usr/share/kmos/kde-profile ]]
}

preflight() {
  local id iface transport pkg service
  [[ -r /etc/os-release ]] || { printf 'Cannot identify this operating system.\n' >&2; return 1; }
  id=$(os_id)
  [[ "$id" == arch ]] || { printf 'Only installed Arch Linux x86_64 is supported (found %s).\n' "$id" >&2; return 1; }
  [[ $(uname -m) == x86_64 ]] || { printf 'Only x86_64 is supported.\n' >&2; return 1; }
  headless_marker_present || {
    printf 'KMOS headless base marker not found; do not use the upgrade path on this system.\n' >&2
    return 1
  }

  printf 'KMOS headless base: present\n'
  if package_installed plasma-desktop || package_installed sddm || kde_profile_present; then
    printf 'KDE/SDDM already present: yes (upgrade path must not overwrite it)\n'
  else
    printf 'KDE/SDDM already present: no\n'
  fi

  printf 'Default-route interface: '
  iface=$(ip -o -4 route show default 2>/dev/null | awk '{for (i=1; i<NF; i++) if ($i == "dev") {print $(i+1); exit}}') || :
  if [[ -z "$iface" ]]; then
    printf 'not detected\n'
  else
    transport=Ethernet-or-other
    [[ -d "/sys/class/net/$iface/wireless" ]] && transport=Wi-Fi
    printf '%s (%s)\n' "$iface" "$transport"
  fi

  for pkg in networkmanager iwd dhcpcd wpa_supplicant openssh impala; do
    if package_installed "$pkg"; then
      printf 'Package %-16s installed\n' "$pkg"
    else
      printf 'Package %-16s absent\n' "$pkg"
    fi
  done
  for service in NetworkManager.service iwd.service dhcpcd.service sshd.service sddm.service; do
    printf 'Service %-23s active=%s enabled=%s\n' "$service" \
      "$(service_state "$service")" "$(service_enabled "$service")"
  done
  if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]]; then
    printf 'This shell is over SSH: yes (do not interrupt the active network)\n'
  else
    printf 'This shell is over SSH: no / not detected\n'
  fi
  printf 'Preflight complete: nothing was changed. KDE upgrade is not enabled yet.\n'
}

main() {
  case "${1:---help}" in
    --help|-h) [[ $# == 1 || $# == 0 ]] || { usage >&2; return 2; }; usage ;;
    --preflight) [[ $# == 1 ]] || { usage >&2; return 2; }; preflight ;;
    *) usage >&2; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
