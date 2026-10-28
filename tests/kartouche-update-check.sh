#!/usr/bin/env bash
# Offline fixtures for the scheduled read-only Kartouche update check.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
checker="$repo/scripts/check-kartouche-update.sh"
pinned="$fixture/pinned.sh"
upstream="$fixture/upstream.sh"
cp "$repo/platforms/archlinux/tools/kartouche.sh" "$pinned"
cp "$pinned" "$upstream"
export KARTOUCHE_PINNED_FILE="$pinned" KARTOUCHE_SOURCE_URL="file://$upstream"

KARTOUCHE_SOURCE_URL=file:///not/a/real/file "$checker" --help > "$fixture/help"
grep -Fq 'never modify KMOS files' "$fixture/help"
"$checker" > "$fixture/current"
grep -Fq 'template v6 is current' "$fixture/current"

# A project-specific config value is intentional, not a new template version.
sed -i "s/^KT_NAME=.*/KT_NAME='another name'/" "$upstream"
"$checker" > "$fixture/custom-config"

expect_update() {
  if "$checker" > "$fixture/check" 2>&1; then
    printf 'Missed Kartouche update: %s\n' "$1" >&2
    exit 1
  fi
  grep -Fq 'Review the code/config diff' "$fixture/check"
  [[ $(cat "$pinned") == "$(cat "$repo/platforms/archlinux/tools/kartouche.sh")" ]]
}

sed -i 's/^# KARTOUCHE_TEMPLATE_VERSION: 6$/# KARTOUCHE_TEMPLATE_VERSION: 7/; s/^# kartouche:code begin v6$/# kartouche:code begin v7/' "$upstream"
expect_update version
cp "$pinned" "$upstream"
sed -i 's/^_kt_text() { /_kt_text() { # upstream change /' "$upstream"
expect_update code
cp "$pinned" "$upstream"
sed -i '/^# kartouche:config end$/i KT_NEW_OPTION=1' "$upstream"
expect_update config-key
cp "$pinned" "$upstream"
sed -i '/^# kartouche:code end$/d' "$upstream"
if "$checker" > "$fixture/invalid" 2>&1; then exit 1; fi
grep -Fq 'markers are invalid' "$fixture/invalid"

printf 'Kartouche upstream check detects template changes offline without editing scripts.\n'
