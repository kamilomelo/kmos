#!/usr/bin/env bash
# Repair only the Quartz64 headless Bash/Starship prompt on an existing install.
set -Eeuo pipefail

case "${1:-}" in
  -h|--help)
    printf 'Usage: ./repair-headless-prompt.sh\nRepair only the Quartz64 headless SSH/TTY prompt from this KMOS checkout.\n'
    exit 0
    ;;
  '') ;;
  *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; exit 1 ;;
esac
(($# == 0)) || { printf 'ERROR: Unexpected arguments.\n' >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { printf 'ERROR: This repair is for AArch64 boards.\n' >&2; exit 1; }
if ((EUID != 0)); then
  command -v sudo >/dev/null 2>&1 || { printf 'ERROR: Root access is required, but sudo is unavailable.\n' >&2; exit 1; }
  exec sudo -- "$(readlink -f -- "$0")" "$@"
fi

SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
# shellcheck source=platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh
source "$SCRIPT_DIR/provision-kmos-headless.sh"
repository_dir=$(find_local_repository)
configure_kmos_terminal "$repository_dir"
info 'Headless Starship prompt repaired. Start a new SSH session to check it.'
