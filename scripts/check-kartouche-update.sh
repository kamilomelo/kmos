#!/usr/bin/env bash
# Read-only upstream check; never replace the pinned template or installer code.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/check-kartouche-update.sh [--help]

Compare the pinned Kartouche Bash template with upstream. Exit 1 if an update
needs review or upstream is unavailable; never modify KMOS files. CI runs this
weekly and on request. KARTOUCHE_SOURCE_URL and KARTOUCHE_PINNED_FILE are
optional test overrides.
EOF
}

if (($# > 0)); then
  if (($# == 1)) && [[ $1 == --help || $1 == -h ]]; then usage; exit 0; fi
  usage >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
pinned=${KARTOUCHE_PINNED_FILE:-$script_dir/../platforms/archlinux/tools/kartouche.sh}
url=${KARTOUCHE_SOURCE_URL:-https://raw.githubusercontent.com/kamilomelo/kartouche/main/bash/kartouche.sh}
[[ -f $pinned && -r $pinned ]] || { printf 'Pinned Kartouche template is unavailable: %s\n' "$pinned" >&2; exit 1; }
command -v curl >/dev/null || { printf 'curl is needed to check upstream Kartouche.\n' >&2; exit 1; }

temp=$(mktemp) || exit 1
trap 'rm -f -- "$temp"' EXIT
if ! curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 "$url" -o "$temp"; then
  printf 'Could not check upstream Kartouche; do not assume the copy is current.\n' >&2
  exit 1
fi

version() { sed -n 's/^# KARTOUCHE_TEMPLATE_VERSION: \([0-9][0-9]*\)$/\1/p' "$1"; }
code() { sed -n '/^# kartouche:code begin v[0-9][0-9]*$/,/^# kartouche:code end$/p' "$1"; }
config_keys() {
  sed -n '/^# kartouche:config begin$/,/^# kartouche:config end$/p' "$1" |
    sed -n 's/^\(KT_[A-Z_][A-Z_0-9]*\)=.*/\1/p' | sort -u
}
valid_template() {
  local file=$1 version_number
  version_number=$(version "$file")
  [[ $version_number =~ ^[0-9]+$ ]] &&
    [[ $(grep -Ec '^# kartouche:code begin v[0-9]+$' "$file") == 1 ]] &&
    [[ $(grep -c '^# kartouche:code end$' "$file") == 1 ]] &&
    [[ $(grep -c '^# kartouche:config begin$' "$file") == 1 ]] &&
    [[ $(grep -c '^# kartouche:config end$' "$file") == 1 ]] &&
    [[ $(code "$file" | head -n 1) == "# kartouche:code begin v$version_number" ]] &&
    [[ $(code "$file" | tail -n 1) == '# kartouche:code end' ]]
}

valid_template "$pinned" || { printf 'Pinned Kartouche template markers are invalid.\n' >&2; exit 1; }
valid_template "$temp" || { printf 'Upstream Kartouche template markers are invalid.\n' >&2; exit 1; }

if [[ $(version "$pinned") == "$(version "$temp")" ]] &&
   cmp -s <(code "$pinned") <(code "$temp") &&
   cmp -s <(config_keys "$pinned") <(config_keys "$temp"); then
  printf 'Kartouche Bash template v%s is current; KMOS files unchanged.\n' "$(version "$pinned")"
  exit 0
fi

printf 'Kartouche Bash template changed upstream (KMOS v%s, upstream v%s). Review the code/config diff and update the pinned copy and embedded scripts together; KMOS files unchanged.\n' \
  "$(version "$pinned")" "$(version "$temp")" >&2
if [[ -n ${GITHUB_ACTIONS:-} ]]; then
  printf '::error title=Kartouche update requires review::Pinned KMOS Bash template differs from upstream; no installer files were changed.\n' >&2
fi
exit 1
