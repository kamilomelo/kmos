#!/usr/bin/env bash
# Offline GRUB menu-policy tests; never touch a real EFI partition or NVRAM.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"
MOUNT_POINT="$fixture/target"
BOOTNEXT_MODULE="$fixture/live/efibootnext.mod"
mkdir -p "$MOUNT_POINT/etc/default" "$MOUNT_POINT/etc/grub.d" "$MOUNT_POINT/boot/grub" \
  "$MOUNT_POINT${BOOTNEXT_MODULE%/*}" "${BOOTNEXT_MODULE%/*}" "$fixture/bin"
touch "$BOOTNEXT_MODULE" "$MOUNT_POINT$BOOTNEXT_MODULE"
printf '#GRUB_DISABLE_OS_PROBER=false\nGRUB_DISABLE_RECOVERY=false\n' > "$MOUNT_POINT/etc/default/grub"
printf '#!/bin/sh\n' > "$MOUNT_POINT/etc/grub.d/30_uefi-firmware"
chmod +x "$MOUNT_POINT/etc/grub.d/30_uefi-firmware"
cat > "$fixture/bin/efibootmgr" <<'EOF'
#!/bin/sh
if [ "$#" -gt 0 ]; then exit 99; fi
printf '%s\n' 'Boot0000* Windows Boot Manager  HD(1,GPT,fixture)' 'Boot0001* krub' 'Boot0011  Boot Menu' 'Boot0013  Lenovo Diagnostics'
EOF
chmod +x "$fixture/bin/efibootmgr"
PATH="$fixture/bin:$PATH"

cat > "$fixture/generated" <<'EOF'
### BEGIN /etc/grub.d/00_header ###
set default=0
### END /etc/grub.d/00_header ###
### BEGIN /etc/grub.d/10_linux ###
menuentry 'Arch Linux' --class arch {
  linux /vmlinuz-linux
}
submenu 'Advanced options for Arch Linux' {
  menuentry 'Arch Linux, with Linux linux' {
    linux /vmlinuz-linux
  }
}
### END /etc/grub.d/10_linux ###
### BEGIN /etc/grub.d/30_uefi-firmware ###
if [ "$grub_platform" = "efi" ]; then
  menuentry 'UEFI Firmware Settings' $menuentry_id_option 'uefi-firmware' {
    fwsetup
  }
fi
### END /etc/grub.d/30_uefi-firmware ###
EOF
cp "$fixture/generated" "$fixture/no-bootmenu"
FIRMWARE_BOOT_MENU_ID=0011
write_boot_menu_krub_entry
boot_entry="$MOUNT_POINT/etc/grub.d/40_kmos_boot_menu"
[[ -x "$boot_entry" ]]
grep -q 'if bootnext 0011; then' "$boot_entry"
{
  printf '%s\n' '### BEGIN /etc/grub.d/40_kmos_boot_menu ###'
  "$boot_entry"
  printf '%s\n' '### END /etc/grub.d/40_kmos_boot_menu ###'
} >> "$fixture/generated"
cat > "$fixture/bootnext-flood" <<'EOF'
### BEGIN /etc/grub.d/31_efi_bootnext ###
menuentry 'Windows Boot Manager (EFI BootNext)' $menuentry_id_option 'efi-bootnext-0000' { bootnext 0000; reboot; }
menuentry 'krub (EFI BootNext)' $menuentry_id_option 'efi-bootnext-0001' { bootnext 0001; reboot; }
menuentry 'Lenovo Diagnostics (EFI BootNext)' $menuentry_id_option 'efi-bootnext-0013' { bootnext 0013; reboot; }
### END /etc/grub.d/31_efi_bootnext ###
EOF

collect_krub_config <<< '1'
[[ "$INCLUDE_WINDOWS" == no && "$BOOT_MENU_CHOICE_MADE" == 1 && "$FIRMWARE_BOOT_MENU_ID" == 0011 ]]
configure_krub_menu_policy
grep -qx 'GRUB_DISABLE_OS_PROBER=true' "$MOUNT_POINT/etc/default/grub"
grep -qx 'export GRUB_DISABLE_BOOTNEXT=true' "$MOUNT_POINT/etc/default/grub"
grep -qx 'GRUB_DISABLE_RECOVERY=true' "$MOUNT_POINT/etc/default/grub"
[[ -x "$MOUNT_POINT/etc/grub.d/30_uefi-firmware" ]]
[[ $(bash -c '. "$1"; printenv GRUB_DISABLE_BOOTNEXT' _ "$MOUNT_POINT/etc/default/grub") == true ]]
verify_krub_menu_policy "$fixture/generated"
if (verify_krub_menu_policy "$fixture/no-bootmenu") > "$fixture/missing-boot-menu" 2>&1; then
  printf 'A GRUB menu without Boot Menu was accepted.\n' >&2; exit 1
fi
cat "$fixture/generated" "$fixture/bootnext-flood" > "$fixture/extra"
if (verify_krub_menu_policy "$fixture/extra") > "$fixture/rejected" 2>&1; then
  printf 'Extra BootNext entries were accepted.\n' >&2; exit 1
fi
if (collect_krub_config <<< '') > "$fixture/blank" 2>&1; then
  printf 'Blank krub choice was accepted.\n' >&2; exit 1
fi
grep -q 'No krub menu choice received' "$fixture/blank"
cat > "$fixture/bin/efibootmgr" <<'EOF'
#!/bin/sh
printf '%s\n' 'Boot0000* Windows Boot Manager' 'Boot0013  Lenovo Diagnostics'
EOF
chmod +x "$fixture/bin/efibootmgr"
if (collect_krub_config <<< '1') > "$fixture/missing-firmware-menu" 2>&1; then
  printf 'Missing firmware Boot Menu passed the pre-GO check.\n' >&2; exit 1
fi
grep -q 'Exactly one firmware Boot Menu entry is required before GO' "$fixture/missing-firmware-menu"
cat > "$fixture/bin/efibootmgr" <<'EOF'
#!/bin/sh
printf '%s\n' 'Boot0000* Windows Boot Manager' 'Boot0011  Boot Menu' 'Boot0012  Boot Menu'
EOF
chmod +x "$fixture/bin/efibootmgr"
if (collect_krub_config <<< '1') > "$fixture/duplicate-firmware-menu" 2>&1; then
  printf 'Ambiguous firmware Boot Menu entries passed the pre-GO check.\n' >&2; exit 1
fi
grep -q 'Exactly one firmware Boot Menu entry is required before GO' "$fixture/duplicate-firmware-menu"
cat > "$fixture/bin/efibootmgr" <<'EOF'
#!/bin/sh
if [ "$#" -gt 0 ]; then exit 99; fi
printf '%s\n' 'Boot0000* Windows Boot Manager' 'Boot0011  Boot Menu' 'Boot0013  Lenovo Diagnostics'
EOF
chmod +x "$fixture/bin/efibootmgr"
cat "$fixture/generated" > "$fixture/extra-arch"
cat >> "$fixture/extra-arch" <<'EOF'
### BEGIN /etc/grub.d/10_linux ###
menuentry 'Another Arch Linux' { true; }
### END /etc/grub.d/10_linux ###
EOF
if (verify_krub_menu_policy "$fixture/extra-arch") > "$fixture/extra-arch-log" 2>&1; then
  printf 'Additional Arch entry was accepted.\n' >&2; exit 1
fi

collect_krub_config <<< '2'
[[ "$INCLUDE_WINDOWS" == yes && "$WINDOWS_BOOT_ID" == 0000 ]]
configure_krub_menu_policy
grep -qx 'export GRUB_DISABLE_BOOTNEXT=true' "$MOUNT_POINT/etc/default/grub"
write_windows_krub_entry
entry="$MOUNT_POINT/etc/grub.d/41_kmos_windows"
[[ -x "$entry" ]]
grep -q 'if bootnext 0000; then' "$entry"
grep -q 'insmod efibootnext' "$entry"
rm "$MOUNT_POINT$BOOTNEXT_MODULE"
if (write_windows_krub_entry) > "$fixture/target-missing-module" 2>&1; then
  printf 'Windows accepted without a target efibootnext module.\n' >&2; exit 1
fi
grep -q 'target GRUB package has no efibootnext module' "$fixture/target-missing-module"
touch "$MOUNT_POINT$BOOTNEXT_MODULE"
"$entry" > "$fixture/windows-section"
cat "$fixture/generated" > "$fixture/with-windows"
{
  printf '%s\n' '### BEGIN /etc/grub.d/41_kmos_windows ###'
  cat "$fixture/windows-section"
  printf '%s\n' '### END /etc/grub.d/41_kmos_windows ###'
} >> "$fixture/with-windows"
verify_krub_menu_policy "$fixture/with-windows"
if command -v grub-script-check >/dev/null 2>&1; then
  grub-script-check "$fixture/with-windows"
fi
[[ $(grep -c '^[[:space:]]*menuentry .*EFI BootNext' "$fixture/with-windows") == 2 ]]
[[ $(grep -c '^[[:space:]]*menuentry '\''Windows Boot Manager (EFI BootNext)'\''' "$fixture/with-windows") == 1 ]]
WINDOWS_BOOT_ID=9999
if (verify_krub_menu_policy "$fixture/with-windows") > "$fixture/wrong-id" 2>&1; then
  printf 'Wrong Windows firmware ID was accepted.\n' >&2; exit 1
fi
WINDOWS_BOOT_ID=0000

# A missing module is rejected before GO when Windows is selected.
BOOTNEXT_MODULE="$fixture/missing/efibootnext.mod"
if (collect_krub_config <<< '2') > "$fixture/missing-module" 2>&1; then
  printf 'Windows accepted without a live efibootnext module.\n' >&2; exit 1
fi
grep -q 'before GO' "$fixture/missing-module"
BOOTNEXT_MODULE="$fixture/live/efibootnext.mod"

# A failing GRUB generation must preserve the existing bootable menu.
INCLUDE_WINDOWS=no
rm "$boot_entry"
printf 'previous bootable menu\n' > "$MOUNT_POINT/boot/grub/grub.cfg"
verify_krub_mounts() { :; }
arch-chroot() {
  if [[ "$2" == grub-mkconfig ]]; then
    cat "$fixture/generated" "$fixture/bootnext-flood" > "$MOUNT_POINT${!#}"
  fi
}
if (install_krub_bootloader) > "$fixture/not-activated" 2>&1; then
  printf 'Unwanted BootNext entries replaced the previous menu.\n' >&2; exit 1
fi
[[ $(cat "$MOUNT_POINT/boot/grub/grub.cfg") == 'previous bootable menu' ]]
grep -q 'Existing menu preserved' "$fixture/not-activated"
rm "$boot_entry"

# Even if the config happens to contain only allowed entries, claiming to
# run the all-firmware generator must not be reported as a clean install.
arch-chroot() {
  if [[ "$2" == grub-mkconfig ]]; then
    cat "$fixture/generated" > "$MOUNT_POINT${!#}"
    printf '%s\n' 'Adding boot menu entry for EFI BootNext: Lenovo Diagnostics' >&2
  fi
}
if (install_krub_bootloader) > "$fixture/unapproved-generator" 2>&1; then
  printf 'All-firmware generator was silently accepted.\n' >&2; exit 1
fi
grep -q 'An unapproved GRUB generator ran' "$fixture/unapproved-generator"
[[ $(cat "$MOUNT_POINT/boot/grub/grub.cfg") == 'previous bootable menu' ]]
rm "$boot_entry"

# With the generator disabled, a normal generation can be installed and
# the old config is saved without altering any firmware boot entries.
arch-chroot() {
  if [[ "$2" == grub-mkconfig ]]; then
    cat "$fixture/generated" > "$MOUNT_POINT${!#}"
  fi
}
install_krub_bootloader > "$fixture/install" 2>&1
verify_krub_menu_policy "$MOUNT_POINT/boot/grub/grub.cfg"
grep -q 'previous bootable menu' "$MOUNT_POINT"/boot/grub/grub.cfg.kmos-before.*
printf 'krub Arch, Advanced, UEFI, Boot Menu and optional Windows: OK (mocked).\n'
