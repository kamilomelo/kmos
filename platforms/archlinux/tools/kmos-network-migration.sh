#!/usr/bin/env bash
# Optional, local-console handoff from iwd/dhcpcd to NetworkManager.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SYS_NET_ROOT=/sys/class/net
IWD_CONF=/etc/iwd/main.conf
NM_CONF=/etc/NetworkManager/conf.d/90-kmos-iwd-backend.conf
MIGRATION_MARKER=/run/kmos-nm-migration.in-progress
MIGRATION_DONE=/var/lib/kmos/nm-handoff.done
STAGED_MARKER=/var/lib/kmos/nm-handoff.staged
BOOT_SCRIPT=/usr/local/lib/kmos/kmos-network-migration.sh
BOOT_UNIT=/etc/systemd/system/kmos-nm-boot-check.service
BOOT_UNIT_NAME=kmos-nm-boot-check.service
WIRED_IFACE= WIFI_IFACE= ROLLBACK_ARMED=no

os_id() {
  # shellcheck disable=SC1091 # Standard local OS identity file.
  . /etc/os-release
  printf '%s\n' "${ID:-}"
}

kde_ready() { [[ -r /usr/share/kmos/kde-profile ]]; }

usage() {
  cat <<'EOF'
Usage: ./platforms/archlinux/tools/kmos-network-migration.sh --plan
       ./platforms/archlinux/tools/kmos-network-migration.sh --stage-reboot
       ./platforms/archlinux/tools/kmos-network-migration.sh --cancel-stage
       ./platforms/archlinux/tools/kmos-network-migration.sh --apply
       ./platforms/archlinux/tools/kmos-network-migration.sh --rollback

--plan is read-only and shows no saved Wi-Fi credentials. --apply requires a
LOCAL keyboard and screen, connected Ethernet, and interactive confirmation.
It may interrupt networking. It uses iwd only as NetworkManager's Wi-Fi radio
backend: NetworkManager, not iwctl/dhcpcd, controls connections and IP setup.
It preserves saved iwd profiles, tests Ethernet and Wi-Fi under NetworkManager,
then changes boot services. --rollback restores the prior service setup after
an interrupted OR completed handoff; NetworkManager profiles are preserved.
Never run --apply or --rollback over SSH.
--stage-reboot is a SEPARATE SSH-safe path: it stages boot-service changes but
does NOT interrupt current connections. Reboot manually; a one-time boot check
restores iwd/dhcpcd if NetworkManager cannot bring Ethernet online. Wi-Fi can
then be added manually in KDE. --cancel-stage undoes staging before reboot.
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
  local peer route
  [[ -n "${SSH_CONNECTION:-}" ]] || return 1
  peer="${SSH_CONNECTION%% *}"
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
  if [[ -f "$STAGED_MARKER" && ! -L "$STAGED_MARKER" ]]; then
    printf 'KMOS handoff: staged for the next reboot / boot validation\n'
  elif [[ -f "$MIGRATION_DONE" && ! -L "$MIGRATION_DONE" ]]; then
    printf 'KMOS handoff: boot handoff completed; verify Wi-Fi in KDE\n'
  else
    printf 'KMOS handoff: not staged\n'
  fi
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
  printf 'Plan complete: nothing changed. Use --apply only at the local console.\n'
}

local_console() {
  [[ -t 0 && -t 1 && -z "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]] || {
    printf 'Local interactive console required; SSH is unsafe for the handoff.\n' >&2
    return 1
  }
  if [[ -n "${XDG_SESSION_ID:-}" ]] && command -v loginctl >/dev/null 2>&1; then
    [[ $(loginctl show-session "$XDG_SESSION_ID" --property=Remote --value 2>/dev/null || true) != yes ]] || {
      printf 'A remote login session cannot perform the handoff.\n' >&2; return 1;
    }
  fi
}

require_root() {
  (( EUID == 0 )) && return 0
  command -v sudo >/dev/null || { printf 'sudo is required; no changes made.\n' >&2; return 1; }
  exec sudo -- "$SCRIPT_DIR/kmos-network-migration.sh" "$@"
}

select_interfaces() {
  local entry iface kind
  WIRED_IFACE= WIFI_IFACE=
  for entry in "$SYS_NET_ROOT"/*; do
    [[ -e "$entry/device" ]] || continue
    iface="${entry##*/}"
    kind=$(interface_kind "$iface")
    if [[ "$kind" == Ethernet && -r "$entry/carrier" && $(cat "$entry/carrier") == 1 ]] &&
        ipv4_present "$iface" && ethernet_default_route "$iface"; then
      [[ -z "$WIRED_IFACE" ]] || { printf 'Multiple eligible wired fallbacks; review manually.\n' >&2; return 1; }
      WIRED_IFACE="$iface"
    elif [[ "$kind" == Wi-Fi ]] && ipv4_present "$iface"; then
      [[ -z "$WIFI_IFACE" ]] || { printf 'Multiple active Wi-Fi interfaces; review manually.\n' >&2; return 1; }
      WIFI_IFACE="$iface"
    fi
  done
  [[ -n "$WIRED_IFACE" && -n "$WIFI_IFACE" ]] || {
    printf 'Need one working wired interface and one active Wi-Fi interface.\n' >&2; return 1;
  }
}

ready_for_handoff() {
  [[ $(os_id) == arch && $(uname -m) == x86_64 ]] && kde_ready || {
    printf 'Only an installed KMOS KDE Arch x86_64 system is supported.\n' >&2; return 1;
  }
  command -v nmcli >/dev/null && command -v curl >/dev/null && command -v iwctl >/dev/null || {
    printf 'Existing NetworkManager, curl and iwd tools are required. No packages were installed.\n' >&2; return 1;
  }
  [[ $(state is-active NetworkManager.service) != active && $(state is-enabled NetworkManager.service) != enabled &&
     $(state is-active dhcpcd.service) == active && $(state is-enabled dhcpcd.service) == enabled &&
     $(state is-active iwd.service) == active && $(state is-enabled iwd.service) == enabled ]] || {
    printf 'Service state differs from the expected headless configuration; refusing.\n' >&2; return 1;
  }
  [[ ! -e "$NM_CONF" && ! -L "$NM_CONF" && ! -e "$MIGRATION_MARKER" && ! -L "$MIGRATION_MARKER" &&
     ! -e "$MIGRATION_DONE" && ! -L "$MIGRATION_DONE" && ! -e "$STAGED_MARKER" && ! -L "$STAGED_MARKER" &&
     ! -L "${NM_CONF%/*}" &&
     ! -L "${MIGRATION_DONE%/*}" ]] || {
    printf 'KMOS migration config or marker already exists; inspect before retrying.\n' >&2; return 1;
  }
  if [[ -r "$IWD_CONF" ]] && grep -Eq '^[[:space:]]*EnableNetworkConfiguration[[:space:]]*=[[:space:]]*true' "$IWD_CONF"; then
    printf 'iwd built-in IP configuration is enabled; review it before migrating.\n' >&2; return 1
  fi
  local config
  for config in /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d/*.conf; do
    [[ -r "$config" ]] || continue
    if grep -Eq '^[[:space:]]*wifi\.backend[[:space:]]*=' "$config"; then
      printf 'An existing NetworkManager Wi-Fi backend is configured in %s; review before migrating.\n' "$config" >&2
      return 1
    fi
  done
  select_interfaces || return 1
  local unit
  for unit in "dhcpcd@$WIFI_IFACE.service" "dhcpcd@$WIRED_IFACE.service" \
    "wpa_supplicant@$WIFI_IFACE.service"; do
    if [[ $(state is-active "$unit") == active ]]; then
      printf 'Additional network manager %s is active; review before migrating.\n' "$unit" >&2
      return 1
    fi
  done
}

check_internet_on() {
  curl -4 -fsS --interface "$1" --connect-timeout 5 --max-time 12 -o /dev/null https://archlinux.org/
}

nm_connected() {
  local connection
  connection=$(nmcli -g GENERAL.STATE device show "$1" 2>/dev/null) || return 1
  [[ "$connection" == 100* ]] && ipv4_present "$1" && check_internet_on "$1"
}

wait_for_wired() {
  local attempt
  for attempt in {1..12}; do
    if nm_connected "$WIRED_IFACE"; then return 0; fi
    sleep 2
  done
  printf 'NetworkManager did not bring up wired internet.\n' >&2
  return 1
}

write_backend_config() {
  install -Dm0644 /dev/stdin "$NM_CONF" <<'EOF'
[device]
wifi.backend=iwd
wifi.iwd.autoconnect=false
EOF
}

config_is_ours() {
  [[ -f "$NM_CONF" && ! -L "$NM_CONF" ]] && cmp -s "$NM_CONF" <(printf '[device]\nwifi.backend=iwd\nwifi.iwd.autoconnect=false\n')
}

rollback() {
  [[ "$ROLLBACK_ARMED" == yes || -f "$MIGRATION_MARKER" || -f "$MIGRATION_DONE" || -f "$STAGED_MARKER" ]] || return 0
  printf 'Restoring the prior network services. Keep the cable attached.\n' >&2
  local failed=0
  systemctl stop NetworkManager.service || failed=1
  systemctl disable NetworkManager.service || failed=1
  systemctl enable iwd.service dhcpcd.service || failed=1
  systemctl start iwd.service dhcpcd.service || failed=1
  if config_is_ours; then rm -f -- "$NM_CONF"; fi
  if [[ $(state is-active iwd.service) != active || $(state is-active dhcpcd.service) != active ]]; then failed=1; fi
  if ((failed == 0)); then
    cleanup_boot_guard || failed=1
    if ((failed == 0)); then rm -f -- "$MIGRATION_MARKER" "$MIGRATION_DONE" "$STAGED_MARKER" || failed=1; fi
  fi
  ROLLBACK_ARMED=no
  if ((failed != 0)); then
    printf 'Rollback incomplete; marker retained. Check services from the local console.\n' >&2
    return 1
  fi
  printf 'Rollback attempted. Check wired and Wi-Fi status locally before relying on SSH.\n' >&2
}

write_boot_unit() {
  install -Dm0644 /dev/stdin "$BOOT_UNIT" <<'EOF'
[Unit]
Description=KMOS one-time NetworkManager Ethernet check and fallback
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/kmos/kmos-network-migration.sh --boot-check
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF
}

cleanup_boot_guard() {
  systemctl disable "$BOOT_UNIT_NAME" >/dev/null 2>&1 || :
  # These paths were refused if they existed before staging.
  [[ ! -L "$BOOT_UNIT" && ! -L "$BOOT_SCRIPT" ]] || return 1
  if [[ -f "$BOOT_UNIT" ]]; then
    grep -Fxq 'ExecStart=/usr/local/lib/kmos/kmos-network-migration.sh --boot-check' "$BOOT_UNIT" || return 1
  fi
  if [[ -f "$BOOT_SCRIPT" ]]; then
    grep -Fxq '# Optional, local-console handoff from iwd/dhcpcd to NetworkManager.' "$BOOT_SCRIPT" || return 1
  fi
  rm -f -- "$BOOT_UNIT" "$BOOT_SCRIPT"
  systemctl daemon-reload || :
}

confirm_staging() {
  local answer
  printf 'Stage NetworkManager for the NEXT boot? Current SSH/networking stays active.\n' >&2
  printf 'Ethernet %s must be available after reboot. Type STAGE NETWORK: ' "$WIRED_IFACE" >&2
  read -r answer </dev/tty || return 1
  [[ "$answer" == 'STAGE NETWORK' ]]
}

stage_reboot() {
  ready_for_handoff || return 1
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    [[ $(ssh_interface) == "$WIRED_IFACE" ]] || {
      printf 'SSH must currently be routed over the wired interface.\n' >&2; return 1;
    }
  fi
  check_internet_on "$WIRED_IFACE" || {
    printf 'Wired internet unavailable; boot migration not staged.\n' >&2; return 1;
  }
  require_root --stage-reboot || return 1
  ready_for_handoff || return 1
  check_internet_on "$WIRED_IFACE" || return 1
  [[ ! -e "$BOOT_UNIT" && ! -L "$BOOT_UNIT" && ! -e "$BOOT_SCRIPT" && ! -L "$BOOT_SCRIPT" &&
     ! -L "${BOOT_SCRIPT%/*}" && ! -L "${BOOT_UNIT%/*}" && ! -L "${STAGED_MARKER%/*}" ]] || {
    printf 'A boot-check unit/script already exists; review it before staging.\n' >&2; return 1;
  }
  confirm_staging || { printf 'Cancelled without changes.\n' >&2; return 1; }
  install -Dm0600 /dev/stdin "$STAGED_MARKER" <<< "$WIRED_IFACE" || return 1
  ROLLBACK_ARMED=yes
  trap 'rollback' EXIT
  trap 'exit 130' INT TERM
  install -Dm0755 "$SCRIPT_DIR/kmos-network-migration.sh" "$BOOT_SCRIPT" || return 1
  write_boot_unit || return 1
  systemctl daemon-reload || return 1
  systemctl enable "$BOOT_UNIT_NAME" || return 1
  write_backend_config || return 1
  systemctl enable NetworkManager.service || return 1
  systemctl disable dhcpcd.service iwd.service || return 1
  [[ $(state is-active dhcpcd.service) == active && $(state is-active iwd.service) == active &&
     $(state is-active NetworkManager.service) != active ]] || {
    printf 'Unexpected live service change; restoring the old setup.\n' >&2; return 1;
  }
  ROLLBACK_ARMED=no
  trap - EXIT INT TERM
  printf 'Staged for reboot. Current SSH and iwd/dhcpcd connections were not stopped.\n'
  printf 'After reboot, SSH via Ethernet should return under NetworkManager.\n'
  printf 'If wired NetworkManager cannot connect, the boot check restores iwd/dhcpcd.\n'
  printf 'Connect Wi-Fi in KDE manually after reboot; old iwd profiles were preserved.\n'
}

boot_check() {
  local wired attempt
  require_boot_root || return 1
  [[ -f "$STAGED_MARKER" && ! -L "$STAGED_MARKER" ]] || return 0
  wired=$(cat "$STAGED_MARKER") || return 1
  [[ "$wired" =~ ^[a-zA-Z0-9_.:-]+$ && -e "$SYS_NET_ROOT/$wired/device" &&
     $(interface_kind "$wired") == Ethernet ]] || {
    printf 'Invalid staged Ethernet interface; restoring prior services.\n' >&2
    rollback
    return 1
  }
  for attempt in {1..8}; do
    if nm_connected "$wired"; then
      if ! install -Dm0600 /dev/stdin "$MIGRATION_DONE" <<'EOF'
KMOS NetworkManager reboot handoff; Wi-Fi requires a user-selected NM connection.
EOF
      then
        rollback
        return 1
      fi
      if ! cleanup_boot_guard; then
        rollback
        return 1
      fi
      rm -f -- "$STAGED_MARKER" || return 1
      printf 'NetworkManager Ethernet verified. Configure Wi-Fi with KDE when ready.\n'
      return 0
    fi
    sleep 3
  done
  printf 'NetworkManager Ethernet failed; restoring iwd/dhcpcd for this and future boots.\n' >&2
  rollback
  return 1
}

require_boot_root() { ((EUID == 0)); }

cancel_stage() {
  local answer
  [[ -f "$STAGED_MARKER" && ! -L "$STAGED_MARKER" ]] || {
    printf 'No pending reboot migration found.\n' >&2; return 1;
  }
  [[ $(state is-active dhcpcd.service) == active && $(state is-active iwd.service) == active &&
     $(state is-active NetworkManager.service) != active ]] || {
    printf 'This appears to be after reboot; use the local console or boot fallback instead.\n' >&2; return 1;
  }
  require_root --cancel-stage || return 1
  printf 'Type CANCEL STAGE to restore the original next-boot settings: ' >&2
  read -r answer </dev/tty || return 1
  [[ "$answer" == 'CANCEL STAGE' ]] || return 1
  rollback
}

confirm_handoff() {
  local response
  printf 'Ethernet: %s; Wi-Fi: %s. DHCP and SSH may disconnect temporarily.\n' "$WIRED_IFACE" "$WIFI_IFACE" >&2
  printf 'Use the local keyboard/screen. Type MIGRATE NETWORK to continue: ' >&2
  read -r response </dev/tty || return 1
  [[ "$response" == 'MIGRATE NETWORK' ]]
}

confirm_wifi() {
  local response
  printf '\nEthernet now works through NetworkManager. Keep the cable attached.\n' >&2
  printf 'Use KDE’s network menu to connect a Wi-Fi network under NetworkManager.\n' >&2
  printf 'Enter its password in KDE, NOT in this script. Type VERIFY WIFI when connected: ' >&2
  read -r response </dev/tty || return 1
  [[ "$response" == 'VERIFY WIFI' ]] || return 1
  nm_connected "$WIFI_IFACE" || { printf 'NetworkManager Wi-Fi internet not verified.\n' >&2; return 1; }
}

apply_handoff() {
  local_console || return 1
  ready_for_handoff || return 1
  printf 'Testing wired internet through %s before changing any service...\n' "$WIRED_IFACE"
  check_internet_on "$WIRED_IFACE" || {
    printf 'Wired internet test failed; no services changed.\n' >&2; return 1;
  }
  confirm_handoff || { printf 'Cancelled without changes.\n' >&2; return 1; }
  require_root --apply || return 1
  # Recheck after sudo: the wired fallback and service states must still match.
  ready_for_handoff || return 1
  check_internet_on "$WIRED_IFACE" || return 1
  printf 'In progress: do not reboot until Ethernet and Wi-Fi have both been verified.\n' > "$MIGRATION_MARKER" || return 1
  ROLLBACK_ARMED=yes
  trap 'rollback' EXIT
  trap 'exit 130' INT TERM
  write_backend_config || return 1
  systemctl stop dhcpcd.service || return 1
  iwctl station "$WIFI_IFACE" disconnect || return 1
  systemctl start NetworkManager.service || return 1
  wait_for_wired || return 1
  confirm_wifi || return 1
  systemctl enable NetworkManager.service || return 1
  systemctl disable dhcpcd.service || return 1
  # iwd remains running as NM's radio backend, but NM starts it on future boots.
  systemctl disable iwd.service || return 1
  install -Dm0600 /dev/stdin "$MIGRATION_DONE" <<'EOF' || return 1
KMOS NetworkManager handoff; no credentials stored. --rollback is available locally.
EOF
  rm -f -- "$MIGRATION_MARKER" || return 1
  ROLLBACK_ARMED=no
  trap - EXIT INT TERM
  printf 'NetworkManager now controls Ethernet and Wi-Fi. Do not use iwctl to manage connections.\n'
  printf 'Unplug Ethernet only after confirming KDE Wi-Fi remains online at the local console.\n'
}

manual_rollback() {
  local response
  local_console || return 1
  [[ ( -f "$MIGRATION_MARKER" && ! -L "$MIGRATION_MARKER" ) ||
     ( -f "$MIGRATION_DONE" && ! -L "$MIGRATION_DONE" ) ]] || {
    printf 'No KMOS network handoff to roll back.\n' >&2; return 1;
  }
  printf 'Type ROLLBACK NETWORK to restore the previous services: ' >&2
  read -r response </dev/tty || return 1
  [[ "$response" == 'ROLLBACK NETWORK' ]] || return 1
  require_root --rollback || return 1
  rollback
}

main() {
  case "${1:-}" in
    --help|-h) (($# == 1)) || { usage >&2; return 2; }; usage ;;
    --plan) (($# == 1)) || { usage >&2; return 2; }; plan ;;
    --stage-reboot) (($# == 1)) || { usage >&2; return 2; }; stage_reboot ;;
    --cancel-stage) (($# == 1)) || { usage >&2; return 2; }; cancel_stage ;;
    --boot-check) (($# == 1)) || return 2; boot_check ;;
    --apply) (($# == 1)) || { usage >&2; return 2; }; apply_handoff ;;
    --rollback) (($# == 1)) || { usage >&2; return 2; }; manual_rollback ;;
    *) usage >&2; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
