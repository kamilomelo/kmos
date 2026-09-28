#!/usr/bin/env bash
# Optional source-built AUR helper for an existing Quartz64 headless system.
set -Eeuo pipefail

case "${1:-}" in
  -h|--help)
    printf 'Usage: ./install-aur-helper.sh\nInteractively choose paru or yay to build as an administrator on AArch64.\n'
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
find_local_repository >/dev/null
PRIMARY_USER=${SUDO_USER:-}
if [[ -z "$PRIMARY_USER" || "$PRIMARY_USER" == root || "$PRIMARY_USER" == alarm ]]; then
  read -r -p 'Administrator username for the AUR build: ' PRIMARY_USER
fi
offer_aur_helper
