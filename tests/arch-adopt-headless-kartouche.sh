#!/usr/bin/env bash
# Read-only mocked adoption preview: no packages, accounts or host changes.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/kmos-adopt-headless.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

for term in xterm-256color linux; do
  (
    TERM=$term
    # shellcheck disable=SC1090
    source "$script"
    eligible() { :; }
    packages_for_host() { PACKAGES=(git openssh); }
    installed() { [[ $1 == git ]]; }
    hostname() { printf 'fixture-arch\n'; }
    regular_users() { printf 'tester:x:1000:1000::/home/tester:/bin/bash\n'; }
    is_admin() { return 1; }
    systemctl() {
      if [[ $1 == is-enabled ]]; then printf 'disabled\n'; else printf 'inactive\n'; fi
    }
    helper_works() { return 1; }
    preflight > "$fixture/$term.stdout" 2> "$fixture/$term.stderr"
    [[ $KT_PAUSE_SECONDS == 1 ]]
    if [[ $term == linux ]]; then
      [[ $KT_ACCENT == 37 ]]
    else
      [[ $KT_ACCENT == '38;5;244' ]]
    fi
  )
  grep -Fq 'Arch headless x86_64: eligible' "$fixture/$term.stdout"
  grep -Fq 'Current hostname: fixture-arch' "$fixture/$term.stdout"
  grep -Fq 'No changes made.' "$fixture/$term.stdout"
  grep -Fq 'Read-only preflight' "$fixture/$term.stderr"
  grep -Fq '3 ok' "$fixture/$term.stderr"
  ! grep -Fq $'\033' "$fixture/$term.stderr"
  if [[ $term == linux ]]; then
    grep -Fq '|- + Host settings unchanged' "$fixture/$term.stderr"
  else
    grep -Fq '├─ ✓ Host settings unchanged' "$fixture/$term.stderr"
  fi
done

# A checkout without the optional renderer retains its original read-only
# inventory instead of turning the preview into an installation dependency.
(
  # shellcheck disable=SC1090
  source "$script"
  SCRIPT_DIR="$fixture/without-renderer"
  eligible() { :; }
  packages_for_host() { PACKAGES=(git); }
  installed() { return 1; }
  hostname() { printf 'fixture-arch\n'; }
  regular_users() { :; }
  systemctl() { printf 'inactive\n'; }
  helper_works() { return 1; }
  preflight
) > "$fixture/plain.stdout" 2> "$fixture/plain.stderr"
grep -Fq 'No changes made.' "$fixture/plain.stdout"
[[ ! -s "$fixture/plain.stderr" ]]

printf 'Arch adoption Kartouche preflight: OK (fixtures only).\n'
