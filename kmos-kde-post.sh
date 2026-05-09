#!/bin/bash
# KMOS KDE Post Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
MOUNT_POINT="/mnt"
KDE_PROFILE="${KMOS_KDE_PROFILE:-test}"
ASSET_WALLPAPER="$SCRIPT_DIR/assets/KM-R-wallpaper.png"
ASSET_COLOR_SCHEME="$SCRIPT_DIR/assets/color-schemes/KMOS.colors"
TARGET_WALLPAPER="/opt/kmos/assets/KM-R-wallpaper.png"
TARGET_COLOR_SCHEME="/opt/kmos/assets/color-schemes/KMOS.colors"

UI_RESET=""
UI_BOLD=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""
SUCCESS_ICON="▸"
FINAL_SUCCESS_ICON="✔"

init_ui() {
  if [[ -t 2 && "${TERM:-dumb}" != "dumb" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_INFO=$'\033[37m'
    UI_SUCCESS=$'\033[32m'
    UI_WARN=$'\033[33m'
    UI_DANGER=$'\033[31m'
  fi

  if [[ "${TERM:-}" == "linux" || "${ASCII_UI:-${KMOS_ASCII_UI:-0}}" == "1" ]]; then
    SUCCESS_ICON=">"
    FINAL_SUCCESS_ICON="OK"
  fi
}

log() {
  printf '%s\n' "$*" >&2
}

success() {
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

final_success() {
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$FINAL_SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

die() {
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        shift
        [[ $# -gt 0 ]] || die "--target requires a mount point."
        MOUNT_POINT="$1"
        ;;
      --profile)
        shift
        [[ $# -gt 0 ]] || die "--profile requires a value."
        KDE_PROFILE="$1"
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run this script as root."
}

verify_target() {
  findmnt -rn --mountpoint "$MOUNT_POINT" >/dev/null 2>&1 || die "$MOUNT_POINT is not mounted."
  [[ -d "$MOUNT_POINT/etc" ]] || die "$MOUNT_POINT does not look like an installed system."
}

write_ksplash_none() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[KSplash]
Engine=none
Theme=None
EOF
}

write_kdeglobals_defaults() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[General]
ColorScheme=KMOS
AccentColor=117,117,117
LastUsedCustomAccentColor=117,117,117

[KDE]
contrast=4
frameContrast=0.2
EOF
}

apply_splash_defaults() {
  local home_dir=""
  local username=""

  write_ksplash_none "$MOUNT_POINT/etc/xdg/ksplashrc"
  write_ksplash_none "$MOUNT_POINT/etc/skel/.config/ksplashrc"
  write_ksplash_none "$MOUNT_POINT/root/.config/ksplashrc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      write_ksplash_none "$home_dir/.config/ksplashrc"
      arch-chroot "$MOUNT_POINT" chown "$username:$username" "/home/$username/.config" "/home/$username/.config/ksplashrc" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "Splash screen disabled by default."
}

apply_sddm_defaults() {
  local source_theme_dir="/usr/share/sddm/themes/breeze"
  local target_theme_name="breeze-kmos"
  local target_theme_dir="$MOUNT_POINT/usr/share/sddm/themes/$target_theme_name"

  [[ -r "$ASSET_WALLPAPER" ]] || die "Missing wallpaper asset: $ASSET_WALLPAPER"
  [[ -d "$source_theme_dir" ]] || die "Missing SDDM Breeze theme: $source_theme_dir"

  install -Dm0644 "$ASSET_WALLPAPER" "$MOUNT_POINT$TARGET_WALLPAPER"
  rm -rf "$target_theme_dir"
  cp -a "$source_theme_dir" "$target_theme_dir"
  sed -i 's/fillMode: Image.PreserveAspectCrop/fillMode: Image.PreserveAspectFit/' "$target_theme_dir/Background.qml"

  install -Dm0644 /dev/stdin "$MOUNT_POINT/etc/sddm.conf.d/kmos-theme.conf" <<'EOF'
[Theme]
Current=breeze-kmos
EOF

  install -Dm0644 /dev/stdin "$target_theme_dir/theme.conf.user" <<EOF
[General]
type=image
background=$TARGET_WALLPAPER
color=#000000
EOF

  success "SDDM Breeze theme configured with black background and preserved proportions."
}

write_kscreenlocker_defaults() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<EOF
[Greeter][Wallpaper][org.kde.image][General]
Image=file://$TARGET_WALLPAPER
FillMode=1
Color=#000000
Blur=false
EOF
}

apply_lockscreen_defaults() {
  local home_dir=""
  local username=""

  write_kscreenlocker_defaults "$MOUNT_POINT/etc/xdg/kscreenlockerrc"
  write_kscreenlocker_defaults "$MOUNT_POINT/etc/skel/.config/kscreenlockerrc"
  write_kscreenlocker_defaults "$MOUNT_POINT/root/.config/kscreenlockerrc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      write_kscreenlocker_defaults "$home_dir/.config/kscreenlockerrc"
      arch-chroot "$MOUNT_POINT" chown "$username:$username" "/home/$username/.config" "/home/$username/.config/kscreenlockerrc" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "Lock screen wallpaper configured."
}

apply_desktop_wallpaper_defaults() {
  install -Dm0644 /dev/stdin "$MOUNT_POINT/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/zz-kmos-wallpaper.js" <<EOF
var allDesktops = desktops();
for (var i = 0; i < allDesktops.length; ++i) {
    var desktop = allDesktops[i];
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", "file://$TARGET_WALLPAPER");
    desktop.writeConfig("FillMode", "1");
    desktop.writeConfig("Color", "#000000");
    desktop.writeConfig("Blur", "false");
    desktop.reloadConfig();
}
EOF

  success "Desktop wallpaper defaults staged for first Plasma start."
}

apply_color_scheme_defaults() {
  local home_dir=""
  local username=""

  [[ -r "$ASSET_COLOR_SCHEME" ]] || die "Missing color scheme asset: $ASSET_COLOR_SCHEME"

  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT$TARGET_COLOR_SCHEME"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/usr/share/color-schemes/KMOS.colors"

  write_kdeglobals_defaults "$MOUNT_POINT/etc/xdg/kdeglobals"
  write_kdeglobals_defaults "$MOUNT_POINT/etc/skel/.config/kdeglobals"
  write_kdeglobals_defaults "$MOUNT_POINT/root/.config/kdeglobals"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      write_kdeglobals_defaults "$home_dir/.config/kdeglobals"
      arch-chroot "$MOUNT_POINT" chown "$username:$username" "/home/$username/.config" "/home/$username/.config/kdeglobals" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "KMOS color scheme installed and set as default."
}

record_profile() {
  install -Dm0644 /dev/stdin "$MOUNT_POINT/usr/share/kmos/kde-profile" <<EOF
$KDE_PROFILE
EOF
}

apply_post_tweaks() {
  apply_splash_defaults
  apply_sddm_defaults
  apply_lockscreen_defaults
  apply_desktop_wallpaper_defaults
  apply_color_scheme_defaults
  record_profile
  success "KDE post-install hook executed."
}

main() {
  init_ui
  parse_args "$@"
  require_root
  verify_target
  apply_post_tweaks
  final_success "KDE post-install stage complete."
}

main "$@"
