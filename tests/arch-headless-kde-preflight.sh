#!/usr/bin/env bash
# Read-only mocked preflight; never run a desktop install against the host.
# Mock functions are consumed by the sourced preflight.
# shellcheck disable=SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

"$script" --help > "$fixture/help"
grep -Fq 'No KDE upgrade operation is available yet.' "$fixture/help"
if "$script" --install > "$fixture/rejected" 2>&1; then
  printf 'Unexpectedly accepted an installation request.\n' >&2; exit 1
fi
grep -Fq -- '--preflight' "$fixture/rejected"

(
  # shellcheck disable=SC1091 # Sourced entry point is guarded against execution.
  source "$script"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  headless_marker_present() { :; }
  kde_profile_present() { return 1; }
  package_installed() { [[ "$1" == iwd || "$1" == openssh ]]; }
  ip() { printf 'default via 192.0.2.1 dev eth0 proto dhcp\n'; }
  service_state() { [[ "$1" == sshd.service ]] && printf 'active\n' || printf 'inactive\n'; }
  service_enabled() { [[ "$1" == sshd.service ]] && printf 'enabled\n' || printf 'disabled\n'; }
  SSH_CONNECTION='fixture-only'
  preflight
) > "$fixture/report"
grep -Fq 'Default-route interface: eth0' "$fixture/report"
grep -Fq 'Package iwd              installed' "$fixture/report"
grep -Fq 'Service sshd.service            active=active enabled=enabled' "$fixture/report"
grep -Fq 'This shell is over SSH: yes' "$fixture/report"
grep -Fq 'Preflight complete: nothing was changed.' "$fixture/report"

if (
  # shellcheck disable=SC1091
  source "$script"
  os_id() { printf 'rocky\n'; }
  preflight
) > "$fixture/wrong-os" 2>&1; then
  printf 'Preflight accepted a different operating system.\n' >&2; exit 1
fi
grep -Fq 'Only installed Arch Linux x86_64 is supported' "$fixture/wrong-os"

printf 'Headless KDE preflight and install-command refusal: OK (mocked only).\n'
