#!/usr/bin/env bash
# Offline GRUB policy tests: no real partition, bootloader or NVRAM is changed.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"
MOUNT_POINT="$fixture/target"
BOOTNEXT_MODULE=/usr/lib/grub/x86_64-efi/efibootnext.mod
mkdir -p "$MOUNT_POINT/etc/default" "$MOUNT_POINT/etc/grub.d" "$MOUNT_POINT/boot/grub" "$fixture/bin"
printf '#GRUB_DISABLE_OS_PROBER=false\nGRUB_DISABLE_RECOVERY=false\n' > "$MOUNT_POINT/etc/default/grub"
printf '#!/bin/sh\n' > "$MOUNT_POINT/etc/grub.d/30_uefi-firmware"
chmod +x "$MOUNT_POINT/etc/grub.d/30_uefi-firmware"
printf '#!/bin/sh\n# all-firmware generator\n' > "$MOUNT_POINT/etc/grub.d/31_efi_bootnext"
chmod +x "$MOUNT_POINT/etc/grub.d/31_efi_bootnext"
cat > "$fixture/bin/efibootmgr" <<'EOF'
#!/bin/sh
if [ "$#" -gt 0 ]; then exit 99; fi
printf '%s\n' 'Boot0009* Windows Boot Manager' 'Boot0011  Boot Menu' 'Boot0013  Lenovo Diagnostics'
EOF
chmod +x "$fixture/bin/efibootmgr"
PATH="$fixture/bin:$PATH"
scan_windows_efi_loaders() { printf '/dev/winesp|ABCD-1234|8:9\n'; }
lsblk() { [[ "$1" == -dnro && "$2" == MAJ:MIN ]] && printf '8:9\n'; }
blkid() { printf 'ABCD-1234\n'; }
cat > "$fixture/core" <<'EOF'
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
cat > "$fixture/flood" <<'EOF'
### BEGIN /etc/grub.d/31_efi_bootnext ###
menuentry 'Lenovo Diagnostics (EFI BootNext)' { bootnext 0013; reboot; }
### END /etc/grub.d/31_efi_bootnext ###
EOF
build_fixture_menu() {
  local output=$1 name
  cat "$fixture/core" > "$output"
  for name in 40_kmos_boot_menu 41_kmos_windows; do
    if [[ -x "$MOUNT_POINT/etc/grub.d/$name" ]]; then
      {
        printf '### BEGIN /etc/grub.d/%s ###\n' "$name"
        "$MOUNT_POINT/etc/grub.d/$name"
        printf '### END /etc/grub.d/%s ###\n' "$name"
      } >> "$output"
    fi
  done
}

# The ISO does not have the BootNext module. This must not stop installation.
BOOTNEXT_MODULE="$fixture/missing/efibootnext.mod"
collect_krub_config <<< ''
[[ "$INCLUDE_WINDOWS" == no && "$BOOT_MENU_CHOICE_MADE" == 1 && "$FIRMWARE_BOOT_MENU_ID" == 0011 ]]
configure_krub_menu_policy
grep -qx 'GRUB_DISABLE_OS_PROBER=true' "$MOUNT_POINT/etc/default/grub"
grep -qx 'export GRUB_DISABLE_BOOTNEXT=true' "$MOUNT_POINT/etc/default/grub"
[[ ! -x "$MOUNT_POINT/etc/grub.d/31_efi_bootnext" ]]
[[ $(bash -c '. "$1"; printenv GRUB_DISABLE_BOOTNEXT' _ "$MOUNT_POINT/etc/default/grub") == true ]]
write_boot_menu_krub_entry
[[ "$FIRMWARE_BOOT_MENU_ENABLED" == no ]]
build_fixture_menu "$fixture/arch-only"
verify_krub_menu_policy "$fixture/arch-only"

# If the target GRUB has the module, add exactly its Boot Menu entry.
mkdir -p "$MOUNT_POINT${BOOTNEXT_MODULE%/*}"
touch "$MOUNT_POINT$BOOTNEXT_MODULE"
write_boot_menu_krub_entry
[[ "$FIRMWARE_BOOT_MENU_ENABLED" == yes ]]
grep -q 'if bootnext 0011; then' "$MOUNT_POINT/etc/grub.d/40_kmos_boot_menu"
build_fixture_menu "$fixture/with-boot-menu"
verify_krub_menu_policy "$fixture/with-boot-menu"

# Windows does not require the module, and only its verified EFI loader is
# chainloaded. It must not use os-prober or select other BootNext entries.
collect_krub_config <<< 'y'
[[ "$INCLUDE_WINDOWS" == yes && "$WINDOWS_BOOT_PARTITION" == /dev/winesp && "$WINDOWS_BOOT_UUID" == ABCD-1234 ]]
write_windows_krub_entry
grep -q 'chainloader /EFI/Microsoft/Boot/bootmgfw.efi' "$MOUNT_POINT/etc/grub.d/41_kmos_windows"
build_fixture_menu "$fixture/with-windows"
verify_krub_menu_policy "$fixture/with-windows"
if command -v grub-script-check >/dev/null 2>&1; then
  grub-script-check "$fixture/with-windows"
fi
[[ $(grep -c '^[[:space:]]*menuentry ' "$fixture/with-windows") == 5 ]]
cat "$fixture/with-windows" "$fixture/flood" > "$fixture/extra"
if (verify_krub_menu_policy "$fixture/extra") > "$fixture/extra-log" 2>&1; then
  printf 'Unexpected firmware entries were accepted.\n' >&2; exit 1
fi

# A generator claiming to add the firmware flood is an error even if its
# staged output looks normal. It must not replace an existing GRUB config.
INCLUDE_WINDOWS=no
rm "$MOUNT_POINT/etc/grub.d/40_kmos_boot_menu" "$MOUNT_POINT/etc/grub.d/41_kmos_windows"
FIRMWARE_BOOT_MENU_ENABLED=no
printf 'previous bootable menu\n' > "$MOUNT_POINT/boot/grub/grub.cfg"
verify_krub_mounts() { :; }
arch-chroot() {
  if [[ "$2" == grub-mkconfig ]]; then
    build_fixture_menu "$MOUNT_POINT${!#}"
    printf '%s\n' 'Adding boot menu entry for EFI BootNext: Lenovo Diagnostics' >&2
  fi
}
if (install_krub_bootloader) > "$fixture/unapproved" 2>&1; then
  printf 'Unapproved generator activated a new menu.\n' >&2; exit 1
fi
grep -q 'An unapproved GRUB generator ran' "$fixture/unapproved"
[[ $(cat "$MOUNT_POINT/boot/grub/grub.cfg") == 'previous bootable menu' ]]
printf 'krub three fixed entries; optional Boot Menu and Windows (mocked): OK.\n'
