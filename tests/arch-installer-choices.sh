#!/usr/bin/env bash
# Mocked input only; never execute the installer's disk or format operations.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"
TERM=linux NO_COLOR=1
init_ui

choice=$(prompt_choice 'Test filesystem options' xfs xfs ext4 <<< '2' 2> "$fixture/choice")
[[ $choice == ext4 ]]
grep -Fq '|- 1) xfs' "$fixture/choice"
grep -Fq '|- 2) ext4' "$fixture/choice"
choice=$(prompt_choice 'Test filesystem options' xfs xfs ext4 <<< '' 2> "$fixture/default")
[[ $choice == xfs ]]
choice=$(prompt_choice 'AUR helper options' paru paru yay <<< 'yay' 2> "$fixture/yay-name")
[[ $choice == yay ]]
grep -Fq '|- 2) yay' "$fixture/yay-name"
choice=$(prompt_choice 'AUR helper options' paru paru yay <<< '2' 2> "$fixture/yay-number")
[[ $choice == yay ]]
choice=$(prompt_choice 'AUR helper options' paru paru yay <<< $'YAY\nyay' 2> "$fixture/invalid-helper")
[[ $choice == yay ]]
grep -Fq 'Invalid selection. Enter a listed number or name.' "$fixture/invalid-helper"
choice=$(prompt_choice 'AUR helper options' yay paru yay <<< '' 2> "$fixture/yay-default")
[[ $choice == yay ]]
grep -Fq 'Select number or name [1-${#options[@]}] (Enter:' "$repo/platforms/archlinux/kmos-archlinux-install.sh"

pacman() { [[ $1 == -Si && $2 == impala ]]; }
KDE_PROFILE=full
collect_desktop_config <<< $'\n1\nn' 2> "$fixture/desktop"
[[ $INSTALL_KDE == no && $DESKTOP_CHOICE_MADE == 1 ]]
grep -Fq 'Choose headless or KDE (required, no default)' "$fixture/desktop"
grep -Fq '|- 1) Headless (no KDE)' "$fixture/desktop"
grep -Fq 'Choose 1 for headless or 2 for KDE. Enter alone does not select KDE.' "$fixture/desktop"

TARGET_DISK=/dev/fixture-disk
ROOT_PARTITION=/dev/fixture-root
BOOT_PARTITION=/dev/fixture-efi
BOOT_PARTITION_ACTION=reuse
CONFIRMED_DISK_ID=8:0
CONFIRMED_DISK_SIZE=10737418240
PRIMARY_USER=fixture-user
BOOT_MENU_CHOICE_MADE=1
run_plan() {
  FORMAT_APPROVED=0
  confirm_install_plan
}
if (run_plan <<< 'EXIT') > /dev/null 2> "$fixture/exit"; then exit 1; fi
grep -Fq 'Install cancelled.' "$fixture/exit"
[[ $FORMAT_APPROVED == 0 ]]
if (run_plan </dev/null) > /dev/null 2> "$fixture/eof"; then exit 1; fi
grep -Fq 'no filesystem was formatted.' "$fixture/eof"
if (BOOT_MENU_CHOICE_MADE=0; run_plan <<< FORMAT) > /dev/null 2> "$fixture/blocked"; then exit 1; fi
grep -Fq 'cannot approve formatting' "$fixture/blocked"
run_plan <<< $'format\nFORMAT' > /dev/null 2> "$fixture/approved"
[[ $FORMAT_APPROVED == 1 ]]
grep -Fq 'Type FORMAT exactly' "$fixture/approved"
grep -Fq 'The root partition will be formatted.' "$fixture/approved"
grep -Fq 'will NOT be formatted' "$fixture/approved"
header=$(grep -nF 'Review install plan' "$fixture/approved" | head -1 | cut -d: -f1)
detail=$(grep -nF 'Disk identity' "$fixture/approved" | head -1 | cut -d: -f1)
warning=$(grep -nF 'Destructive action' "$fixture/approved" | head -1 | cut -d: -f1)
((header < detail && detail < warning))
grep -Fq "read -r -p 'Type FORMAT to continue or EXIT to cancel: ' confirm" "$repo/platforms/archlinux/kmos-archlinux-install.sh"
grep -Fq "read -r -p 'Type EREASE to force this EFI format, or anything else to cancel: ' confirm" "$repo/platforms/archlinux/kmos-archlinux-install.sh"

BOOT_PARTITION_ACTION=format
run_plan <<< FORMAT > /dev/null 2> "$fixture/format"
grep -Fq 'The boot partition will be formatted as FAT32.' "$fixture/format"
! grep -Fq 'will NOT be formatted' "$fixture/format"
printf 'Arch installer choices and approval gates: OK (mocked only).\n'
