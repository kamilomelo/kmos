#!/usr/bin/env bash
# USB flasher presentation fixtures: no device writes, downloads or sudo.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
script="$fixture/kmos-usb-flasher.sh"
# The flasher must also work when only its script is copied to a USB host.
cp "$repo/platforms/archlinux/tools/kmos-usb-flasher.sh" "$script"
[[ ! -e "$fixture/kartouche.sh" ]]
bash -n "$script"
# Keep the inlined code aligned with the pinned Kartouche source in this repo.
cmp -s \
  <(sed -n '/^# kartouche:code begin v5$/,/^# kartouche:code end$/p' "$script") \
  <(sed -n '/^# kartouche:code begin v5$/,/^# kartouche:code end$/p' "$repo/platforms/archlinux/tools/kartouche.sh")

for term in xterm-256color linux; do
  (
    # shellcheck disable=SC1090
    source "$script"
    WORK_DIR="$fixture/work"
    require_tools() { :; }
    ensure_workdir() { :; }
    init_base_urls() { :; }
    prepare_iso_for_os() { printf '/mock/arch.iso\n'; }
    select_target_disk() { printf '/dev/mock-usb\n'; }
    flash_iso() { printf '%s %s\n' "$1" "$2" >> "$fixture/write-args"; }
    cleanup_workdir_prompt() { :; }
    TERM="$term" NO_COLOR=1 main <<< '' > "$fixture/$term.stdout" 2> "$fixture/$term.stderr"
    TERM="$term" success 'USB ready' > "$fixture/$term.success" 2>&1
    if [[ "$term" == linux ]]; then
      [[ "$KT_ACCENT" == 37 ]]
    else
      [[ "$KT_ACCENT" == '38;5;244' ]]
    fi
  )
  [[ ! -s "$fixture/$term.stdout" ]]
  [[ $(cat "$fixture/write-args") == *'/mock/arch.iso /dev/mock-usb' ]]
  grep -Fq 'Warning: the selected target disk will be erased.' "$fixture/$term.stderr"
  mapfile -t lines < "$fixture/$term.stderr"
  frames=0
  banner_spaced=0
  for ((i=1; i<${#lines[@]}-1; i++)); do
    if [[ ${lines[i]} == *'Bootable USB creator for Arch Linux and Rocky Linux.' ]]; then
      ((banner_spaced+=1))
      [[ -z ${lines[i+1]} ]]
    fi
    if [[ ${lines[i]} == *'/4' && ${lines[i]} == *'->'* ||
          ${lines[i]} == *'/4' && ${lines[i]} == *'❯'* ]]; then
      ((frames+=1))
      [[ -z ${lines[i+1]} ]]
      [[ ${lines[i-5]} == *'kmos USB Flasher' && -z ${lines[i-6]} ]]
    fi
  done
  [[ $banner_spaced == 1 && $frames == 4 ]]
  grep -Fq '1/4' "$fixture/$term.stderr"
  grep -Fq '2/4' "$fixture/$term.stderr"
  grep -Fq '3/4' "$fixture/$term.stderr"
  grep -Fq '4/4' "$fixture/$term.stderr"
  grep -Fq '4 ok' "$fixture/$term.stderr"
  grep -Fq '0 failed' "$fixture/$term.stderr"
  [[ -z ${lines[-1]} && ${lines[-2]} == *'4 ok'*'0 failed'*'0 skipped' ]]
  ! grep -Fq $'\033' "$fixture/$term.stderr"
  ! grep -Fq $'\r' "$fixture/$term.stderr"
  if [[ "$term" == linux ]]; then
    grep -Fq ',- * kmos USB Flasher' "$fixture/$term.stderr"
    grep -Fq '|- + Preparing installation media' "$fixture/$term.stderr"
    grep -Fq '|- @ Selecting target USB disk' "$fixture/$term.stderr"
    grep -Fq '> USB ready' "$fixture/$term.success"
  else
    grep -Fq '╭─ ● kmos USB Flasher' "$fixture/$term.stderr"
    grep -Fq '├─ ✓ Preparing installation media' "$fixture/$term.stderr"
    grep -Fq '├─ ◉ Selecting target USB disk' "$fixture/$term.stderr"
    grep -Fq '▸ USB ready' "$fixture/$term.success"
  fi
done

(
  # Failing a safety gate must never produce a success end state.
  # shellcheck disable=SC1090
  source "$script"
  KT_GLYPHS=ascii
  advance_step
  die 'Cancelled before selecting a device'
) > "$fixture/fail.stdout" 2> "$fixture/fail.stderr" && exit 1
grep -Fq 'failed at 1/4 Preparing installation media' "$fixture/fail.stderr"
! grep -Fq '4 ok' "$fixture/fail.stderr"

(
  # The erase warning and explicit confirmation still gate the unchanged dd.
  # shellcheck disable=SC1090
  source "$script"
  printf 'fake iso\n' > "$fixture/image.iso"
  unmount_target_partitions() { printf 'unmount\n' >> "$fixture/flash-order"; }
  run_privileged() { printf '%s\n' "$*" >> "$fixture/flash-order"; }
  sync() { printf 'sync\n' >> "$fixture/flash-order"; }
  confirm_yes_no() { return 1; }
  if ( flash_iso "$fixture/image.iso" /dev/mock-usb ) > "$fixture/declined" 2>&1; then exit 1; fi
  [[ ! -e "$fixture/flash-order" ]]
  grep -Fq 'All data on /dev/mock-usb will be permanently erased.' "$fixture/declined"
  confirm_yes_no() { return 0; }
  flash_iso "$fixture/image.iso" /dev/mock-usb > "$fixture/approved" 2>&1
  [[ $(sed -n '1p' "$fixture/flash-order") == unmount ]]
  grep -Fq "dd if=$fixture/image.iso of=/dev/mock-usb bs=4M status=progress oflag=sync conv=fsync" "$fixture/flash-order"
  [[ $(tail -n 1 "$fixture/flash-order") == sync ]]
)

printf 'USB flasher Kartouche preview and failure paths: OK (fixtures only).\n'
