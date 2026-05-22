#!/bin/bash
# kmos platform dispatcher
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ARCH_INSTALLER="$SCRIPT_DIR/platforms/archlinux/kmos-archlinux-install.sh"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

detect_linux_id() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  printf '%s\n' "${ID:-}"
}

main() {
  local os_id=""

  [[ -x "$ARCH_INSTALLER" ]] || die "Missing Arch Linux installer: $ARCH_INSTALLER"

  case "${OSTYPE:-}" in
    msys*|cygwin*|win32*)
      die "Windows support is not implemented yet. Planned platform path: platforms/windows/"
      ;;
  esac

  os_id="$(detect_linux_id || true)"
  case "$os_id" in
    arch|archarm)
      exec bash "$ARCH_INSTALLER" "$@"
      ;;
    rocky)
      die "Rocky Linux support is not implemented yet. Planned platform path: platforms/rocky/"
      ;;
    "")
      die "Could not detect the operating system."
      ;;
    *)
      die "Unsupported platform for the current dispatcher: $os_id"
      ;;
  esac
}

main "$@"
