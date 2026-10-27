#!/usr/bin/env bash
# Presentation-only preflight fixtures: no package, network or system changes.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

for term in xterm-256color linux; do
  (
    TERM=$term
    # shellcheck disable=SC1090
    source "$script"
    if [[ $term == linux ]]; then
      [[ $KT_ACCENT == 37 ]]
    else
      [[ $KT_ACCENT == '38;5;244' ]]
    fi
    os_id() { printf 'arch\n'; }
    uname() { printf 'x86_64\n'; }
    headless_marker_present() { :; }
    kde_profile_present() { return 1; }
    package_installed() { return 1; }
    ip() { printf 'default via 192.0.2.1 dev enp0s2\n'; }
    service_state() { printf 'inactive\n'; }
    service_enabled() { printf 'disabled\n'; }
    kde_upgrade_banner 'Read-only preflight'
    preflight
  ) > "$fixture/$term.stdout" 2> "$fixture/$term.stderr"
  grep -Fq 'KMOS headless base: present' "$fixture/$term.stdout"
  grep -Fq 'KDE/SDDM already present: no' "$fixture/$term.stdout"
  grep -Fq 'Default-route interface: enp0s2' "$fixture/$term.stdout"
  grep -Fq 'Preflight complete: nothing was changed.' "$fixture/$term.stdout"
  grep -Fq 'kmos Headless to KDE' "$fixture/$term.stderr"
  grep -Fq 'Read-only preflight' "$fixture/$term.stderr"
  grep -Fq '3 ok' "$fixture/$term.stderr"
  ! grep -Fq $'\033' "$fixture/$term.stderr"
  if [[ $term == linux ]]; then
    grep -Fq '|- + KMOS headless base' "$fixture/$term.stderr"
  else
    grep -Fq '├─ ✓ KMOS headless base' "$fixture/$term.stderr"
  fi
done

# The interactive entry point must show Kartouche before selecting packages.
(
  # shellcheck disable=SC1090
  source "$script"
  install_layer() { printf 'selection reached\n'; }
  main
) > "$fixture/guided.stdout" 2> "$fixture/guided.stderr"
grep -Fxq 'selection reached' "$fixture/guided.stdout"
grep -Fq 'Guided desktop upgrade' "$fixture/guided.stderr"

printf 'Arch headless-to-KDE Kartouche preflight: OK (fixtures only).\n'
