#!/bin/bash
# kmos KDE Post Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd)"
MOUNT_POINT="/mnt"
PANEL_HOOKS_ONLY=no
KDE_PROFILE="${kmos_kde_profile:-full}"
INSTALL_AUR="${kmos_INSTALL_AUR:-yes}"
AUR_HELPER="${kmos_AUR_HELPER:-paru}"
REPO_AUR_DIR="$REPO_ROOT/packages/aur"
ASSET_WALLPAPER="$REPO_ROOT/assets/wallpapers/kmos-wallpaper.png"
ASSET_COLOR_SCHEME="$REPO_ROOT/assets/color-schemes/kmos.colors"
ASSET_KONSOLE_COLOR_SCHEME="$REPO_ROOT/assets/konsole/kmos.colorscheme"
ASSET_KONSOLE_PROFILE="$REPO_ROOT/assets/konsole/kmos.profile"
ASSET_KONSOLE_DOLPHIN_PROFILE="$REPO_ROOT/assets/konsole/kmos-dolphin.profile"
ASSET_YAKUAKE_SKIN_DIR="$REPO_ROOT/assets/yakuake/monochrome"
ASSET_KATE_THEME_AYU="$REPO_ROOT/assets/kate/kmos-ayu.theme"
ASSET_KATE_THEME_GITHUB="$REPO_ROOT/assets/kate/kmos-github.theme"
ASSET_AUR_PACKAGE_LIST="$REPO_AUR_DIR/aur-packages.kmos"
TARGET_WALLPAPER="/opt/kmos/assets/wallpapers/kmos-wallpaper.png"
TARGET_COLOR_SCHEME="/opt/kmos/assets/color-schemes/kmos.colors"
TARGET_KONSOLE_COLOR_SCHEME="/opt/kmos/assets/konsole/kmos.colorscheme"
TARGET_AUR_PACKAGE_LIST="/opt/kmos/assets/aur/aur-packages.kmos"
KAPPA_TYPE_API_BASE="https://api.github.com/repos/kamilomelo/kappa-type/contents/fonts"

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
      --disable-panel-hooks)
        PANEL_HOOKS_ONLY=yes
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

require_root() {
  ((EUID == 0)) && return
  command -v sudo >/dev/null 2>&1 || die "Root access is required, but sudo is not installed."
  log "Root access is needed for KDE configuration; sudo will prompt for your password."
  exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
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
ColorScheme=kmos
AccentColor=117,117,117
LastUsedCustomAccentColor=117,117,117

[KDE]
LookAndFeelPackage=org.kde.kmos.desktop
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
marker="${XDG_CONFIG_HOME:-$HOME/.config}/.kmos-colorscheme-applied"

if [ -f "$marker" ]; then
  exit 0
fi

# Only finish setting up an untouched KMOS default. Never switch a user's
# chosen scheme, including on subsequent logins after they change it.
if ! [ -f "$cfg" ] || ! command -v kreadconfig6 >/dev/null 2>&1 || \
    [ "$(kreadconfig6 --file "$cfg" --group General --key ColorScheme 2>/dev/null || true)" != kmos ]; then
  [ -d "${marker%/*}" ] || exit 0
  touch "$marker"
  exit 0
fi

command -v plasma-apply-colorscheme >/dev/null 2>&1 || exit 1
# Plasma 6 exits successfully without applying any colors when ColorScheme is
# already kmos. Applying the existing accent explicitly runs applyScheme even
# in that case. Check its resulting palette hash before writing our marker.
scheme="${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/kmos.colors"
[ -r "$scheme" ] || scheme=/usr/share/color-schemes/kmos.colors
[ -r "$scheme" ] || exit 1
expected_hash=$(sha1sum "$scheme")
expected_hash=${expected_hash%% *}
if ! plasma-apply-colorscheme --accent-color '#757575' >/dev/null 2>&1; then
  printf 'KMOS color application failed; will retry on the next KDE login.\n' >&2
  exit 1
fi
if [ "$(kreadconfig6 --file "$cfg" --group General --key ColorSchemeHash 2>/dev/null || true)" != "$expected_hash" ]; then
  printf 'KMOS color palette was not written; will retry on the next KDE login.\n' >&2
  exit 1
fi
touch "$marker"
EOF

  install -Dm0644 /dev/stdin "$target_desktop" <<EOF
[Desktop Entry]
Type=Application
Name=kmos color scheme
Exec=/usr/share/kmos/bin/kmos-apply-colorscheme.sh
OnlyShowIn=KDE;
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
ColorScheme=kmos
AccentColor=117,117,117
LastUsedCustomAccentColor=117,117,117

[KDE]
LookAndFeelPackage=org.kde.kmos.desktop
contrast=4
frameContrast=0.2
EOF
}

install_fresh_kmos_panel() {
  local stock="$MOUNT_POINT/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js"
  local template="$MOUNT_POINT/usr/share/plasma/layout-templates/org.kde.kmos.defaultPanel"
  local layout="$MOUNT_POINT/usr/share/plasma/look-and-feel/org.kde.kmos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
  local setup="$REPO_ROOT/assets/plasma/kmos-panel-setup.js"
  local plugin=""

  [[ -f "$stock" && ! -L "$stock" && -r "$setup" ]] || die 'Missing stock panel or KMOS setup; no panel defaults staged.'
  [[ $(grep -Fxc 'panel.addWidget("org.kde.plasma.kickoff")' "$stock") == 1 \
    && $(grep -Fxc 'panel.addWidget("org.kde.plasma.systemtray")' "$stock") == 1 \
    && $(grep -Fxc 'panel.addWidget("org.kde.plasma.digitalclock")' "$stock") == 1 \
    && $(grep -Fxc 'panel.addWidget("org.kde.plasma.showdesktop")' "$stock") == 1 ]] \
    || die 'Stock panel changed; refusing to guess at widget placement.'
  for plugin in org.kde.plasma.kickerdash org.kde.plasma.systemmonitor.kmos-cpu-gpu \
    org.kde.plasma.systemmonitor.kmos-mem org.kde.plasma.systemmonitor.kmos-disk \
    org.kde.plasma.systemmonitor.net; do
    [[ -r "$MOUNT_POINT/usr/share/plasma/plasmoids/$plugin/metadata.json" ]] \
      || die "Required KMOS panel widget is missing: $plugin"
  done
  [[ ! -e "$template" && ! -L "$template" && ! -e "$layout" && ! -L "$layout" ]] \
    || die 'KMOS panel defaults already exist; refusing to overwrite them.'

  install -Dm0644 /dev/stdin "$template/metadata.json" <<'EOF'
{
    "KPackageStructure": "Plasma/LayoutTemplate",
    "KPlugin": {
        "Id": "org.kde.kmos.defaultPanel",
        "Name": "KMOS default panel",
        "Description": "Fresh KMOS panel based on the KDE default panel",
        "License": "MIT",
        "Version": "1.0"
    },
    "X-Plasma-ContainmentCategories": ["panel"]
}
EOF
  # Preserve KDE's panel geometry, task manager, tray and conditional input
  # method. Substitute only the May 2026 KMOS launcher and widget sequence.
  awk '
    $0 == "panel.addWidget(\"org.kde.plasma.kickoff\")" {
      print "panel.addWidget(\"org.kde.plasma.kickerdash\")"; next
    }
    $0 == "panel.addWidget(\"org.kde.plasma.digitalclock\")" {
      print "panel.addWidget(\"org.kde.plasma.systemmonitor.kmos-cpu-gpu\")"
      print "panel.addWidget(\"org.kde.plasma.systemmonitor.kmos-mem\")"
      print "panel.addWidget(\"org.kde.plasma.systemmonitor.kmos-disk\")"
      print "panel.addWidget(\"org.kde.plasma.systemmonitor.net\")"
      print "panel.addWidget(\"org.kde.plasma.digitalclock\")"
      print "panel.addWidget(\"org.kde.plasma.digitalclock\")"
      print "panel.addWidget(\"org.kde.plasma.digitalclock\")"; next
    }
    {print}
  ' "$stock" | install -Dm0644 /dev/stdin "$template/contents/layout.js"
  cat "$setup" >> "$template/contents/layout.js"

  # Plasma reads the active global theme from [KDE] LookAndFeelPackage and
  # executes this layout only if the account has no existing Plasma layout.
  install -Dm0644 /dev/stdin "$layout" <<'EOF'
loadTemplate("org.kde.kmos.defaultPanel")

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}
EOF
  success 'KMOS panel staged for new Plasma layouts only; existing panels were not changed.'
}

write_konsole_profile() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[Appearance]
ColorScheme=kmos
Font=Kappa Mono,11,-1,5,50,0,0,0,0,0
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
Font=Kappa Mono,11,-1,5,50,0,0,0,0,0
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
Font=Kappa Mono,11,-1,5,50,0,0,0,0,0
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

set_kwinrc_value() {
  local target="$1"
  local group="$2"
  local key="$3"
  local value="$4"

  install -d "$(dirname "$target")"
  arch-chroot "$MOUNT_POINT" kwriteconfig6 --file "$target" --group "$group" --key "$key" "$value"
}

set_kwinrc_value_for_user() {
  local username="$1"
  local target="$2"
  local group="$3"
  local key="$4"
  local value="$5"

  arch-chroot "$MOUNT_POINT" install -d -m 0755 "/home/$username/.config"
  arch-chroot "$MOUNT_POINT" runuser -u "$username" -- kwriteconfig6 --file "$target" --group "$group" --key "$key" "$value"
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

apply_color_scheme_defaults() {
  local home_dir=""
  local username=""
  local autostart_script="$MOUNT_POINT/usr/share/kmos/bin/kmos-apply-colorscheme.sh"
  local autostart_desktop="$MOUNT_POINT/etc/xdg/autostart/kmos-apply-colorscheme.desktop"

  [[ -r "$ASSET_COLOR_SCHEME" ]] || die "Missing color scheme asset: $ASSET_COLOR_SCHEME"

  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT$TARGET_COLOR_SCHEME"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/usr/share/color-schemes/KMOS.colors"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/usr/share/color-schemes/kmos.colors"
  install_lookandfeel_defaults
  write_color_scheme_autostart "$autostart_script" "$autostart_desktop"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/etc/skel/.local/share/color-schemes/KMOS.colors"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/etc/skel/.local/share/color-schemes/kmos.colors"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/root/.local/share/color-schemes/KMOS.colors"
  install -Dm0644 "$ASSET_COLOR_SCHEME" "$MOUNT_POINT/root/.local/share/color-schemes/kmos.colors"

  write_kdeglobals_defaults "$MOUNT_POINT/etc/xdg/kdeglobals"
  write_kdeglobals_defaults "$MOUNT_POINT/etc/skel/.config/kdeglobals"
  write_kdeglobals_defaults "$MOUNT_POINT/root/.config/kdeglobals"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      if [[ ! -e "$home_dir/.local/share/color-schemes/KMOS.colors" && ! -L "$home_dir/.local/share/color-schemes/KMOS.colors" ]]; then
        install -Dm0644 "$ASSET_COLOR_SCHEME" "$home_dir/.local/share/color-schemes/KMOS.colors"
      fi
      if [[ ! -e "$home_dir/.local/share/color-schemes/kmos.colors" && ! -L "$home_dir/.local/share/color-schemes/kmos.colors" ]]; then
        install -Dm0644 "$ASSET_COLOR_SCHEME" "$home_dir/.local/share/color-schemes/kmos.colors"
      fi
      if [[ ! -e "$home_dir/.config/kdeglobals" && ! -L "$home_dir/.config/kdeglobals" ]]; then
        write_kdeglobals_defaults "$home_dir/.config/kdeglobals"
      fi
      arch-chroot "$MOUNT_POINT" chown -R "$username:$username" "/home/$username/.config" "/home/$username/.local" 2>/dev/null || true
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

install_yakuake_autostart() {
  install -Dm0644 /dev/stdin "$MOUNT_POINT/etc/xdg/autostart/kmos-yakuake.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Yakuake
Comment=Launch Yakuake when the KDE session starts
Exec=yakuake
Terminal=false
OnlyShowIn=KDE;
X-GNOME-Autostart-enabled=false
EOF
}

apply_yakuake_defaults() {
  local home_dir=""
  local username=""

  install_yakuake_skin
  install_yakuake_autostart

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

apply_virtual_desktop_defaults() {
  local home_dir=""
  local username=""

  set_kwinrc_value "/etc/xdg/kwinrc" "Desktops" "Number" "2"
  set_kwinrc_value "/etc/xdg/kwinrc" "Desktops" "Rows" "2"
  set_kwinrc_value "/etc/xdg/kwinrc" "Windows" "RollOverDesktops" "true"

  set_kwinrc_value "/etc/skel/.config/kwinrc" "Desktops" "Number" "2"
  set_kwinrc_value "/etc/skel/.config/kwinrc" "Desktops" "Rows" "2"
  set_kwinrc_value "/etc/skel/.config/kwinrc" "Windows" "RollOverDesktops" "true"

  set_kwinrc_value "/root/.config/kwinrc" "Desktops" "Number" "2"
  set_kwinrc_value "/root/.config/kwinrc" "Desktops" "Rows" "2"
  set_kwinrc_value "/root/.config/kwinrc" "Windows" "RollOverDesktops" "true"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      set_kwinrc_value_for_user "$username" "/home/$username/.config/kwinrc" "Desktops" "Number" "2"
      set_kwinrc_value_for_user "$username" "/home/$username/.config/kwinrc" "Desktops" "Rows" "2"
      set_kwinrc_value_for_user "$username" "/home/$username/.config/kwinrc" "Windows" "RollOverDesktops" "true"
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "Virtual desktop defaults configured."
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

  if [[ -d "$REPO_ROOT/assets/sysmonitor" ]]; then
    install -d -m 0755 "$MOUNT_POINT/usr/share/plasma/plasmoids"
    cp -a "$REPO_ROOT/assets/sysmonitor/." "$MOUNT_POINT/usr/share/plasma/plasmoids/"
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
  local family=""
  local api_url=""
  local metadata=""
  local downloaded=0
  local legacy_font=""
  local -a families=(
    "kappa-text"
    "kappa-mark"
    "kappa-form"
    "kappa-mono"
    "kappa-spin"
  )

  install -d "$fonts_dir"

  find "$fonts_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -delete 2>/dev/null || true

  for family in "${families[@]}"; do
    api_url="$KAPPA_TYPE_API_BASE/$family/ttf?ref=main"
    metadata="$(curl -fsSL "$api_url")" || die "Could not fetch Kappa font metadata for $family."

    while IFS= read -r download_url; do
      [[ -n "$download_url" ]] || continue
      curl -fsSL "$download_url" -o "$fonts_dir/${download_url##*/}" || die "Could not download ${download_url##*/}."
      downloaded=1
    done < <(printf '%s\n' "$metadata" | grep -o 'https://raw.githubusercontent.com/[^"]*\.ttf')
  done

  (( downloaded == 1 )) || die "No Kappa fonts were downloaded."
  [[ -s "$fonts_dir/KappaMono-Regular.ttf" ]] || die 'Kappa Mono Regular was not downloaded; no valid terminal font is available.'

  for legacy_font in \
    ABeeZee-Regular.ttf \
    ABeeZee-Italic.ttf \
    MoreSugar-Thin.ttf \
    MoreSugar-Regular.ttf \
    MoreSugar-Extras.ttf \
    MoreSugar-Regular.otf \
    MoreSugar-Thin.otf \
    MoreSugar-Extras.otf \
    Comfortaa-wght.ttf
  do
    rm -f "$fonts_dir/$legacy_font"
  done

  find "$fonts_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -exec chmod 0644 {} +
  arch-chroot "$MOUNT_POINT" fc-cache -r >/dev/null 2>&1 || die 'Could not refresh font cache after installing Kappa fonts.'
  arch-chroot "$MOUNT_POINT" fc-match -f '%{family}\n' 'Kappa Mono' | head -n 1 | grep -Fqi 'Kappa Mono' \
    || die 'Kappa Mono is not visible to fontconfig in the installed system.'
  success "Kappa font families installed."
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

remove_legacy_kmos_font_packages() {
  local pkg=""
  local -a packages=(
    "gnu-free-fonts"
    "opendesktop-fonts"
    "otf-font-awesome"
    "ttf-hack-nerd"
    "ttf-mononoki-nerd"
    "ttf-comfortaa"
  )

  for pkg in "${packages[@]}"; do
    if arch-chroot "$MOUNT_POINT" pacman -Q "$pkg" >/dev/null 2>&1; then
      run_target_pacman_without_packagekit_hook "-Rdd --noconfirm $pkg" || warn "Could not remove legacy font package: $pkg"
    fi
  done
}

write_aur_installer_script() {
  local target="$1"

  install -Dm0755 /dev/stdin "$target" <<'EOF'
#!/bin/bash
set -Eeuo pipefail

list_file="/usr/share/kmos/aur/aur-packages.kmos"
pacman_wrapper="/usr/share/kmos/bin/kmos-pacman-nohooks"
aur_helper="${1:-paru}"
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
case "$aur_helper" in
  paru)
    paru --pacman "$pacman_wrapper" --noprovides -S --needed --noconfirm --skipreview "${packages[@]}"
    ;;
  yay)
    yay --pacman "$pacman_wrapper" -S --needed --noconfirm --answerclean None --answerdiff None "${packages[@]}"
    ;;
  *)
    printf 'Unknown AUR helper: %s\n' "$aur_helper" >&2
    exit 1
    ;;
esac
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
  local sudoers_file="$MOUNT_POINT/etc/sudoers.d/10-kmos-aur-helper"
  local group_list=""
  local -a packages=()

  [[ "$INSTALL_AUR" == "yes" ]] || return 0

  case "$AUR_HELPER" in
    paru|yay) ;;
    *) warn "Unknown AUR helper: $AUR_HELPER; skipping AUR package installation."; return 0 ;;
  esac

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
  if ! arch-chroot "$MOUNT_POINT" bash -lc "command -v '$AUR_HELPER' >/dev/null 2>&1"; then
    warn "$AUR_HELPER is not installed in the target system; skipping AUR package installation."
    return 0
  fi

  stage_aur_package_list
  write_pacman_nohooks_wrapper "$MOUNT_POINT/usr/share/kmos/bin/kmos-pacman-nohooks"
  install -Dm0440 /dev/stdin "$sudoers_file" <<EOF
$builder_user ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman, /usr/share/kmos/bin/kmos-pacman-nohooks
EOF

  write_aur_installer_script "$installer_script"

  if ! arch-chroot "$MOUNT_POINT" runuser -u "$builder_user" -- /usr/share/kmos/bin/kmos-install-aur-packages.sh "$AUR_HELPER"; then
    rm -f "$sudoers_file"
    warn "AUR package installation failed."
    return 0
  fi

  rm -f "$sudoers_file"
  success "AUR package set installed."
}

disable_legacy_panel_updates() {
  local updates="${MOUNT_POINT%/}/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates"
  local name marker path
  local -a names=(zz-kmos-kickerdash.js zz-kmos-panel-widgets.js zz-kmos-unpin-taskmanager.js)
  local -a markers=('panel.addWidget("org.kde.plasma.kickerdash")' 'function configureDigitalClock(widget' 'widget.writeConfig("launchers", "")')
  local index
  # Inspect every hook before moving any, so a modified file cannot leave a
  # half-disabled panel setup. Never replace an existing backup.
  for index in "${!names[@]}"; do
    name=${names[$index]}
    marker=${markers[$index]}
    path="$updates/$name"
    [[ -e "$path" || -L "$path" ]] || continue
    if [[ ! -f "$path" || -L "$path" ]] || ! grep -Fq "$marker" "$path"; then
      die "Existing panel hook differs from KMOS's generated file: $path. Preserve it and review manually."
    fi
    [[ ! -e "$path.kmos-disabled" && ! -L "$path.kmos-disabled" ]] \
      || die "Panel hook backup already exists: $path.kmos-disabled. Review before rerunning."
  done
  for index in "${!names[@]}"; do
    path="$updates/${names[$index]}"
    [[ -e "$path" ]] || continue
    mv -- "$path" "$path.kmos-disabled"
    warn "Disabled old KMOS panel hook; backup: $path.kmos-disabled"
  done
}

apply_post_tweaks() {
  # Never add, remove, reorder or unpin widgets. Plasma owns the panel.
  disable_legacy_panel_updates
  stage_repo_assets
  install_fresh_kmos_panel
  apply_splash_defaults
  apply_sddm_defaults
  apply_lockscreen_defaults
  apply_desktop_wallpaper_defaults
  apply_color_scheme_defaults
  apply_konsole_defaults
  apply_yakuake_defaults
  apply_dolphin_defaults
  apply_kate_defaults
  apply_virtual_desktop_defaults
  install_extra_fonts
  remove_noto_fonts
  remove_legacy_kmos_font_packages
  install_aur_packages
  record_profile
  success "KDE post-install hook executed."
}

main() {
  init_ui
  parse_args "$@"
  require_root "$@"
  verify_target
  if [[ "$PANEL_HOOKS_ONLY" == yes ]]; then
    disable_legacy_panel_updates
    success 'Old KMOS panel hooks disabled; personal Plasma layout was not changed.'
    return 0
  fi
  apply_post_tweaks
  final_success "KDE post-install stage complete."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
