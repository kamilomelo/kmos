#!/usr/bin/env bash
# Fixture-only first-run layout checks. Never run a Plasma reset on this host.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
MOUNT_POINT="$fixture/target"
stock="$MOUNT_POINT/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js"
mkdir -p "${stock%/*}" "$MOUNT_POINT/home/alice/.config"
cat > "$stock" <<'EOF'
var panel = new Panel
panel.addWidget("org.kde.plasma.kickoff")
panel.addWidget("org.kde.plasma.pager")
panel.addWidget("org.kde.plasma.icontasks")
panel.addWidget("org.kde.plasma.marginsseparator")
panel.addWidget("org.kde.plasma.systemtray")
panel.addWidget("org.kde.plasma.digitalclock")
panel.addWidget("org.kde.plasma.showdesktop")
EOF
cp "$stock" "$fixture/stock"
printf 'personal panel configuration\n' > "$MOUNT_POINT/home/alice/.config/plasma-org.kde.plasma.desktop-appletsrc"
for plugin in org.kde.plasma.kickerdash org.kde.plasma.systemmonitor.net; do
  mkdir -p "$MOUNT_POINT/usr/share/plasma/plasmoids/$plugin"
  printf '{}\n' > "$MOUNT_POINT/usr/share/plasma/plasmoids/$plugin/metadata.json"
done
cp -a "$repo/platforms/archlinux/assets/sysmonitor/." "$MOUNT_POINT/usr/share/plasma/plasmoids/"

install_fresh_kmos_panel
cmp "$stock" "$fixture/stock"
[[ $(cat "$MOUNT_POINT/home/alice/.config/plasma-org.kde.plasma.desktop-appletsrc") == 'personal panel configuration' ]]
panel="$MOUNT_POINT/usr/share/plasma/layout-templates/org.kde.kmos.defaultPanel/contents/layout.js"
layout="$MOUNT_POINT/usr/share/plasma/look-and-feel/org.kde.kmos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
[[ $(grep -Fxc 'panel.addWidget("org.kde.plasma.kickerdash")' "$panel") == 1 ]]
! grep -Fq 'panel.addWidget("org.kde.plasma.kickoff")' "$panel"
grep -Fxq 'loadTemplate("org.kde.kmos.defaultPanel")' "$layout"
[[ $(grep -Fxc 'panel.addWidget("org.kde.plasma.digitalclock")' "$panel") == 3 ]]
for plugin in kmos-cpu-gpu kmos-mem kmos-disk; do
  [[ $(grep -Fxc "panel.addWidget(\"org.kde.plasma.systemmonitor.$plugin\")" "$panel") == 1 ]]
done
[[ $(grep -Fxc 'panel.addWidget("org.kde.plasma.systemmonitor.net")' "$panel") == 1 ]]
[[ $(grep -Fxc 'panel.addWidget("org.kde.plasma.systemtray")' "$panel") == 1 ]]
[[ $(grep -Fxc 'panel.addWidget("org.kde.plasma.icontasks")' "$panel") == 1 ]]
[[ $(grep -Fxc 'panel.addWidget("org.kde.plasma.showdesktop")' "$panel") == 1 ]]
mapfile -t order < <(grep '^panel.addWidget' "$panel")
[[ ${order[0]} == 'panel.addWidget("org.kde.plasma.kickerdash")' ]]
[[ ${order[4]} == 'panel.addWidget("org.kde.plasma.systemtray")' ]]
[[ ${order[5]} == 'panel.addWidget("org.kde.plasma.systemmonitor.kmos-cpu-gpu")' ]]
[[ ${order[6]} == 'panel.addWidget("org.kde.plasma.systemmonitor.kmos-mem")' ]]
[[ ${order[7]} == 'panel.addWidget("org.kde.plasma.systemmonitor.kmos-disk")' ]]
[[ ${order[8]} == 'panel.addWidget("org.kde.plasma.systemmonitor.net")' ]]
[[ ${order[12]} == 'panel.addWidget("org.kde.plasma.showdesktop")' ]]
if (install_fresh_kmos_panel) > "$fixture/rerun" 2>&1; then
  echo 'Rerun overwrote first-login defaults.' >&2; exit 1
fi

write_kdeglobals_defaults "$fixture/kdeglobals"
install_lookandfeel_defaults
grep -A1 '^\[KDE\]$' "$fixture/kdeglobals" | grep -Fxq 'LookAndFeelPackage=org.kde.kmos.desktop'
grep -A1 '^\[KDE\]$' "$MOUNT_POINT/usr/share/plasma/look-and-feel/org.kde.kmos.desktop/contents/defaults/kdeglobals" \
  | grep -Fxq 'LookAndFeelPackage=org.kde.kmos.desktop'
[[ $(cat "$MOUNT_POINT/home/alice/.config/plasma-org.kde.plasma.desktop-appletsrc") == 'personal panel configuration' ]]
# Changed KDE templates must be rejected, without creating an incomplete theme.
other="$fixture/unexpected"
MOUNT_POINT="$other"
mkdir -p "$other/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents"
printf 'panel.addWidget("org.kde.plasma.kicker")\n' \
  > "$other/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js"
if (install_fresh_kmos_panel) > "$fixture/unexpected-log" 2>&1; then
  echo 'Unexpected packaged layout was accepted.' >&2; exit 1
fi
[[ ! -e "$other/usr/share/plasma/layout-templates/org.kde.kmos.defaultPanel" ]]
echo 'KMOS fresh panel defaults: OK (fixtures only; graphical first login untested).'
