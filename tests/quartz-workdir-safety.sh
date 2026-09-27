#!/usr/bin/env bash
# Never delete a custom SD-preparation cache in a mocked cleanup test.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
touch "$fixture/keep-me"

# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh"
WORK_DIR="$fixture"
CUSTOM_WORK_DIR=1
cleanup_workdir_prompt < /dev/null
[[ -f "$fixture/keep-me" ]]
printf 'Quartz custom SD-preparation work directory remains untouched: OK.\n'
