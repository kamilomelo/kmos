#!/usr/bin/env bash
# Mocked KDE finishing plan; never touch system or personal KDE settings.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/desktop/kde/kmos-kde-finish.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

for term in xterm-256color linux; do
  (
    TERM=$term
    # shellcheck disable=SC1090
    source "$script"
    [[ $KT_PAUSE_SECONDS == 1 ]]
    if [[ $term == linux ]]; then
      [[ $KT_ACCENT == 37 ]]
    else
      [[ $KT_ACCENT == '38;5;244' ]]
    fi
    choose_user() { user=fixture; home="$fixture/home"; }
    check_system() { :; }
    stage_defaults() { printf 'plan\n' >> "$fixture/$term.actions"; }
    main --plan > "$fixture/$term.stdout" 2> "$fixture/$term.stderr"
  )
  [[ $(cat "$fixture/$term.actions") == plan ]]
  grep -Fq 'KMOS KDE defaults for fixture (plan)' "$fixture/$term.stdout"
  grep -Fq 'Done. Skipped existing files: 0.' "$fixture/$term.stdout"
  grep -Fq 'Read-only KDE defaults plan' "$fixture/$term.stderr"
  grep -Fq '2 ok' "$fixture/$term.stderr"
  ! grep -Fq $'\033' "$fixture/$term.stderr"
  if [[ $term == linux ]]; then
    grep -Fq '|- + No existing settings replaced' "$fixture/$term.stderr"
  else
    grep -Fq '├─ ✓ No existing settings replaced' "$fixture/$term.stderr"
  fi
done

printf 'KDE finish Kartouche plan: OK (mocked only).\n'
