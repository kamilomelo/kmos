#!/usr/bin/env bash
# Offline GRUB menu-policy tests; no EFI or installed bootloader is touched.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"
MOUNT_POINT="$fixture/target"
mkdir -p "$MOUNT_POINT/etc/default" "$MOUNT_POINT/etc/grub.d" "$MOUNT_POINT/boot/grub"
printf '#GRUB_DISABLE_OS_PROBER=false\nGRUB_DISABLE_RECOVERY=false\n' > "$MOUNT_POINT/etc/default/grub"
printf '#!/bin/sh\n' > "$MOUNT_POINT/etc/grub.d/30_uefi-firmware"
chmod 755 "$MOUNT_POINT/etc/grub.d/30_uefi-firmware"
cat > "$MOUNT_POINT/etc/grub.d/41_windows" <<'EOF'
#!/bin/sh
menuentry "Windows Boot Manager" { :; }
EOF
detect_other_os_candidate() { return 1; }

collect_krub_config <<< '1'
[[ "$ENABLE_OS_PROBER" == no && "$BOOT_MENU_CHOICE_MADE" == 1 ]]
configure_krub_menu_policy
grep -qx 'GRUB_DISABLE_OS_PROBER=true' "$MOUNT_POINT/etc/default/grub"
grep -qx 'GRUB_DISABLE_RECOVERY=true' "$MOUNT_POINT/etc/default/grub"
[[ ! -x "$MOUNT_POINT/etc/grub.d/30_uefi-firmware" ]]
[[ ! -e "$MOUNT_POINT/etc/grub.d/41_windows" && -f "$MOUNT_POINT/etc/grub.d/41_windows.kmos-disabled" ]]
cat > "$MOUNT_POINT/boot/grub/grub.cfg" <<'EOF'
### BEGIN /etc/grub.d/10_linux ###
menuentry 'Arch Linux' --class arch { linux /vmlinuz-linux }
submenu 'Advanced options for Arch Linux' {
  menuentry 'Arch Linux, with Linux linux (fallback initramfs)' { linux /vmlinuz-linux }
}
### END /etc/grub.d/10_linux ###
EOF
verify_krub_menu_policy "$MOUNT_POINT/boot/grub/grub.cfg"
cat >> "$MOUNT_POINT/boot/grub/grub.cfg" <<'EOF'
### BEGIN /etc/grub.d/30_os-prober ###
menuentry 'Windows Boot Manager' { chainloader /EFI/Microsoft/Boot/bootmgfw.efi }
EOF
if (verify_krub_menu_policy "$MOUNT_POINT/boot/grub/grub.cfg") > "$fixture/extra" 2>&1; then
  printf 'Other-OS entry accepted after KMOS-only choice.\n' >&2; exit 1
fi
grep -q 'Unexpected krub entry' "$fixture/extra"
sed -i '/### BEGIN \/etc\/grub.d\/30_os-prober ###/,$d' "$MOUNT_POINT/boot/grub/grub.cfg"
printf "  menuentry 'Arch Linux (recovery mode)' { linux /vmlinuz-linux }\n" >> "$MOUNT_POINT/boot/grub/grub.cfg"
if (verify_krub_menu_policy "$MOUNT_POINT/boot/grub/grub.cfg") > "$fixture/recovery" 2>&1; then
  printf 'Recovery entry accepted after KMOS-only choice.\n' >&2; exit 1
fi
grep -q 'Unexpected krub entry' "$fixture/recovery"
cat >> "$MOUNT_POINT/boot/grub/grub.cfg" <<'EOF'
### BEGIN /etc/grub.d/30_os-prober ###
menuentry 'Windows Boot Manager' { chainloader /EFI/Microsoft/Boot/bootmgfw.efi }
EOF
inspect_krub_menu "$MOUNT_POINT" > "$fixture/inspection" 2>&1
grep -q '30_os-prober.*Windows Boot Manager' "$fixture/inspection"
grep -q 'GRUB_DISABLE_OS_PROBER=true' "$fixture/inspection"
if (collect_krub_config <<< '') > "$fixture/blank" 2>&1; then
  printf 'Blank krub choice was accepted.\n' >&2; exit 1
fi
grep -q 'No krub menu choice received' "$fixture/blank"

# The explicit other-OS choice may enable probing; it must not silently run
# when the earlier answer was KMOS only.
collect_krub_config <<< '2'
[[ "$ENABLE_OS_PROBER" == yes && "$BOOT_MENU_CHOICE_MADE" == 1 ]]
configure_krub_menu_policy
grep -qx 'GRUB_DISABLE_OS_PROBER=false' "$MOUNT_POINT/etc/default/grub"

# Validation happens on a staged file. Unexpected entries must not overwrite
# an existing bootable grub.cfg or trigger an automatic reboot.
ENABLE_OS_PROBER=no
printf 'previous bootable menu\n' > "$MOUNT_POINT/boot/grub/grub.cfg"
verify_krub_mounts() { :; }
arch-chroot() {
  if [[ "$2" == grub-mkconfig ]]; then
    cat > "$MOUNT_POINT${!#}" <<'GRUB'
### BEGIN /etc/grub.d/10_linux ###
menuentry 'Arch Linux' { linux /vmlinuz-linux }
### BEGIN /etc/grub.d/30_os-prober ###
menuentry 'Another OS' { chainloader /EFI/Other/bootx64.efi }
GRUB
  fi
}
if (install_krub_bootloader) > "$fixture/not-activated" 2>&1; then
  printf 'Unwanted krub entries replaced the prior menu.\n' >&2; exit 1
fi
[[ $(cat "$MOUNT_POINT/boot/grub/grub.cfg") == 'previous bootable menu' ]]
grep -q 'KMOS-only krub menu contains additional entries' "$fixture/not-activated"
printf 'krub KMOS-only and other-OS choices enforce distinct menus (mocked).\n'
