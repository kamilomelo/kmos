#!/bin/bash
# kmos KDE Post Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd)"
MOUNT_POINT="/mnt"
KDE_PROFILE="${kmos_kde_profile:-full}"
INSTALL_AUR="${kmos_INSTALL_AUR:-yes}"
REPO_AUR_DIR="$REPO_ROOT/packages/aur"
ASSET_WALLPAPER="$REPO_ROOT/assets/wallpapers/kmos-wallpaper.png"
ASSET_COLOR_SCHEME="$REPO_ROOT/assets/color-schemes/kmos.colors"
ASSET_KONSOLE_COLOR_SCHEME="$REPO_ROOT/assets/konsole/kmos.colorscheme"
ASSET_KONSOLE_PROFILE="$REPO_ROOT/assets/konsole/kmos.profile"
ASSET_KONSOLE_DOLPHIN_PROFILE="$REPO_ROOT/assets/konsole/kmos-dolphin.profile"
ASSET_YAKUAKE_SKIN_DIR="$REPO_ROOT/assets/yakuake/monochrome"
ASSET_KATE_THEME_AYU="$REPO_ROOT/assets/kate/kmos-ayu.theme"
ASSET_KATE_THEME_GITHUB="$REPO_ROOT/assets/kate/kmos-github.theme"
ASSET_DASHBOARD_ICON="$REPO_ROOT/assets/icons/kmos.ico"
ASSET_MENU_HIDE_LIST="$REPO_ROOT/assets/menus/to-delete-from-menu.kmos"
ASSET_AUR_PACKAGE_LIST="$REPO_AUR_DIR/aur-packages.kmos"
ASSET_EXTRA_FONTS_DIR="$REPO_ROOT/assets/extra-fonts"
TARGET_WALLPAPER="/opt/kmos/assets/wallpapers/kmos-wallpaper.png"
TARGET_COLOR_SCHEME="/opt/kmos/assets/color-schemes/kmos.colors"
TARGET_KONSOLE_COLOR_SCHEME="/opt/kmos/assets/konsole/kmos.colorscheme"
TARGET_DASHBOARD_ICON="/opt/kmos/assets/icons/kmos.ico"
TARGET_AUR_PACKAGE_LIST="/opt/kmos/assets/aur/aur-packages.kmos"

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

  if [[ "${TERM:-}" == "linux" || "${ascii_ui:-0}" == "1" ]]; then
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

warn() {
  printf '%bWARNING:%b %s\n' "${UI_WARN}${UI_BOLD}" "$UI_RESET" "$*" >&2
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
LookAndFeelPackage=org.kde.kmos.desktop

[KDE]
contrast=4
frameContrast=0.2
EOF
}

write_color_scheme_autostart() {
  local target_script="$1"
  local target_desktop="$2"

  install -Dm0755 /dev/stdin "$target_script" <<'EOF'
#!/bin/sh
set -eu

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"

if [ -r "$cfg" ] && grep -q '^[[:space:]]*ColorScheme=KMOS$' "$cfg"; then
  exit 0
fi

if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
  plasma-apply-colorscheme KMOS >/dev/null 2>&1 || true
fi
EOF

  install -Dm0644 /dev/stdin "$target_desktop" <<EOF
[Desktop Entry]
Type=Application
Name=kmos color scheme
Exec=$target_script
OnlyShowIn=KDE;
X-GNOME-Autostart-enabled=false
NoDisplay=true
EOF
}

install_lookandfeel_defaults() {
  local target_theme_dir="$MOUNT_POINT/usr/share/plasma/look-and-feel/org.kde.kmos.desktop"

  install -d "$target_theme_dir/contents/defaults"

  install -Dm0644 /dev/stdin "$target_theme_dir/metadata.json" <<'EOF'
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Id": "org.kde.kmos.desktop",
        "Name": "kmos",
        "Description": "kmos look and feel defaults",
        "License": "MIT",
        "Category": "",
        "Version": "1.0"
    }
}
EOF

  install -Dm0644 /dev/stdin "$target_theme_dir/contents/defaults/kdeglobals" <<'EOF'
[General]
ColorScheme=KMOS
AccentColor=117,117,117
LastUsedCustomAccentColor=117,117,117
LookAndFeelPackage=org.kde.kmos.desktop

[KDE]
contrast=4
frameContrast=0.2
EOF
}

write_konsole_profile() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[Appearance]
ColorScheme=kmos
UseTransparency=true

[General]
Name=kmos
Parent=FALLBACK/
EOF
}

write_konsole_default_profile() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[Appearance]
ColorScheme=kmos
UseTransparency=true

[General]
Name=Default
Parent=FALLBACK/
EOF
}

write_konsole_dolphin_profile() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[Appearance]
ColorScheme=kmos
UseTransparency=false

[General]
Name=kmos-dolphin
Parent=FALLBACK/
EOF
}

write_konsole_rc() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[Desktop Entry]
DefaultProfile=kmos.profile

[UiSettings]
ColorScheme=kmos
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

[TerminalPanel]
Profile=kmos-dolphin.profile

[PreviewSettings]
Plugins=appimagethumbnail,audiothumbnail,blenderthumbnail,comicbookthumbnail,cursorthumbnail,directorythumbnail,djvuthumbnail,ebookthumbnail,exrthumbnail,ffmpegthumbs,fontthumbnail,glycin-heif,glycin-image-rs,glycin-jxl,glycin-svg,gsthumbnail,heif,imagethumbnail,jpegthumbnail,kraorathumbnail,mltpreview,mobithumbnail,opendocumentthumbnail,rawthumbnail,svgthumbnail,textthumbnail,windowsexethumbnail,windowsimagethumbnail
EOF
}

write_kate_rc() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[KTextEditor Renderer]
Schema=kmos-github
EOF
}

hide_desktop_entry() {
  local source="$1"
  local rel_path="${source#"$MOUNT_POINT/usr/share/applications/"}"
  local target="$MOUNT_POINT/usr/local/share/applications/$rel_path"

  install -Dm0644 "$source" "$target"
  if grep -q '^[[:space:]]*NoDisplay=' "$target"; then
    sed -i 's/^[[:space:]]*NoDisplay=.*/NoDisplay=true/' "$target"
  else
    printf '\nNoDisplay=true\n' >> "$target"
  fi

  if grep -q '^[[:space:]]*Hidden=' "$target"; then
    sed -i 's/^[[:space:]]*Hidden=.*/Hidden=true/' "$target"
  else
    printf 'Hidden=true\n' >> "$target"
  fi
}

write_kmenuedit_menu_overlay() {
  local target="$1"
  local name=""

  install -d "$(dirname "$target")"
  {
    printf '%s\n' '<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"'
    printf '%s\n' ' "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">'
    printf '%s\n' '<Menu>'
    printf '%s\n' '  <Name>Applications</Name>'
    printf '%s\n' '  <Exclude>'
    while IFS= read -r name; do
      name="${name%%#*}"
      name="${name#"${name%%[![:space:]]*}"}"
      name="${name%"${name##*[![:space:]]}"}"
      [[ -n "$name" ]] || continue
      case "$name" in
        *.desktop) printf '    <Filename>%s</Filename>\n' "$name" ;;
        *) printf '    <Filename>%s.desktop</Filename>\n' "$name" ;;
      esac
    done < "$ASSET_MENU_HIDE_LIST"
    printf '%s\n' '  </Exclude>'
    printf '%s\n' '</Menu>'
  } | install -Dm0644 /dev/stdin "$target"
}

refresh_menu_cache() {
  arch-chroot "$MOUNT_POINT" kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$MOUNT_POINT/usr/local/share/applications" >/dev/null 2>&1 || true
    update-desktop-database "$MOUNT_POINT/usr/share/applications" >/dev/null 2>&1 || true
  fi
}

apply_menu_hides() {
  local app_dir="$MOUNT_POINT/usr/share/applications"
  local desktop=""
  local matched=0
  local pattern=""
  local name=""
  local -a patterns=()

  [[ -d "$app_dir" ]] || return 0
  [[ -r "$ASSET_MENU_HIDE_LIST" ]] || die "Missing menu hide list asset: $ASSET_MENU_HIDE_LIST"

  write_kmenuedit_menu_overlay "$MOUNT_POINT/etc/xdg/menus/applications-kmenuedit.menu"

  while IFS= read -r name; do
    name="${name%%#*}"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    [[ -n "$name" ]] || continue
    case "$name" in
      *.desktop) patterns+=("$name") ;;
      *)
        patterns+=("$name.desktop")
        patterns+=("*$name*.desktop")
        ;;
    esac
  done < "$ASSET_MENU_HIDE_LIST"

  for pattern in "${patterns[@]}"; do
    for desktop in "$app_dir"/$pattern; do
      [[ -f "$desktop" ]] || continue
      hide_desktop_entry "$desktop"
      matched=1
    done
  done

  if ((matched == 1)); then
    success "Configured menu hides from asset list."
  else
    success "No matching desktop entries found for menu hide asset list."
  fi

  refresh_menu_cache
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
  local icon=""
  local -a theme_dirs=(
    "$MOUNT_POINT/usr/share/icons/breeze"
    "$MOUNT_POINT/usr/share/icons/breeze-dark"
  )
  local -a sizes=(16 22 24 32 64 96)

  [[ -r "$ASSET_DASHBOARD_ICON" ]] || die "Missing dashboard icon asset: $ASSET_DASHBOARD_ICON"

  install -Dm0644 "$ASSET_DASHBOARD_ICON" "$MOUNT_POINT$TARGET_DASHBOARD_ICON"
  install -Dm0644 "$ASSET_DASHBOARD_ICON" "$MOUNT_POINT/usr/share/icons/hicolor/scalable/apps/kmos.svg"
  install -Dm0644 "$ASSET_DASHBOARD_ICON" "$MOUNT_POINT/usr/share/icons/hicolor/scalable/apps/plasma-symbolic.svg"

  for icon in "${theme_dirs[@]}"; do
    for size in "${sizes[@]}"; do
      install -Dm0644 "$ASSET_DASHBOARD_ICON" "$icon/places/$size/start-here-kde.svg"
      install -Dm0644 "$ASSET_DASHBOARD_ICON" "$icon/places/$size/start-here-kde-symbolic.svg"
      install -Dm0644 "$ASSET_DASHBOARD_ICON" "$icon/places/$size/start-here-kde-plasma.svg"
      install -Dm0644 "$ASSET_DASHBOARD_ICON" "$icon/places/$size/start-here-kde-plasma-symbolic.svg"
    done
    install -Dm0644 "$ASSET_DASHBOARD_ICON" "$icon/apps/22/plasma-symbolic.svg"
    install -Dm0644 "$ASSET_DASHBOARD_ICON" "$icon/apps/24/plasma-symbolic.svg"
  done

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
            var dashboard = panel.addWidget("org.kde.plasma.kickerdash");
            if (dashboard) {
                dashboard.currentConfigGroup = ["General"];
                dashboard.writeConfig("icon", "start-here-kde");
                dashboard.writeConfig("Icon", "start-here-kde");
            }
            break;
        }
    }
}
EOF

  success "Application Dashboard staged as default launcher."
}

apply_taskmanager_unpin_defaults() {
  install -Dm0644 /dev/stdin "$MOUNT_POINT/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/zz-kmos-unpin-taskmanager.js" <<'EOF'
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

        if (widget.type === "org.kde.plasma.taskmanager" || widget.type === "org.kde.plasma.icontasks") {
            widget.currentConfigGroup = ["General"];
            widget.writeConfig("launchers", "");
        }
    }
}
EOF

  success "Task Manager launchers staged as unpinned."
}

apply_color_scheme_defaults() {
  local home_dir=""
  local username=""
  local autostart_script="$MOUNT_POINT/usr/share/kmos/bin/kmos-apply-colorscheme.sh"
  local autostart_desktop="$MOUNT_POINT/etc/xdg/autostart/kmos-apply-colorscheme.desktop"

  [[ -r "$ASSET_COLOR_SCHEME" ]] || die "Missing color scheme asset: $ASSET_COLOR_SCHEME"

  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT$TARGET_COLOR_SCHEME"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/usr/share/color-schemes/KMOS.colors"
  sed -i 's/^ColorScheme=kmos$/ColorScheme=KMOS/; s/^Name=kmos$/Name=KMOS/' "$MOUNT_POINT/usr/share/color-schemes/KMOS.colors"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/usr/share/color-schemes/kmos.colors"
  install_lookandfeel_defaults
  write_color_scheme_autostart "$autostart_script" "$autostart_desktop"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/etc/skel/.local/share/color-schemes/KMOS.colors"
  sed -i 's/^ColorScheme=kmos$/ColorScheme=KMOS/; s/^Name=kmos$/Name=KMOS/' "$MOUNT_POINT/etc/skel/.local/share/color-schemes/KMOS.colors"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/root/.local/share/color-schemes/KMOS.colors"
  sed -i 's/^ColorScheme=kmos$/ColorScheme=KMOS/; s/^Name=kmos$/Name=KMOS/' "$MOUNT_POINT/root/.local/share/color-schemes/KMOS.colors"

  write_kdeglobals_defaults "$MOUNT_POINT/etc/xdg/kdeglobals"
  write_kdeglobals_defaults "$MOUNT_POINT/etc/skel/.config/kdeglobals"
  write_kdeglobals_defaults "$MOUNT_POINT/root/.config/kdeglobals"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      write_kmenuedit_menu_overlay "$home_dir/.config/menus/applications-kmenuedit.menu"
      arch-chroot "$MOUNT_POINT" chown -R "$username:$username" "/home/$username/.config/menus" 2>/dev/null || true
      install -Dm0644 "$ASSET_COLOR_SCHEME" "$home_dir/.local/share/color-schemes/KMOS.colors"
      sed -i 's/^ColorScheme=kmos$/ColorScheme=KMOS/; s/^Name=kmos$/Name=KMOS/' "$home_dir/.local/share/color-schemes/KMOS.colors"
      write_kdeglobals_defaults "$home_dir/.config/kdeglobals"
      arch-chroot "$MOUNT_POINT" chown "$username:$username" "/home/$username/.config" "/home/$username/.config/kdeglobals" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "kmos color scheme installed and set as default."
}

apply_konsole_defaults() {
  local home_dir=""
  local username=""

  [[ -r "$ASSET_KONSOLE_COLOR_SCHEME" ]] || die "Missing Konsole color scheme asset: $ASSET_KONSOLE_COLOR_SCHEME"
  [[ -r "$ASSET_KONSOLE_PROFILE" ]] || die "Missing Konsole profile asset: $ASSET_KONSOLE_PROFILE"
  [[ -r "$ASSET_KONSOLE_DOLPHIN_PROFILE" ]] || die "Missing Konsole profile asset: $ASSET_KONSOLE_DOLPHIN_PROFILE"

  install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$MOUNT_POINT$TARGET_KONSOLE_COLOR_SCHEME"
  install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$MOUNT_POINT/usr/share/konsole/kmos.colorscheme"
  write_konsole_rc "$MOUNT_POINT/etc/xdg/konsolerc"
  install -Dm0644 "$ASSET_KONSOLE_PROFILE" "$MOUNT_POINT/etc/skel/.local/share/konsole/kmos.profile"
  install -Dm0644 "$ASSET_KONSOLE_DOLPHIN_PROFILE" "$MOUNT_POINT/etc/skel/.local/share/konsole/kmos-dolphin.profile"
  write_konsole_default_profile "$MOUNT_POINT/etc/skel/.local/share/konsole/Default.profile"
  install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$MOUNT_POINT/etc/skel/.local/share/konsole/kmos.colorscheme"
  write_konsole_rc "$MOUNT_POINT/etc/skel/.config/konsolerc"

  install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$MOUNT_POINT/root/.local/share/konsole/kmos.colorscheme"
  install -Dm0644 "$ASSET_KONSOLE_PROFILE" "$MOUNT_POINT/root/.local/share/konsole/kmos.profile"
  install -Dm0644 "$ASSET_KONSOLE_DOLPHIN_PROFILE" "$MOUNT_POINT/root/.local/share/konsole/kmos-dolphin.profile"
  write_konsole_default_profile "$MOUNT_POINT/root/.local/share/konsole/Default.profile"
  write_konsole_rc "$MOUNT_POINT/root/.config/konsolerc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      install -Dm0644 "$ASSET_KONSOLE_COLOR_SCHEME" "$home_dir/.local/share/konsole/kmos.colorscheme"
      install -Dm0644 "$ASSET_KONSOLE_PROFILE" "$home_dir/.local/share/konsole/kmos.profile"
      install -Dm0644 "$ASSET_KONSOLE_DOLPHIN_PROFILE" "$home_dir/.local/share/konsole/kmos-dolphin.profile"
      write_konsole_default_profile "$home_dir/.local/share/konsole/Default.profile"
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

apply_kate_defaults() {
  local home_dir=""
  local username=""

  [[ -r "$ASSET_KATE_THEME_AYU" ]] || die "Missing Kate theme asset: $ASSET_KATE_THEME_AYU"
  [[ -r "$ASSET_KATE_THEME_GITHUB" ]] || die "Missing Kate theme asset: $ASSET_KATE_THEME_GITHUB"

  install -Dm0644 "$ASSET_KATE_THEME_AYU" "$MOUNT_POINT/usr/share/org.kde.syntax-highlighting/themes/kmos-ayu.theme"
  install -Dm0644 "$ASSET_KATE_THEME_GITHUB" "$MOUNT_POINT/usr/share/org.kde.syntax-highlighting/themes/kmos-github.theme"
  install -Dm0644 "$ASSET_KATE_THEME_AYU" "$MOUNT_POINT/opt/kmos/assets/kate/kmos-ayu.theme"
  install -Dm0644 "$ASSET_KATE_THEME_GITHUB" "$MOUNT_POINT/opt/kmos/assets/kate/kmos-github.theme"

  write_kate_rc "$MOUNT_POINT/etc/skel/.config/katerc"
  write_kate_rc "$MOUNT_POINT/root/.config/katerc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      install -Dm0644 "$ASSET_KATE_THEME_AYU" "$home_dir/.local/share/org.kde.syntax-highlighting/themes/kmos-ayu.theme"
      install -Dm0644 "$ASSET_KATE_THEME_GITHUB" "$home_dir/.local/share/org.kde.syntax-highlighting/themes/kmos-github.theme"
      write_kate_rc "$home_dir/.config/katerc"
      arch-chroot "$MOUNT_POINT" chown -R "$username:$username" "/home/$username/.local" "/home/$username/.config/katerc" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "Kate themes installed and kmos-github set as default."
}

record_profile() {
  install -Dm0644 /dev/stdin "$MOUNT_POINT/usr/share/kmos/kde-profile" <<EOF
$KDE_PROFILE
EOF
}

stage_repo_assets() {
  if [[ -d "$REPO_ROOT/assets" ]]; then
    install -d -m 0755 "$MOUNT_POINT/opt/kmos/assets"
    cp -a "$REPO_ROOT/assets/." "$MOUNT_POINT/opt/kmos/assets/"
  fi
}

read_package_list_file() {
  local list_file="$1"
  local line=""

  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line"
  done < "$list_file"
}

get_aur_builder_user() {
  local username=""
  local uid=""
  local home=""

  while IFS=: read -r username _ uid _ _ home _; do
    [[ "$uid" =~ ^[0-9]+$ ]] || continue
    ((uid >= 1000)) || continue
    [[ "$home" == /home/* ]] || continue
    [[ -d "$MOUNT_POINT$home" ]] || continue
    printf '%s\n' "$username"
    return 0
  done < "$MOUNT_POINT/etc/passwd"

  return 1
}

stage_aur_package_list() {
  [[ -r "$ASSET_AUR_PACKAGE_LIST" ]] || die "Missing AUR package list asset: $ASSET_AUR_PACKAGE_LIST"

  install -Dm0644 "$ASSET_AUR_PACKAGE_LIST" "$MOUNT_POINT/usr/share/kmos/aur/aur-packages.kmos"
  install -Dm0644 "$ASSET_AUR_PACKAGE_LIST" "$MOUNT_POINT$TARGET_AUR_PACKAGE_LIST"
}

run_target_pacman_without_packagekit_hook() {
  local pacman_cmd="$1"
  local hookdir="/var/cache/kmos/empty-hooks"

  arch-chroot "$MOUNT_POINT" mkdir -p "$hookdir"
  arch-chroot "$MOUNT_POINT" bash -lc "pacman --disable-download-timeout --hookdir '$hookdir' $pacman_cmd"
}

install_extra_fonts() {
  local fonts_dir="$MOUNT_POINT/usr/local/share/fonts/kmos"
  local asset=""
  local temp_dir=""

  [[ -d "$ASSET_EXTRA_FONTS_DIR" ]] || return 0
  install -d "$fonts_dir"

  for asset in "$ASSET_EXTRA_FONTS_DIR"/*; do
    [[ -e "$asset" ]] || continue
    case "$asset" in
      *.zip)
        temp_dir="$(mktemp -d)"
        if command -v bsdtar >/dev/null 2>&1; then
          bsdtar -xf "$asset" -C "$temp_dir"
        elif command -v unzip >/dev/null 2>&1; then
          unzip -oq "$asset" -d "$temp_dir"
        else
          warn "Skipping extra font archive without extractor support: ${asset##*/}"
          rm -rf "$temp_dir"
          continue
        fi
        case "${asset##*/}" in
          ABeeZee.zip)
            [[ -f "$temp_dir/ABeeZee-Regular.ttf" ]] && install -m 0644 "$temp_dir/ABeeZee-Regular.ttf" "$fonts_dir/ABeeZee-Regular.ttf"
            [[ -f "$temp_dir/ABeeZee-Italic.ttf" ]] && install -m 0644 "$temp_dir/ABeeZee-Italic.ttf" "$fonts_dir/ABeeZee-Italic.ttf"
            ;;
          more_sugar.zip)
            [[ -f "$temp_dir/MoreSugar-Thin.ttf" ]] && install -m 0644 "$temp_dir/MoreSugar-Thin.ttf" "$fonts_dir/MoreSugar-Thin.ttf"
            [[ -f "$temp_dir/MoreSugar-Regular.ttf" ]] && install -m 0644 "$temp_dir/MoreSugar-Regular.ttf" "$fonts_dir/MoreSugar-Regular.ttf"
            [[ -f "$temp_dir/MoreSugar-Extras.ttf" ]] && install -m 0644 "$temp_dir/MoreSugar-Extras.ttf" "$fonts_dir/MoreSugar-Extras.ttf"
            ;;
          *)
            find "$temp_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -exec install -m 0644 {} "$fonts_dir/" \;
            ;;
        esac
        rm -rf "$temp_dir"
        ;;
      *.ttf|*.otf|*.ttc)
        install -m 0644 "$asset" "$fonts_dir/${asset##*/}"
        ;;
    esac
  done

  find "$fonts_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -exec chmod 0644 {} +
  arch-chroot "$MOUNT_POINT" fc-cache -r >/dev/null 2>&1 || warn "Could not refresh font cache after installing extra fonts."
  success "Extra fonts installed from assets."
}

remove_noto_fonts() {
  if arch-chroot "$MOUNT_POINT" pacman -Q noto-fonts >/dev/null 2>&1; then
    run_target_pacman_without_packagekit_hook "-Rdd --noconfirm noto-fonts" || warn "Could not force-remove noto-fonts."
  fi

  rm -rf "$MOUNT_POINT/usr/share/fonts/noto"
  find "$MOUNT_POINT/usr/share/fonts" -type f \( -iname 'Noto*.ttf' -o -iname 'Noto*.otf' -o -iname 'Noto*.ttc' \) -delete 2>/dev/null || true
  arch-chroot "$MOUNT_POINT" fc-cache -r >/dev/null 2>&1 || warn "Could not refresh font cache after removing noto fonts."
  success "Noto fonts removed from package database and filesystem."
}

write_aur_installer_script() {
  local target="$1"

  install -Dm0755 /dev/stdin "$target" <<'EOF'
#!/bin/bash
set -Eeuo pipefail

list_file="/usr/share/kmos/aur/aur-packages.kmos"
pacman_wrapper="/usr/share/kmos/bin/kmos-pacman-nohooks"
packages=()
line=""

while IFS= read -r line; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n "$line" ]] || continue
  packages+=("$line")
done < "$list_file"

[[ ${#packages[@]} -gt 0 ]] || exit 0
paru --pacman "$pacman_wrapper" --noprovides -S --needed --noconfirm --skipreview "${packages[@]}"
EOF
}

write_pacman_nohooks_wrapper() {
  local target="$1"

  install -Dm0755 /dev/stdin "$target" <<'EOF'
#!/bin/bash
set -Eeuo pipefail
exec /usr/bin/pacman --disable-download-timeout --hookdir /var/cache/kmos/empty-hooks "$@"
EOF
}

install_aur_packages() {
  local builder_user=""
  local installer_script="$MOUNT_POINT/usr/share/kmos/bin/kmos-install-aur-packages.sh"
  local sudoers_file="$MOUNT_POINT/etc/sudoers.d/10-kmos-paru"
  local group_list=""
  local -a packages=()

  [[ "$INSTALL_AUR" == "yes" ]] || return 0

  [[ -r "$ASSET_AUR_PACKAGE_LIST" ]] || return 0
  mapfile -t packages < <(read_package_list_file "$ASSET_AUR_PACKAGE_LIST")
  [[ ${#packages[@]} -gt 0 ]] || return 0

  builder_user="$(get_aur_builder_user)" || {
    warn "Could not find a normal user for AUR package installation."
    return 0
  }
  group_list="$(arch-chroot "$MOUNT_POINT" id -nG "$builder_user" 2>/dev/null || true)"
  if [[ " $group_list " != *" wheel "* ]]; then
    warn "User $builder_user is not in wheel; skipping AUR package installation."
    return 0
  fi
  if ! arch-chroot "$MOUNT_POINT" bash -lc "command -v paru >/dev/null 2>&1"; then
    warn "paru is not installed in the target system; skipping AUR package installation."
    return 0
  fi

  stage_aur_package_list
  write_pacman_nohooks_wrapper "$MOUNT_POINT/usr/share/kmos/bin/kmos-pacman-nohooks"
  install -Dm0440 /dev/stdin "$sudoers_file" <<EOF
$builder_user ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman, /usr/share/kmos/bin/kmos-pacman-nohooks
EOF

  write_aur_installer_script "$installer_script"

  if ! arch-chroot "$MOUNT_POINT" runuser -u "$builder_user" -- /usr/share/kmos/bin/kmos-install-aur-packages.sh; then
    rm -f "$sudoers_file"
    warn "AUR package installation failed."
    return 0
  fi

  rm -f "$sudoers_file"
  success "AUR package set installed."
}

apply_post_tweaks() {
  stage_repo_assets
  apply_splash_defaults
  apply_sddm_defaults
  apply_lockscreen_defaults
  apply_desktop_wallpaper_defaults
  apply_application_dashboard_defaults
  apply_taskmanager_unpin_defaults
  apply_color_scheme_defaults
  apply_konsole_defaults
  apply_yakuake_defaults
  apply_dolphin_defaults
  apply_kate_defaults
  apply_menu_hides
  install_extra_fonts
  remove_noto_fonts
  install_aur_packages
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
