#!/usr/bin/env bash
# Visual-only fixture; never call the installer's disk or account functions.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/kmos-archlinux-install.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

"$script" --help > "$fixture/help"
grep -Fq 'No argument starts the interactive x86 installation.' "$fixture/help"
"$script" preview-ui > "$fixture/preview.stdout" 2> "$fixture/preview.stderr"
[[ ! -s "$fixture/preview.stdout" ]]
grep -Fq '1/9' "$fixture/preview.stderr"
if "$script" preview-ui unwanted > "$fixture/invalid.stdout" 2> "$fixture/invalid.stderr"; then
  printf 'preview-ui accepted additional arguments.\n' >&2; exit 1
fi
grep -Fq 'does not accept additional arguments' "$fixture/invalid.stderr"

for term in xterm-256color linux; do
  (
    TERM=$term NO_COLOR=1
    # shellcheck disable=SC1090
    source "$script"
    init_ui
    print_banner
    advance_step 'Verifying live environment'
    [[ $STEP_INDEX == 1 && $STEP_TOTAL == 9 && $KT_PAUSE_SECONDS == 1 ]]
    if [[ $term == linux ]]; then
      [[ $KT_ACCENT == 37 && $KT_GLYPHS == ascii ]]
    else
      [[ $KT_ACCENT == '38;5;244' && $KT_GLYPHS == auto ]]
    fi
  ) > "$fixture/$term.stdout" 2> "$fixture/$term.stderr"
  [[ ! -s "$fixture/$term.stdout" ]]
  grep -Fq '1/9' "$fixture/$term.stderr"
  grep -Fq 'kmos Arch Linux Install' "$fixture/$term.stderr"
  grep -Fq 'Formatting and mounting' "$fixture/$term.stderr"
  ! grep -Fq $'\033' "$fixture/$term.stderr"
  if [[ $term == linux ]]; then
    grep -Fq '|- @ Verifying live environment' "$fixture/$term.stderr"
  else
    grep -Fq '├─ ◉ Verifying live environment' "$fixture/$term.stderr"
  fi
done

(
  TERM=xterm-256color ASCII_UI=1
  # shellcheck disable=SC1090
  source "$script"
  init_ui
  [[ $KT_GLYPHS == ascii ]]
)

printf 'Arch installer Kartouche banner and first step: OK (no install).\n'
