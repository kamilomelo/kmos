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
ASSET_KONSOLE_COLOR_SCHEME="$SCRIPT_DIR/assets/konsole/KMOS-Linux.colorscheme"
ASSET_YAKUAKE_SKIN_DIR="$SCRIPT_DIR/assets/yakuake/monochrome"
TARGET_WALLPAPER="/opt/kmos/assets/KM-R-wallpaper.png"
TARGET_COLOR_SCHEME="/opt/kmos/assets/color-schemes/KMOS.colors"
TARGET_KONSOLE_COLOR_SCHEME="/opt/kmos/assets/konsole/KMOS-Linux.colorscheme"

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

write_konsole_profile() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[Appearance]
ColorScheme=KMOS-Linux
UseTransparency=true

[General]
Name=kmos
Parent=FALLBACK/
EOF
}

write_konsole_rc() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[Desktop Entry]
DefaultProfile=kmos.profile

[UiSettings]
ColorScheme=KMOS-Linux
EOF
}

write_yakuake_rc() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[Appearance]
Skin=monochrome
SkinInstalledWithKns=false

[Window]
Width=80
Height=80
KeepOpen=false
EOF
}

write_dolphin_rc() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[General]
ShowPreview=true

[PreviewSettings]
Plugins=appimagethumbnail,audiothumbnail,blenderthumbnail,comicbookthumbnail,cursorthumbnail,directorythumbnail,djvuthumbnail,ebookthumbnail,exrthumbnail,ffmpegthumbs,fontthumbnail,glycin-heif,glycin-image-rs,glycin-jxl,glycin-svg,gsthumbnail,heif,imagethumbnail,jpegthumbnail,kraorathumbnail,mltpreview,mobithumbnail,opendocumentthumbnail,rawthumbnail,svgthumbnail,textthumbnail,windowsexethumbnail,windowsimagethumbnail
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
  local source_theme_dir="$MOUNT_POINT/usr/share/sddm/themes/breeze"
  local target_theme_name="breeze-kmos"
  local target_theme_dir="$MOUNT_POINT/usr/share/sddm/themes/$target_theme_name"

  [[ -r "$ASSET_WALLPAPER" ]] || die "Missing wallpaper asset: $ASSET_WALLPAPER"
  [[ -d "$source_theme_dir" ]] || die "Missing SDDM Breeze theme in target system: $source_theme_dir"

  install -Dm0644 "$ASSET_WALLPAPER" "$MOUNT_POINT$TARGET_WALLPAPER"
  rm -rf "$target_theme_dir"
  cp -a "$source_theme_dir" "$target_theme_dir"
  sed -i 's/fillMode: Image.PreserveAspectCrop/fillMode: Image.PreserveAspectFit/' "$target_theme_dir/Background.qml"
  sed -i '0,/visible: false/s//visible: true/' "$target_theme_dir/Background.qml"

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

apply_application_dashboard_defaults() {
  local layout_template="$MOUNT_POINT/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js"

  if [[ -f "$layout_template" ]]; then
    sed -i 's/org.kde.plasma.kickoff/org.kde.plasma.kickerdash/' "$layout_template"
  fi

  install -Dm0644 /dev/stdin "$MOUNT_POINT/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/zz-kmos-kickerdash.js" <<'EOF'
var panels = panelIds;
for (var i = 0; i < panels.length; ++i) {
    var panel = panelById(panels[i]);
    if (!panel || !panel.widgetIds) {
        continue;
    }

    var widgets = panel.widgetIds;
    for (var j = 0; j < widgets.length; ++j) {
        var widget = panel.widgetById(widgets[j]);
        if (!widget) {
            continue;
        }

        if (widget.type === "org.kde.plasma.kicker" || widget.type === "org.kde.plasma.kickoff") {
            panel.removeWidget(widget);
            panel.addWidget("org.kde.plasma.kickerdash");
            break;
        }
    }
}
EOF

  success "Application Dashboard staged as default launcher."
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

apply_konsole_defaults() {
  local home_dir=""
  local username=""

  [[ -r "$ASSET_KONSOLE_COLOR_SCHEME" ]] || die "Missing Konsole color scheme asset: $ASSET_KONSOLE_COLOR_SCHEME"

  install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$MOUNT_POINT$TARGET_KONSOLE_COLOR_SCHEME"
  install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$MOUNT_POINT/usr/share/konsole/KMOS-Linux.colorscheme"
  write_konsole_profile "$MOUNT_POINT/etc/skel/.local/share/konsole/kmos.profile"
  install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$MOUNT_POINT/etc/skel/.local/share/konsole/KMOS-Linux.colorscheme"
  write_konsole_rc "$MOUNT_POINT/etc/skel/.config/konsolerc"

  install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$MOUNT_POINT/root/.local/share/konsole/KMOS-Linux.colorscheme"
  write_konsole_profile "$MOUNT_POINT/root/.local/share/konsole/kmos.profile"
  write_konsole_rc "$MOUNT_POINT/root/.config/konsolerc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$home_dir/.local/share/konsole/KMOS-Linux.colorscheme"
      write_konsole_profile "$home_dir/.local/share/konsole/kmos.profile"
      write_konsole_rc "$home_dir/.config/konsolerc"
      arch-chroot "$MOUNT_POINT" chown -R "$username:$username" "/home/$username/.local" "/home/$username/.config/konsolerc" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "Konsole defaults configured."
}

install_yakuake_skin() {
  local target_system_skin="$MOUNT_POINT/usr/share/yakuake/skins/monochrome"
  local target_asset_skin="$MOUNT_POINT/opt/kmos/assets/yakuake/monochrome"

  [[ -d "$ASSET_YAKUAKE_SKIN_DIR" ]] || die "Missing Yakuake skin asset directory: $ASSET_YAKUAKE_SKIN_DIR"

  rm -rf "$target_system_skin" "$target_asset_skin"
  install -d "$MOUNT_POINT/usr/share/yakuake/skins" "$MOUNT_POINT/opt/kmos/assets/yakuake"
  cp -a "$ASSET_YAKUAKE_SKIN_DIR" "$target_system_skin"
  cp -a "$ASSET_YAKUAKE_SKIN_DIR" "$target_asset_skin"
}

apply_yakuake_defaults() {
  local home_dir=""
  local username=""

  install_yakuake_skin

  write_yakuake_rc "$MOUNT_POINT/etc/skel/.config/yakuakerc"
  write_yakuake_rc "$MOUNT_POINT/root/.config/yakuakerc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      write_yakuake_rc "$home_dir/.config/yakuakerc"
      arch-chroot "$MOUNT_POINT" chown "$username:$username" "/home/$username/.config/yakuakerc" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "Yakuake defaults configured."
}

apply_dolphin_defaults() {
  local home_dir=""
  local username=""

  write_dolphin_rc "$MOUNT_POINT/etc/xdg/dolphinrc"
  write_dolphin_rc "$MOUNT_POINT/etc/skel/.config/dolphinrc"
  write_dolphin_rc "$MOUNT_POINT/root/.config/dolphinrc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      write_dolphin_rc "$home_dir/.config/dolphinrc"
      arch-chroot "$MOUNT_POINT" chown "$username:$username" "/home/$username/.config/dolphinrc" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "Dolphin previews enabled by default."
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
  apply_application_dashboard_defaults
  apply_color_scheme_defaults
  apply_konsole_defaults
  apply_yakuake_defaults
  apply_dolphin_defaults
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
