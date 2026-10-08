#!/usr/bin/env bash
# Read-only inventory before handing networking from iwd/dhcpcd to NetworkManager.
set -euo pipefail
SYS_NET_ROOT=/sys/class/net
IWD_CONF=/etc/iwd/main.conf

os_id() {
  # shellcheck disable=SC1091 # Standard local OS identity file.
  . /etc/os-release
  printf '%s\n' "${ID:-}"
}

kde_ready() { [[ -r /usr/share/kmos/kde-profile ]]; }

usage() {
  cat <<'EOF'
Usage: ./platforms/archlinux/tools/kmos-network-migration.sh --plan

Read-only: checks physical Ethernet/Wi-Fi interfaces and the active network
managers. Does not show saved Wi-Fi credentials or change connections. There
is no migration command yet. The goal is NetworkManager-controlled networking
in KDE instead of directly using iwctl/iwd plus dhcpcd. Ethernet/local console
is a fallback for the one-time handoff, not the networking mode we are testing.
EOF
}

state() {
  local value
  value=$(systemctl "$1" "$2" 2>/dev/null) || :
  printf '%s\n' "${value:-unknown}"
}

interface_kind() {
  [[ -d "$SYS_NET_ROOT/$1/wireless" ]] && { printf 'Wi-Fi\n'; return; }
  [[ -r "$SYS_NET_ROOT/$1/type" && $(cat "$SYS_NET_ROOT/$1/type") == 1 ]] && {
    printf 'Ethernet\n'; return;
  }
  printf 'other\n'
}

ipv4_present() {
  [[ -n "$(ip -o -4 addr show dev "$1" scope global 2>/dev/null)" ]]
}

ethernet_default_route() {
  [[ -n "$(ip -4 route show default dev "$1" 2>/dev/null)" ]]
}

ssh_interface() {
  local peer="${SSH_CONNECTION%% *}" route
  [[ -n "${SSH_CONNECTION:-}" ]] || return 1
  route=$(ip route get "$peer" 2>/dev/null) || return 1
  printf '%s\n' "$route" | awk '{for (i=1; i<NF; i++) if ($i == "dev") {print $(i+1); exit}}'
}

plan() {
  local iface kind carrier dhcp wifi=0 wired=0 ssh_dev
  [[ -r /etc/os-release ]] || { printf 'Cannot identify this OS.\n' >&2; return 1; }
  [[ $(os_id) == arch && $(uname -m) == x86_64 ]] || {
    printf 'Only installed Arch Linux x86_64 is supported.\n' >&2; return 1;
  }
  kde_ready || {
    printf 'KMOS KDE upgrade marker not found; refusing migration planning.\n' >&2; return 1;
  }
  printf 'NetworkManager binary: '
  if command -v nmcli >/dev/null 2>&1; then printf 'present\n'; else printf 'missing\n'; fi
  printf 'Services (active / enabled):\n'
  local service
  for service in NetworkManager.service iwd.service dhcpcd.service sshd.service systemd-resolved.service; do
    printf '  %-25s %s / %s\n' "$service" "$(state is-active "$service")" "$(state is-enabled "$service")"
  done
  printf 'iwd built-in IP configuration: '
  if [[ -r "$IWD_CONF" ]] && grep -Eq '^[[:space:]]*EnableNetworkConfiguration[[:space:]]*=[[:space:]]*true' "$IWD_CONF"; then
    printf 'enabled (must be coordinated with NetworkManager)\n'
  else
    printf 'not explicitly enabled\n'
  fi
  printf 'Physical interfaces (no addresses, SSIDs or passwords shown):\n'
  for iface in "$SYS_NET_ROOT"/*; do
    [[ -e "$iface/device" ]] || continue
    iface="${iface##*/}"
    kind=$(interface_kind "$iface")
    carrier=unknown
    [[ ! -r "$SYS_NET_ROOT/$iface/carrier" ]] || carrier=$(cat "$SYS_NET_ROOT/$iface/carrier" 2>/dev/null) || :
    dhcp=no
    if ipv4_present "$iface"; then dhcp=yes; fi
    printf '  %s: %s, carrier=%s, IPv4=%s' "$iface" "$kind" "$carrier" "$dhcp"
    if [[ "$kind" == Ethernet ]]; then
      ((wired+=1))
      if ethernet_default_route "$iface"; then printf ', default route=yes'; else printf ', default route=no'; fi
    elif [[ "$kind" == Wi-Fi ]]; then
      ((wifi+=1))
    fi
    printf '\n'
  done
  ssh_dev=$(ssh_interface || true)
  if [[ -n "$ssh_dev" ]]; then printf 'Current SSH route interface: %s\n' "$ssh_dev"; fi
  if ((wifi == 0 || wired == 0)); then
    printf 'No Wi-Fi or wired fallback detected; do not attempt a remote handoff.\n'
  else
    printf 'Check wired connectivity separately before any handoff; carrier/IP alone do not prove internet access.\n'
  fi
  printf 'Plan complete: nothing changed. NetworkManager handoff is not available yet.\n'
}

main() {
  case "${1:-}" in
    --help|-h) (($# == 1)) || { usage >&2; return 2; }; usage ;;
    --plan) (($# == 1)) || { usage >&2; return 2; }; plan ;;
    *) usage >&2; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
