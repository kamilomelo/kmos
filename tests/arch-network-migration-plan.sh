#!/usr/bin/env bash
# Fixture-only inventory; no host services, saved networks or routes changed.
# Mock functions and variables are used by the sourced script.
# shellcheck disable=SC1090,SC2034,SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/tools/kmos-network-migration.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
"$script" --help > "$fixture/help"
grep -Fq -- '--apply requires a' "$fixture/help"
if "$script" --apply > "$fixture/rejected" 2>&1; then
  printf 'A non-interactive network migration was accepted.\n' >&2; exit 1
fi
grep -Fq 'Local interactive console required' "$fixture/rejected"
mkdir -p "$fixture/net/enp1s0" "$fixture/net/wlan0/wireless"
touch "$fixture/net/enp1s0/device" "$fixture/net/wlan0/device"
printf '1\n' > "$fixture/net/enp1s0/type"
printf '1\n' > "$fixture/net/wlan0/type"
printf '1\n' > "$fixture/net/enp1s0/carrier"
printf '1\n' > "$fixture/net/wlan0/carrier"
printf '[General]\nEnableNetworkConfiguration=true\n' > "$fixture/iwd.conf"
(
  # shellcheck disable=SC1091
  source "$script"
  TERM=linux
  SYS_NET_ROOT="$fixture/net"
  IWD_CONF="$fixture/iwd.conf"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  kde_ready() { :; }
  nmcli() { :; }
  state() {
    [[ "$2" == iwd.service || "$2" == sshd.service ]] && printf 'active\n' || printf 'inactive\n'
  }
  ip() {
    case "$*" in
      '-o -4 addr show dev enp1s0 scope global') printf 'fixture-IPv4\n' ;;
      '-o -4 addr show dev wlan0 scope global') printf 'fixture-IPv4\n' ;;
      '-4 route show default dev enp1s0') printf 'fixture-default-route\n' ;;
      'route get 192.0.2.9') printf '192.0.2.9 dev wlan0\n' ;;
      *) return 1 ;;
    esac
  }
  SSH_CONNECTION='192.0.2.9 1234 192.0.2.10 22'
  plan
) > "$fixture/plan" 2> "$fixture/plan-ui"
grep -Fq 'Handoff plan' "$fixture/plan-ui"
grep -Fq '|- + Network services unchanged' "$fixture/plan-ui"
grep -Fq '2 ok' "$fixture/plan-ui"
! grep -Fq $'\033' "$fixture/plan-ui"
grep -Fq 'enp1s0: Ethernet, carrier=1, IPv4=yes, default route=yes' "$fixture/plan"
grep -Fq 'wlan0: Wi-Fi, carrier=1, IPv4=yes' "$fixture/plan"
grep -Fq 'Current SSH route interface: wlan0' "$fixture/plan"
grep -Fq 'iwd built-in IP configuration: enabled' "$fixture/plan"
grep -Fq 'Plan complete: nothing changed' "$fixture/plan"
(
  # shellcheck disable=SC1091
  source "$script"
  TERM=xterm-256color
  SYS_NET_ROOT="$fixture/net" IWD_CONF="$fixture/iwd.conf"
  STAGED_MARKER="$fixture/no-stage" MIGRATION_DONE="$fixture/no-done"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  kde_ready() { :; }
  nmcli() { :; }
  state() { printf 'inactive\n'; }
  ip() {
    case "$*" in
      '-o -4 addr show dev enp1s0 scope global') printf 'fixture-IPv4\n' ;;
      '-4 route show default dev enp1s0') printf 'fixture-default-route\n' ;;
      *) return 1 ;;
    esac
  }
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY
  plan
) > "$fixture/wired-only-plan" 2> "$fixture/wired-only-ui"
grep -Fq '├─ ✓ Network services unchanged' "$fixture/wired-only-ui"
grep -Fq 'Wi-Fi has no IPv4: --apply requires active Wi-Fi and will refuse' "$fixture/wired-only-plan"
grep -Fq -- '--stage-reboot can use disconnected Wi-Fi' "$fixture/wired-only-plan"
(
  # shellcheck disable=SC1091
  source "$script"
  SYS_NET_ROOT="$fixture/net" IWD_CONF="$fixture/iwd.conf"
  STAGED_MARKER="$fixture/no-stage" MIGRATION_DONE="$fixture/no-done"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  kde_ready() { :; }
  nmcli() { :; }
  state() { printf 'inactive\n'; }
  ip() {
    case "$*" in
      '-o -4 addr show dev wlan0 scope global') printf 'fixture-IPv4\n' ;;
      *) return 1 ;;
    esac
  }
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY
  plan
) > "$fixture/wifi-only-plan"
grep -Fq -- '--stage-reboot-wifi rechecks service state and Wi-Fi internet' "$fixture/wifi-only-plan"
(
  # shellcheck disable=SC1091
  source "$script"
  SYS_NET_ROOT="$fixture/net"
  IWD_CONF="$fixture/iwd.conf"
  STAGED_MARKER="$fixture/no-stage" MIGRATION_DONE="$fixture/no-done"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  kde_ready() { :; }
  nmcli() { :; }
  state() { printf 'inactive\n'; }
  ip() { return 1; }
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY
  plan
) > "$fixture/no-ssh-plan"
grep -Fq 'Plan complete: nothing changed' "$fixture/no-ssh-plan"
if grep -Fq 'Current SSH route interface' "$fixture/no-ssh-plan"; then
  printf 'Invented an SSH route when there was no SSH session.\n' >&2; exit 1
fi
: > "$fixture/done-fixture"
(
  # shellcheck disable=SC1091
  source "$script"
  SYS_NET_ROOT="$fixture/net"
  IWD_CONF="$fixture/iwd.conf"
  STAGED_MARKER="$fixture/no-stage" MIGRATION_DONE="$fixture/done-fixture"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  kde_ready() { :; }
  nmcli() { :; }
  state() { printf 'inactive\n'; }
  ip() { return 1; }
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY
  plan
) > "$fixture/done-plan"
grep -Fq 'Verify NetworkManager Wi-Fi before unplugging Ethernet' "$fixture/done-plan"
if grep -Fq 'Use --apply' "$fixture/done-plan"; then
  printf 'Suggested the live handoff after completion.\n' >&2; exit 1
fi
if grep -Eq '192\.0\.2\.|password=|SSID: ' "$fixture/plan"; then
  printf 'Inventory leaked connection details.\n' >&2; exit 1
fi
if grep -Eq '192\.0\.2\.|password=|SSID: ' "$fixture/plan-ui"; then
  printf 'Styled inventory leaked connection details.\n' >&2; exit 1
fi

# A copy used as a boot guard has no renderer sibling. Its inventory stays
# functional, and boot/service paths never depend on the presentation helper.
mkdir -p "$fixture/standalone/net"
cp "$script" "$fixture/standalone/kmos-network-migration.sh"
(
  # shellcheck disable=SC1091
  source "$fixture/standalone/kmos-network-migration.sh"
  SYS_NET_ROOT="$fixture/standalone/net"
  STAGED_MARKER="$fixture/no-stage" MIGRATION_DONE="$fixture/no-done"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  kde_ready() { :; }
  state() { printf 'inactive\n'; }
  ip() { return 1; }
  plan
) > "$fixture/standalone-plan" 2> "$fixture/standalone-ui"
grep -Fq 'Handoff not ready: a physical Wi-Fi interface is required.' "$fixture/standalone-plan"
[[ ! -s "$fixture/standalone-ui" ]]
printf 'Network migration inventory: OK (fixture only; no service changes).\n'
