#!/usr/bin/env bash
# Panel safeguards in an offline target fixture; never touches the live Plasma session.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
MOUNT_POINT="$fixture/target"
updates="$MOUNT_POINT/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates"
layout="$MOUNT_POINT/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js"
mkdir -p "$updates" "${layout%/*}"
printf 'panel.addWidget("org.kde.plasma.kickoff")\n' > "$layout"
cp "$layout" "$fixture/original-layout"
printf 'panel.addWidget("org.kde.plasma.kickerdash")\n' > "$updates/zz-kmos-kickerdash.js"
printf 'function configureDigitalClock(widget) {}\n' > "$updates/zz-kmos-panel-widgets.js"
printf 'widget.writeConfig("launchers", "")\n' > "$updates/zz-kmos-unpin-taskmanager.js"
printf 'user customization\n' > "$updates/user-update.js"
disable_legacy_panel_updates
for name in zz-kmos-kickerdash.js zz-kmos-panel-widgets.js zz-kmos-unpin-taskmanager.js; do
  [[ ! -e "$updates/$name" && -f "$updates/$name.kmos-disabled" ]]
done
cmp "$layout" "$fixture/original-layout"
[[ $(cat "$updates/user-update.js") == 'user customization' ]]

# Fresh default only: copy KDE's panel into a KMOS-owned template, replacing
# just the launcher. No personal appletsrc or packaged KDE template is edited.
mkdir -p "$MOUNT_POINT/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/layouts" \
  "$MOUNT_POINT/usr/share/plasma/plasmoids/org.kde.plasma.kickerdash" \
  "$MOUNT_POINT/home/user/.config"
stock_desktop="$MOUNT_POINT/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
printf 'loadTemplate("org.kde.plasma.desktop.defaultPanel")\n' > "$stock_desktop"
applet="$MOUNT_POINT/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc"
printf 'personal panel layout\n' > "$applet"
install_fresh_panel_defaults
cmp "$layout" "$fixture/original-layout"
[[ $(cat "$applet") == 'personal panel layout' ]]
new_layout="$MOUNT_POINT/usr/share/plasma/layout-templates/org.kde.kmos.defaultPanel/contents/layout.js"
[[ $(grep -Fc 'panel.addWidget("org.kde.plasma.kickerdash")' "$new_layout") == 1 ]]
grep -Fq 'loadTemplate("org.kde.kmos.defaultPanel")' \
  "$MOUNT_POINT/usr/share/plasma/look-and-feel/org.kde.kmos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
if (install_fresh_panel_defaults) > "$fixture/no-overwrite" 2>&1; then
  printf 'Existing KMOS panel template was unexpectedly overwritten.\n' >&2; exit 1
fi
[[ $(cat "$applet") == 'personal panel layout' ]]

# Reruns leave backups and user files intact. An altered KMOS-named hook is
# never replaced or deleted merely because its filename looks familiar.
disable_legacy_panel_updates
printf 'user-edited panel hook\n' > "$updates/zz-kmos-panel-widgets.js"
if (disable_legacy_panel_updates) > "$fixture/unknown" 2>&1; then
  printf 'Unrecognized panel update was changed automatically.\n' >&2; exit 1
fi
[[ $(cat "$updates/zz-kmos-panel-widgets.js") == 'user-edited panel hook' ]]
[[ -f "$updates/zz-kmos-panel-widgets.js.kmos-disabled" ]]
grep -q 'review manually' "$fixture/unknown"
(
  MOUNT_POINT="$fixture/second-target"
  fresh="$MOUNT_POINT/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates"
  mkdir -p "$fresh"
  printf 'panel.addWidget("org.kde.plasma.kickerdash")\n' > "$fresh/zz-kmos-kickerdash.js"
  printf 'edited by user\n' > "$fresh/zz-kmos-panel-widgets.js"
  if (disable_legacy_panel_updates) > "$fixture/partial" 2>&1; then
    printf 'Unknown hook did not stop the cleanup.\n' >&2; exit 1
  fi
  [[ -f "$fresh/zz-kmos-kickerdash.js" && ! -e "$fresh/zz-kmos-kickerdash.js.kmos-disabled" ]]
)

# The post-install sequence must never invoke a panel-layout writer.
post_script="$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
if grep -Eq '^[[:space:]]*(apply_application_dashboard_defaults|apply_panel_widget_defaults|apply_taskmanager_unpin_defaults)[[:space:]]*$' "$post_script"; then
  printf 'A panel mutation was reintroduced into KDE post-install.\n' >&2; exit 1
fi
printf 'KDE panel hooks are disabled without rewriting user layout (fixture only).\n'
