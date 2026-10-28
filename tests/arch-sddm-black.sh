#!/usr/bin/env bash
# No host SDDM files are read or written; all QML and backups live in fixtures.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
post="$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
finish="$repo/platforms/archlinux/desktop/kde/kmos-kde-finish.sh"

make_breeze() {
  mkdir -p "$1"
  printf 'sceneBackgroundColor: config.color\n' > "$1/Main.qml"
  cat > "$1/Background.qml" <<'EOF'
FocusScope {
    Rectangle { id: sceneColorBackground }
    Image { id: sceneImageBackground }
    states: [
        State {
            name: "imageBackground"
            PropertyChanges {
                target: sceneColorBackground
                visible: false
            }
            PropertyChanges {
                target: sceneImageBackground
                visible: true
            }
        },
        State {
            name: "colorBackground"
        }
    ]
}
EOF
}

(
  # shellcheck disable=SC1090
  source "$post"
  MOUNT_POINT="$fixture/new"
  ASSET_WALLPAPER="$fixture/kmos.png"
  printf 'fixture PNG\n' > "$ASSET_WALLPAPER"
  theme="$MOUNT_POINT/usr/share/sddm/themes/breeze"
  make_breeze "$theme"
  cp "$theme/Background.qml" "$fixture/expected-original"
  apply_sddm_defaults
  grep -Fxq 'color=#000000' "$theme/theme.conf.user"
  grep -Fxq 'background=/opt/kmos/assets/wallpapers/kmos-wallpaper.png' "$theme/theme.conf.user"
  grep -Fxq '                visible: true' "$theme/Background.qml"
  [[ $(grep -Fc 'visible: true' "$theme/Background.qml") == 2 ]]
  mapfile -t backups < <(find "$MOUNT_POINT/var/backups/kmos/sddm" -type f)
  [[ ${#backups[@]} == 1 && $(stat -c %a "${backups[0]}") == 600 ]]
  cmp -s "$fixture/expected-original" "${backups[0]}"
  apply_sddm_defaults
  [[ $(find "$MOUNT_POINT/var/backups/kmos/sddm" -type f | wc -l) == 1 ]]
) > "$fixture/new-output" 2>&1

(
  # shellcheck disable=SC1090
  source "$finish"
  sddm_breeze_dir="$fixture/existing/themes/breeze"
  sddm_config_dir="$fixture/existing/etc/sddm.conf.d"
  sddm_main_config="$fixture/existing/etc/sddm.conf"
  sddm_choice_file="$sddm_config_dir/kmos-theme.conf"
  sddm_backup_dir="$fixture/existing/backups"
  sddm_wallpaper=/opt/kmos/assets/wallpapers/kmos-wallpaper.png
  make_breeze "$sddm_breeze_dir"
  mkdir -p "$sddm_config_dir"
  printf '[Theme]\nCurrent=breeze\n' > "$sddm_choice_file"
  printf '[General]\ntype=image\nbackground=%s\ncolor=#000000\n' "$sddm_wallpaper" > "$sddm_breeze_dir/theme.conf.user"
  cp "$sddm_breeze_dir/Background.qml" "$fixture/old-qml"
  black_sddm_background
  grep -Fxq '                visible: true' "$sddm_breeze_dir/Background.qml"
  black_sddm_background
  [[ $(find "$sddm_backup_dir" -type f | wc -l) == 1 ]]
  mapfile -t backups < <(find "$sddm_backup_dir" -type f)
  cmp -s "$fixture/old-qml" "${backups[0]}"
  printf 'Current=personal\n' > "$sddm_choice_file"
  if black_sddm_background > "$fixture/refused" 2>&1; then exit 1; fi
  grep -Fq 'no changes made' "$fixture/refused"
  printf '[Theme]\nCurrent=breeze\n' > "$sddm_choice_file"
  sed -i 's/target: sceneColorBackground/target: personalBackground/' "$sddm_breeze_dir/Background.qml"
  if black_sddm_background > "$fixture/unrecognized" 2>&1; then exit 1; fi
  grep -Fq 'no changes made' "$fixture/unrecognized"
) > "$fixture/existing-output" 2>&1

printf 'SDDM black image background: OK (fixture QML and backup only).\n'
