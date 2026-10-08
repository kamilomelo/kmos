#!/usr/bin/env bash
# Optional, reviewable v0.9 KDE defaults for a live KMOS headless -> KDE upgrade.
# Asset paths and config writers are supplied by the sourced KDE post script.
# shellcheck disable=SC2154
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode= user= home= backup_stamp= temp= changes=0 skipped=0 backup_bytes=0
system_backup_root=/var/backups/kmos
font_dir=/usr/local/share/fonts/kmos

usage() {
  cat <<'EOF'
Usage: ./platforms/archlinux/desktop/kde/kmos-kde-finish.sh --plan
       ./platforms/archlinux/desktop/kde/kmos-kde-finish.sh --apply

For the invoking user on an installed KMOS KDE system. --plan reads settings
only. --apply prompts before replacing EACH existing file and backs up approved
replacements. Missing defaults are added; panels, wallpaper choices, networking,
packages and other users' home files are not changed. System-wide defaults can
affect other KDE users who have no personal override. No automatic reboot.
EOF
}

fail() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

choose_user() {
  user="${1:-$(id -un)}"
  [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] || { fail 'Invalid user name.'; return 1; }
  local uid
  uid=$(id -u "$user") || return 1
  ((uid >= 1000)) || { fail 'Choose a regular account, not root.'; return 1; }
  home=$(getent passwd "$user" | cut -d: -f6)
  [[ "$home" == /home/* && -d "$home" && ! -L "$home" ]] || { fail 'User home must be a real directory under /home.'; return 1; }
}

check_system() {
  [[ -r /usr/share/kmos/kde-profile ]] || { fail 'KMOS KDE upgrade has not completed.'; return 1; }
  command -v pacman >/dev/null && pacman -Qq plasma-desktop >/dev/null 2>&1 || {
    fail 'Plasma is not installed.'; return 1;
  }
}

safe_path() {
  local path="$1"
  [[ ! -L "$path" ]] || { fail "Symlink refused: $path"; return 1; }
  path="${path%/*}"
  while [[ "$path" != / && -n "$path" ]]; do
    [[ ! -L "$path" ]] || { fail "Symlink parent refused: $path"; return 1; }
    path="${path%/*}"
  done
}

ask_replace() {
  local answer
  printf 'Replace %s? [y/N]: ' "$1" >&2
  read -r answer </dev/tty || return 1
  [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}

backup_file() {
  local scope="$1" path="$2" dir dest
  if [[ "$scope" == user ]]; then
    dir="$home/.local/share/kmos/backups/kde-$backup_stamp"
    safe_path "$dir"
    runuser -u "$user" -- mkdir -p -- "$dir" || return 1
    runuser -u "$user" -- chmod 0700 -- "$home/.local/share/kmos/backups" "$dir" || return 1
    dest="$dir/${path#"$home"/}"
    runuser -u "$user" -- mkdir -p -- "${dest%/*}" || return 1
  else
    dir="$system_backup_root/kde-$backup_stamp"
    safe_path "$dir"
    install -d -m 0700 "$dir" || return 1
    dest="$dir/${path#/}"
    install -d -m 0700 "${dest%/*}" || return 1
  fi
  [[ ! -e "$dest" && ! -L "$dest" ]] || { fail "Backup already exists: $dest"; return 1; }
  cp -p -- "$path" "$dest" || return 1
  printf 'Saved backup: %s\n' "$dest"
}

stage_file() {
  local scope="$1" target="$2" writer="$3" sourcefile status size
  ((changes+=1))
  sourcefile="$temp/candidate-$changes"
  safe_path "$target" || return 1
  "$writer" "$sourcefile" "$target" || return 1
  if [[ -e "$target" ]]; then
    [[ -f "$target" ]] || { fail "Not a regular file: $target"; return 1; }
    if cmp -s -- "$sourcefile" "$target"; then return 0; fi
    size=$(stat -c %s -- "$target")
    ((backup_bytes+=size))
    status="existing ($size bytes; approval and backup required)"
  else
    status='missing (will add without replacing a choice)'
  fi
  printf '%s: %s\n' "$status" "$target"
  [[ "$mode" == apply ]] || return 0
  if [[ -e "$target" ]]; then
    if ! ask_replace "$target"; then ((skipped+=1)); return 0; fi
    backup_file "$scope" "$target" || return 1
  fi
  install -Dm0644 "$sourcefile" "$target" || return 1
  [[ "$scope" != user ]] || chown "$user:" "$target"
}

write_sddm_theme() {
  cat > "$1" <<'EOF'
[Theme]
Current=breeze-kmos
EOF
}

write_sddm_background() {
  cat > "$1" <<'EOF'
[General]
type=image
background=/opt/kmos/assets/wallpapers/kmos-wallpaper.png
color=#000000
EOF
}

write_virtual_desktops() {
  if [[ -f "${2:-}" ]]; then
    command -v kwriteconfig6 >/dev/null || { fail 'kwriteconfig6 is required for safe KWin edits.'; return 1; }
    cp -- "$2" "$1" || return 1
    kwriteconfig6 --file "$1" --group Desktops --key Number 2 || return 1
    kwriteconfig6 --file "$1" --group Desktops --key Rows 2 || return 1
    kwriteconfig6 --file "$1" --group Windows --key RollOverDesktops true || return 1
    return 0
  fi
  cat > "$1" <<'EOF'
[Desktops]
Number=2
Rows=2

[Windows]
RollOverDesktops=true
EOF
}

write_kmos_konsole_color() { cp -- "$ASSET_KONSOLE_COLOR_SCHEME" "$1"; }
write_kmos_konsole_profile() { cp -- "$ASSET_KONSOLE_PROFILE" "$1"; }
write_kmos_dolphin_profile() { cp -- "$ASSET_KONSOLE_DOLPHIN_PROFILE" "$1"; }
write_kmos_kate_theme() { cp -- "$ASSET_KATE_THEME_GITHUB" "$1"; }
write_kmos_ayu_theme() { cp -- "$ASSET_KATE_THEME_AYU" "$1"; }
write_kmos_yakuake_autostart() {
  cat > "$1" <<'EOF'
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

stage_yakuake_skin() {
  local target=/usr/share/yakuake/skins/monochrome
  [[ -d "$ASSET_YAKUAKE_SKIN_DIR" ]] || return 0
  safe_path "$target" || return 1
  if [[ ! -e "$target" ]]; then
    printf 'missing: %s (KMOS Yakuake skin)\n' "$target"
    if [[ "$mode" == apply ]]; then cp -a -- "$ASSET_YAKUAKE_SKIN_DIR" "$target" || return 1; fi
  else
    [[ -d "$target" && ! -L "$target" ]] || { fail 'Existing Yakuake skin is not a regular directory.'; return 1; }
  fi
}

stage_fonts() {
  local family metadata url filename target count=0
  local fontdir="$font_dir"
  safe_path "$fontdir/KappaMono-Regular.ttf" || return 1
  if [[ -r "$fontdir/KappaMono-Regular.ttf" ]]; then return 0; fi
  printf 'missing: Kappa font families (download to %s without removing other fonts)\n' "$fontdir"
  [[ "$mode" != apply ]] && return 0
  command -v curl >/dev/null || { fail 'curl is needed to fetch Kappa; no package was installed.'; return 1; }
  command -v fc-cache >/dev/null || { fail 'fontconfig is needed for Kappa; no package was installed.'; return 1; }
  for family in kappa-text kappa-mark kappa-form kappa-mono kappa-spin; do
    metadata=$(curl -fsSL "https://api.github.com/repos/kamilomelo/kappa-type/contents/fonts/$family/ttf?ref=main") || return 1
    while IFS= read -r url; do
      [[ "$url" == "https://raw.githubusercontent.com/kamilomelo/kappa-type/"* ]] || continue
      filename="${url##*/}"
      [[ "$filename" =~ ^Kappa[a-zA-Z0-9_-]+\.ttf$ ]] || continue
      target="$fontdir/$filename"
      safe_path "$target" || return 1
      [[ ! -e "$target" ]] || continue
      curl -fsSL "$url" -o "$temp/$filename" || return 1
      [[ -s "$temp/$filename" ]] || { fail "Empty Kappa font: $filename"; return 1; }
      install -Dm0644 "$temp/$filename" "$target" || return 1
      ((count+=1))
    done < <(printf '%s\n' "$metadata" | grep -o 'https://raw.githubusercontent.com/[^"[:space:]]*\.ttf' || true)
  done
  [[ -s "$fontdir/KappaMono-Regular.ttf" ]] || { fail 'Kappa Mono Regular was not downloaded.'; return 1; }
  fc-cache -r >/dev/null || return 1
  fc-match -f '%{family}\n' 'Kappa Mono' | head -n 1 | grep -Fqi 'Kappa Mono' || {
    fail 'Kappa Mono is not visible to fontconfig.'; return 1;
  }
  printf 'Installed %s new Kappa fonts.\n' "$count"
}

stage_sddm_assets() {
  local source=/usr/share/sddm/themes/breeze target=/usr/share/sddm/themes/breeze-kmos config
  [[ -d "$source" && ! -L "$source" ]] || { fail 'SDDM Breeze theme is missing.'; return 1; }
  safe_path "$target" || return 1
  if [[ ! -e "$target" ]]; then
    printf 'missing: %s (KMOS copy of Breeze)\n' "$target"
    if [[ "$mode" == apply ]]; then
      cp -a -- "$source" "$target" || return 1
      sed -i 's/fillMode: Image.PreserveAspectCrop/fillMode: Image.PreserveAspectFit/' "$target/Background.qml" || return 1
      sed -i '0,/visible: false/s//visible: true/' "$target/Background.qml" || return 1
    fi
  else
    [[ -d "$target" && ! -L "$target" ]] || { fail 'Existing SDDM theme is not a regular directory.'; return 1; }
  fi
  stage_file system "$target/theme.conf.user" write_sddm_background || return 1
  for config in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
    [[ -f "$config" && "$config" != /etc/sddm.conf.d/kmos-theme.conf ]] || continue
    if grep -Eq '^[[:space:]]*Current[[:space:]]*=' "$config"; then
      printf 'Existing SDDM theme choice in %s: leaving it untouched; KMOS theme not selected.\n' "$config"
      return 0
    fi
  done
  stage_file system /etc/sddm.conf.d/kmos-theme.conf write_sddm_theme || return 1
}

stage_defaults() {
  local account_cfg="$home/.config" account_data="$home/.local/share"
  # Source only the ISO's individual config writers, never apply_post_tweaks.
  # shellcheck disable=SC1090,SC1091
  source "$SCRIPT_DIR/kmos-kde-post.sh"
  MOUNT_POINT=/
  stage_fonts || return 1
  stage_sddm_assets || return 1
  stage_file system /etc/xdg/ksplashrc write_ksplash_none || return 1
  stage_file system /etc/xdg/kscreenlockerrc write_kscreenlocker_defaults || return 1
  stage_file system /etc/skel/.config/ksplashrc write_ksplash_none || return 1
  stage_file system /etc/skel/.config/kscreenlockerrc write_kscreenlocker_defaults || return 1
  stage_file user "$account_cfg/ksplashrc" write_ksplash_none || return 1
  stage_file user "$account_cfg/kscreenlockerrc" write_kscreenlocker_defaults || return 1
  stage_file system /usr/share/konsole/kmos.colorscheme write_kmos_konsole_color || return 1
  stage_file system /etc/skel/.local/share/konsole/kmos.profile write_kmos_konsole_profile || return 1
  stage_file system /etc/skel/.local/share/konsole/kmos-dolphin.profile write_kmos_dolphin_profile || return 1
  stage_file system /etc/skel/.local/share/konsole/Default.profile write_konsole_default_profile || return 1
  stage_file system /etc/skel/.config/konsolerc write_konsole_rc || return 1
  stage_file system /etc/xdg/konsolerc write_konsole_rc || return 1
  stage_file user "$account_data/konsole/kmos.colorscheme" write_kmos_konsole_color || return 1
  stage_file user "$account_data/konsole/kmos.profile" write_kmos_konsole_profile || return 1
  stage_file user "$account_data/konsole/kmos-dolphin.profile" write_kmos_dolphin_profile || return 1
  stage_file user "$account_data/konsole/Default.profile" write_konsole_default_profile || return 1
  stage_file user "$account_cfg/konsolerc" write_konsole_rc || return 1
  stage_file system /etc/skel/.config/yakuakerc write_yakuake_rc || return 1
  if command -v yakuake >/dev/null; then
    stage_yakuake_skin || return 1
    stage_file system /etc/xdg/autostart/kmos-yakuake.desktop write_kmos_yakuake_autostart || return 1
  fi
  stage_file user "$account_cfg/yakuakerc" write_yakuake_rc || return 1
  stage_file system /etc/skel/.config/dolphinrc write_dolphin_rc || return 1
  stage_file user "$account_cfg/dolphinrc" write_dolphin_rc || return 1
  stage_file system /usr/share/org.kde.syntax-highlighting/themes/kmos-github.theme write_kmos_kate_theme || return 1
  stage_file system /usr/share/org.kde.syntax-highlighting/themes/kmos-ayu.theme write_kmos_ayu_theme || return 1
  stage_file system /etc/skel/.config/katerc write_kate_rc || return 1
  stage_file user "$account_cfg/katerc" write_kate_rc || return 1
  stage_file system /etc/skel/.config/kwinrc write_virtual_desktops || return 1
  stage_file user "$account_cfg/kwinrc" write_virtual_desktops || return 1
}

main() {
  local original_user answer
  original_user="${SUDO_USER:-$(id -un)}"
  mode="${1:-}"
  case "$mode" in
    --help|-h) (( $# == 1 )) || { usage >&2; return 2; }; usage; return ;;
    --plan|--apply) ;;
    *) usage >&2; return 2 ;;
  esac
  if (( $# == 3 )) && [[ "$2" == --user ]]; then original_user="$3"
  elif (( $# != 1 )); then usage >&2; return 2
  fi
  choose_user "$original_user" || return 1
  check_system || return 1
  if [[ "$mode" == --apply && $EUID -ne 0 ]]; then
    command -v sudo >/dev/null || { fail 'sudo is required for --apply.'; return 1; }
    exec sudo -- "$SCRIPT_DIR/kmos-kde-finish.sh" --apply --user "$user"
  fi
  [[ "$mode" != --apply ]] || mode=apply
  [[ "$mode" != --plan ]] || mode=plan
  backup_stamp=$(date +%Y%m%d-%H%M%S)
  temp=$(mktemp -d) || return 1
  trap 'rm -rf -- "$temp"' EXIT
  printf 'KMOS KDE defaults for %s (%s). Existing files require individual approval.\n' "$user" "$mode"
  if [[ "$mode" == apply ]]; then
    printf 'Review --plan first. Type APPLY KMOS to add missing defaults and review existing files: ' >&2
    read -r answer </dev/tty || return 1
    [[ "$answer" == 'APPLY KMOS' ]] || { fail 'Cancelled without changes.'; return 1; }
  fi
  stage_defaults || return 1
  if [[ "$mode" == plan ]]; then
    printf 'Maximum existing-config backup payload if you approve every replacement: %s bytes (not packages or home directories).\n' "$backup_bytes"
  fi
  printf 'Done. Skipped existing files: %s. No panels, wallpaper choices, packages or network services changed.\n' "$skipped"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
