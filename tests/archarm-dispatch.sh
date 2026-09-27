#!/usr/bin/env bash
# Checks the Arch Linux ARM branch without executing an installer.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
source "$repo/kmos-install.sh"

detect_linux_id() { printf 'archarm\n'; }
ARCH_INSTALLER=/this-installer-must-not-exist
ROCKY_INSTALLER=/this-installer-must-not-exist

result=$(main 2>&1) && {
  printf 'Arch Linux ARM was unexpectedly accepted by the x86 dispatcher.\n' >&2
  exit 1
}
[[ "$result" == *'the x86 installer cannot run on ARM'* ]] || {
  printf 'The dispatcher rejected ARM for the wrong reason: %s\n' "$result" >&2
  exit 1
}
printf 'Arch Linux ARM dispatch refuses the x86 installer: OK.\n'
