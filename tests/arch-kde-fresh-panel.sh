#!/usr/bin/env bash
# Fixture-only KConfig checks. Never reset the host's Plasma session.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
MOUNT_POINT="$fixture/target"
mkdir -p "$MOUNT_POINT/home/alice/.config" "$MOUNT_POINT/home/bob"
printf 'personal panel configuration\n' > "$MOUNT_POINT/home/alice/.config/plasma-org.kde.plasma.desktop-appletsrc"
for plugin in org.kde.plasma.kickerdash org.kde.plasma.systemmonitor.net; do
  mkdir -p "$MOUNT_POINT/usr/share/plasma/plasmoids/$plugin"
  printf '{}\n' > "$MOUNT_POINT/usr/share/plasma/plasmoids/$plugin/metadata.json"
done
cp -a "$repo/platforms/archlinux/assets/sysmonitor/." "$MOUNT_POINT/usr/share/plasma/plasmoids/"
arch-chroot() { [[ "$1" == "$MOUNT_POINT" && "$2" == chown ]]; }

install_fresh_kmos_panel
preset="$MOUNT_POINT/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
cmp "$preset" "$MOUNT_POINT/home/bob/.config/plasma-org.kde.plasma.desktop-appletsrc"
[[ $(cat "$MOUNT_POINT/home/alice/.config/plasma-org.kde.plasma.desktop-appletsrc") == 'personal panel configuration' ]]
[[ $(stat -c %a "$preset") == 644 ]]
grep -Fxq 'AppletOrder=4;5;6;7;8;21;22;23;24;25;26;27;28' "$preset"
for plugin in kickerdash pager icontasks marginsseparator systemtray showdesktop; do
  grep -Fq "plugin=org.kde.plasma.$plugin" "$preset"
done
for plugin in kmos-cpu-gpu kmos-mem kmos-disk net; do
  grep -Fxq "plugin=org.kde.plasma.systemmonitor.$plugin" "$preset"
done
[[ $(grep -Fxc 'plugin=org.kde.plasma.digitalclock' "$preset") == 3 ]]
for clock in America/Bogota Local Asia/Shanghai; do
  grep -Fxq "selectedTimeZones=$clock" "$preset"
done
grep -Fxq 'launchers=' "$preset"
[[ ! -e "$MOUNT_POINT/usr/share/plasma/layout-templates/org.kde.kmos.defaultPanel" ]]
[[ ! -e "$MOUNT_POINT/usr/share/plasma/look-and-feel/org.kde.kmos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js" ]]
[[ ! -e "$repo/platforms/archlinux/assets/plasma/kmos-panel-setup.js" ]]
if (install_fresh_kmos_panel) > "$fixture/rerun" 2>&1; then
  echo 'Rerun overwrote the first-login panel preset.' >&2; exit 1
fi

apply_desktop_wallpaper_defaults
desktop="$MOUNT_POINT/etc/skel/.config/autostart/kmos-first-login-wallpaper.desktop"
script="$MOUNT_POINT/usr/share/kmos/bin/kmos-first-login-wallpaper.sh"
[[ -x "$script" && $(stat -c %a "$script") == 755 ]]
bash -n "$script"
cmp "$desktop" "$MOUNT_POINT/home/bob/.config/autostart/kmos-first-login-wallpaper.desktop"
[[ ! -e "$MOUNT_POINT/home/alice/.config/autostart/kmos-first-login-wallpaper.desktop" ]]
[[ ! -e "$MOUNT_POINT/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/zz-kmos-wallpaper.js" ]]
mkdir -p "$fixture/bin" "$fixture/new-user-config"
printf 'fixture wallpaper\n' > "$fixture/kmos.png"
cat > "$fixture/bin/gdbus" <<'WALLPAPER_MOCK'
#!/usr/bin/env bash
case "$*" in
  *org.kde.PlasmaShell.wallpaper*)
    screen="${*: -1}"
    if [[ "${NO_SCREENS:-no}" == yes || "$screen" -gt 1 ]]; then
      printf '(@a{sv} {},)\n'
    elif [[ -e "$WALLPAPER_CALLS/$screen" ]]; then
      if [[ "${BAD_COLOR:-no}" == yes ]]; then
        printf "({'wallpaperPlugin': <'org.kde.image'>, 'Image': <'file://%s'>, 'FillMode': <1>, 'Color': <(uint32 4294967295,)>},)\n" "$KMOS_WALLPAPER_IMAGE"
      else
        printf "({'wallpaperPlugin': <'org.kde.image'>, 'Image': <'file://%s'>, 'FillMode': <1>, 'Color': <(uint32 4278190080,)>},)\n" "$KMOS_WALLPAPER_IMAGE"
      fi
    else
      printf "({'wallpaperPlugin': <'org.kde.image'>, 'FillMode': <2>, 'Color': <(uint32 4294967295,)>},)\n"
    fi
    ;;
  *org.kde.PlasmaShell.setWallpaper*)
    [[ "${WALLPAPER_FAIL:-no}" == no ]] || exit 1
    printf '%s\n' "$*" >> "$WALLPAPER_CALLS/set-calls"
    touch "$WALLPAPER_CALLS/${*: -1}"
    ;;
  *) exit 1 ;;
esac
WALLPAPER_MOCK
chmod +x "$fixture/bin/gdbus"
export WALLPAPER_CALLS="$fixture/wallpaper-calls"
mkdir -p "$WALLPAPER_CALLS"
PATH="$fixture/bin:$PATH" KMOS_WALLPAPER_IMAGE="$fixture/kmos.png" \
  XDG_CONFIG_HOME="$fixture/new-user-config" "$script"
[[ $(wc -l < "$WALLPAPER_CALLS/set-calls") == 2 ]]
grep -Fq "'Image': <'file://$fixture/kmos.png'>" "$WALLPAPER_CALLS/set-calls"
grep -Fq "'FillMode': <int32 1>" "$WALLPAPER_CALLS/set-calls"
grep -Fq "'Color': <(uint32 4278190080,)>" "$WALLPAPER_CALLS/set-calls"
[[ -f "$fixture/new-user-config/.kmos-wallpaper-applied" ]]
PATH="$fixture/bin:$PATH" KMOS_WALLPAPER_IMAGE="$fixture/kmos.png" \
  XDG_CONFIG_HOME="$fixture/new-user-config" "$script"
[[ $(wc -l < "$WALLPAPER_CALLS/set-calls") == 2 ]]
if PATH="$fixture/bin:$PATH" KMOS_WALLPAPER_IMAGE="$fixture/kmos.png" WALLPAPER_FAIL=yes \
    XDG_CONFIG_HOME="$fixture/failed-user-config" "$script" > "$fixture/wallpaper-failure" 2>&1; then
  echo 'Wallpaper failure was marked complete.' >&2; exit 1
fi
[[ ! -e "$fixture/failed-user-config/.kmos-wallpaper-applied" ]]
if PATH="$fixture/bin:$PATH" KMOS_WALLPAPER_IMAGE="$fixture/kmos.png" BAD_COLOR=yes \
    XDG_CONFIG_HOME="$fixture/bad-color-config" "$script" > "$fixture/bad-color" 2>&1; then
  echo 'A white wallpaper background was marked complete.' >&2; exit 1
fi
[[ ! -e "$fixture/bad-color-config/.kmos-wallpaper-applied" ]]
if PATH="$fixture/bin:$PATH" KMOS_WALLPAPER_IMAGE="$fixture/kmos.png" NO_SCREENS=yes \
    XDG_CONFIG_HOME="$fixture/no-screens-config" "$script" > "$fixture/no-screens" 2>&1; then
  echo 'No Plasma screens were accepted.' >&2; exit 1
fi
[[ ! -e "$fixture/no-screens-config/.kmos-wallpaper-applied" ]]

write_kdeglobals_defaults "$fixture/kdeglobals"
install_lookandfeel_defaults
grep -A1 '^\[KDE\]$' "$fixture/kdeglobals" | grep -Fxq 'LookAndFeelPackage=org.kde.kmos.desktop'
[[ $(cat "$MOUNT_POINT/home/alice/.config/plasma-org.kde.plasma.desktop-appletsrc") == 'personal panel configuration' ]]
echo 'KMOS shell-only panel and wallpaper presets: OK (fixture checks only).'
