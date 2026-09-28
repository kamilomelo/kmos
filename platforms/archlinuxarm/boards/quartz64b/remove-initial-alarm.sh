#!/usr/bin/env bash
# Remove the initial alarm account without repeating system provisioning.
set -Eeuo pipefail

case "${1:-}" in
  -h|--help)
    printf 'Usage: ./remove-initial-alarm.sh\nRemove the initial alarm account and /home/alarm, or defer removal until reboot if still logged in.\n'
    exit 0
    ;;
  '') ;;
  *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; exit 1 ;;
esac
(($# == 0)) || { printf 'ERROR: Unexpected arguments.\n' >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { printf 'ERROR: AArch64 board required.\n' >&2; exit 1; }
if ((EUID != 0)); then
  command -v sudo >/dev/null 2>&1 || { printf 'ERROR: Root access is required, but sudo is unavailable.\n' >&2; exit 1; }
  exec sudo -- "$(readlink -f -- "$0")" "$@"
fi

SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
# shellcheck source=platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh
source "$SCRIPT_DIR/provision-kmos-headless.sh"
REPOSITORY_DIR=$(find_local_repository)
PRIMARY_USER=${SUDO_USER:-}
if [[ -z "$PRIMARY_USER" || "$PRIMARY_USER" == root || "$PRIMARY_USER" == alarm ]]; then
  read -r -p 'Name of your new wheel administrator (not alarm): ' PRIMARY_USER
fi
remove_alarm
if ((REMOVE_ALARM_REQUESTED == 0)); then
  info 'alarm removal was declined; no account was removed.'
  exit 0
fi
if ((ALARM_REMOVAL_PENDING)); then
  info 'After reboot, check: getent passwd alarm (must produce no output).'
else
  info 'alarm removal verified.'
fi
