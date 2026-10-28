#!/usr/bin/env bash
# Offline completion tests: no unmounts or real reboot are performed.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"

reboot_installer() { printf 'reboot\n' >> "$fixture/actions"; }
read() {
  case "$response" in
    key) return 0 ;;
    closed) return 1 ;;
    timeout) return 142 ;;
  esac
}

response=key
countdown_or_reboot 9 > "$fixture/key-output" 2>&1
grep -q 'Staying on the live ISO' "$fixture/key-output"
[[ ! -e "$fixture/actions" ]]

response=closed
countdown_or_reboot 9 > "$fixture/closed-output" 2>&1
grep -q 'Terminal input closed; automatic reboot skipped' "$fixture/closed-output"
[[ ! -e "$fixture/actions" ]]

response=timeout
countdown_or_reboot 9 > "$fixture/timeout-output" 2>&1
[[ $(grep -o 'Press any key to stay' "$fixture/timeout-output" | wc -l) == 10 ]]
[[ $(cat "$fixture/actions") == reboot ]]
(
  unmount_target() { :; }
  sync() { :; }
  countdown_or_reboot() { :; }
  exec() { :; }
  final_reboot
) > "$fixture/final" 2>&1
grep -Fq 'Install complete.' "$fixture/final"
grep -Fq '9 ok' "$fixture/final"
! grep -Fq '100%' "$fixture/final"
printf 'Arch completion countdown and Kartouche summary: OK (mocked).\n'
