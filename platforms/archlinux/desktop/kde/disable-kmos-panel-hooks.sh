#!/usr/bin/env bash
# Stop old KMOS Plasma panel hooks without touching anyone's panel configuration.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./disable-kmos-panel-hooks.sh [--help]

On an installed x86 Arch system, disable only KMOS-generated Plasma panel
update scripts. Each is renamed to a .kmos-disabled backup; unknown or edited
files are preserved and cause an error. This does not reset or rearrange your
existing panel. If its saved layout is already damaged, restore it from your
own backup or edit it in Plasma after saving a copy of the configuration.
EOF
}

case "${1:-}" in
  -h|--help) (($# == 1)) || exit 2; usage; exit 0 ;;
  '') (($# == 0)) || { usage >&2; exit 2; } ;;
  *) usage >&2; exit 2 ;;
esac

if ((EUID != 0)); then
  command -v sudo >/dev/null 2>&1 || { printf 'ERROR: sudo is required to disable system-wide panel hooks.\n' >&2; exit 1; }
  printf 'System-wide panel hooks require sudo; your password will be requested by sudo.\n' >&2
  exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
fi

SCRIPT_DIR=$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=platforms/archlinux/desktop/kde/kmos-kde-post.sh
source "$SCRIPT_DIR/kmos-kde-post.sh"
MOUNT_POINT=""
disable_legacy_panel_updates
printf 'KMOS panel hooks disabled. The saved Plasma panel layout was not changed.\n'
