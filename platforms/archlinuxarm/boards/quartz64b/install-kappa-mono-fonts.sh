#!/usr/bin/env bash
# Install the Kappa Mono Nerd Font on an existing Quartz64 headless system.
set -Eeuo pipefail

case "${1:-}" in
  -h|--help)
    printf 'Usage: ./install-kappa-mono-fonts.sh\nInstall Kappa Mono from its GitHub source without rerunning provisioning.\n'
    exit 0
    ;;
  '') ;;
  *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; exit 1 ;;
esac
(($# == 0)) || { printf 'ERROR: Unexpected arguments.\n' >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { printf 'ERROR: This installer is for AArch64 boards.\n' >&2; exit 1; }
if ((EUID != 0)); then
  command -v sudo >/dev/null 2>&1 || { printf 'ERROR: Root access is required, but sudo is unavailable.\n' >&2; exit 1; }
  exec sudo -- "$(readlink -f -- "$0")" "$@"
fi

SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
# shellcheck source=platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh
source "$SCRIPT_DIR/provision-kmos-headless.sh"
find_local_repository >/dev/null
install_kappa_mono_fonts
info 'Kappa Mono is installed on the Quartz64. SSH glyphs depend on the font selected in the client terminal.'
