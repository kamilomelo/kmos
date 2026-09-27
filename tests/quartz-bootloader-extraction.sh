#!/usr/bin/env bash
# Small local ZIP fixture; does not download or execute bootloader code.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh"

fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/input/artifacts" "$fixture/output"
printf 'test idblock\n' > "$fixture/input/artifacts/idblock.bin"
printf 'test uboot\n' > "$fixture/input/artifacts/uboot.img"
bsdtar -cf "$fixture/bootloader.zip" --format zip -C "$fixture/input" artifacts/idblock.bin artifacts/uboot.img

extract_bootloader "$fixture/bootloader.zip" "$fixture/output"
cmp "$fixture/input/artifacts/idblock.bin" "$fixture/output/idblock.bin"
cmp "$fixture/input/artifacts/uboot.img" "$fixture/output/uboot.img"
printf 'Quartz bootloader ZIP extraction works with installed bsdtar: OK.\n'
