#!/usr/bin/env bash
# Fixture-only Wi-Fi presentation test: no network, sudo, or host writes.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
helper="$fixture/kmos-wifi-connect.sh"
# The live ISO often carries only this script in /root, with no sibling files.
cp "$repo/platforms/archlinux/tools/kmos-wifi-connect.sh" "$helper"
[[ ! -e "$fixture/kartouche.sh" ]]
bash -n "$helper"

for term in xterm-256color linux; do
  (
    # shellcheck disable=SC1090
    source "$helper"
    require_root() { :; }
    require_tools() { :; }
    unblock_wireless() { :; }
    select_wireless_adapter() { printf 'mock-wlan\n'; }
    scan_wifi_networks() { return 1; } # The manual SSID fallback is intentional.
    prompt_wifi_credentials() {
      local -n ssid_out=$1 pass_out=$2 hidden_out=$3
      ssid_out='fixture-ssid' pass_out='fixture-secret' hidden_out=1
    }
    connect_wifi() {
      [[ $1 == mock-wlan && $2 == fixture-ssid && $3 == fixture-secret && $4 == 1 ]]
      printf 'connect\n' >> "$fixture/$term.actions"
    }
    verify_internet() { printf 'verify\n' >> "$fixture/$term.actions"; }
    save_wifi_handoff() { printf 'handoff\n' >> "$fixture/$term.actions"; }
    timedatectl() { printf 'clock %s\n' "$*" >> "$fixture/$term.actions"; }
    TERM="$term" NO_COLOR=1 main > "$fixture/$term.stdout" 2> "$fixture/$term.stderr"
    if [[ $term == linux ]]; then [[ $KT_ACCENT == 37 ]]; else [[ $KT_ACCENT == '38;5;244' ]]; fi
  )
  [[ ! -s "$fixture/$term.stdout" ]]
  [[ $(cat "$fixture/$term.actions") == $'connect\nverify\nhandoff\nclock set-timezone Europe/Zurich\nclock set-ntp true\nclock status' ]]
  ! grep -Fq 'fixture-secret' "$fixture/$term.stderr"
  ! grep -Fq $'\033' "$fixture/$term.stderr"
  ! grep -Fq $'\r' "$fixture/$term.stderr"
  grep -Fq 'Selecting Wi-Fi network' "$fixture/$term.stderr"
  grep -Fq '4 ok' "$fixture/$term.stderr"
  mapfile -t lines < "$fixture/$term.stderr"
  [[ -z ${lines[-1]} && ${lines[-2]} == *'4 ok'*'0 failed'*'0 skipped' ]]
  frames=0
  for ((i=6; i<${#lines[@]}-1; i++)); do
    if [[ ${lines[i]} == *'/4' && ${lines[i]} == *'->'* ||
          ${lines[i]} == *'/4' && ${lines[i]} == *'❯'* ]]; then
      ((frames+=1))
      [[ -z ${lines[i-6]} && -z ${lines[i+1]} ]]
    fi
  done
  [[ $frames == 4 ]]
  if [[ $term == linux ]]; then
    grep -Fq '|- + Selecting wireless adapter' "$fixture/$term.stderr"
    grep -Fq '|- @ Selecting Wi-Fi network' "$fixture/$term.stderr"
  else
    grep -Fq '├─ ✓ Selecting wireless adapter' "$fixture/$term.stderr"
    grep -Fq '├─ ◉ Selecting Wi-Fi network' "$fixture/$term.stderr"
  fi
done

(
  # Preserve the helper's explicit ASCII override even in a Unicode terminal.
  # shellcheck disable=SC1090
  source "$helper"
  TERM=xterm-256color kmos_ASCII_UI=1 init_ui
  [[ $KT_GLYPHS == ascii && $SUCCESS_ICON == '>' ]]
)

(
  # A failed connectivity check must not report success or save handoff data.
  # shellcheck disable=SC1090
  source "$helper"
  require_root() { :; }
  require_tools() { :; }
  unblock_wireless() { :; }
  select_wireless_adapter() { printf 'mock-wlan\n'; }
  scan_wifi_networks() { return 1; }
  prompt_wifi_credentials() {
    local -n ssid_out=$1 pass_out=$2 hidden_out=$3
    ssid_out='fixture-ssid' pass_out='fixture-secret' hidden_out=0
  }
  connect_wifi() { :; }
  verify_internet() { return 1; }
  save_wifi_handoff() { printf 'unexpected handoff\n' >> "$fixture/failed.actions"; }
  main
) > "$fixture/failed.stdout" 2> "$fixture/failed.stderr" && exit 1
grep -Fq 'failed at 4/4 Verifying internet access' "$fixture/failed.stderr"
[[ ! -e "$fixture/failed.actions" ]]
! grep -Fq '4 ok' "$fixture/failed.stderr"

printf 'Arch ISO Wi-Fi Kartouche and manual fallback: OK (fixtures only).\n'
