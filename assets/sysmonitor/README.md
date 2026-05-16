# kmos sysmonitor presets

These custom Plasma system monitor widgets are part of the active installer input.

The KDE post-install script stages them into `/usr/share/plasma/plasmoids/` on the
target system and uses them in the default panel layout:

- `org.kde.plasma.systemmonitor.kmos-cpu-gpu`
- `org.kde.plasma.systemmonitor.kmos-mem`
- `org.kde.plasma.systemmonitor.kmos-disk`

Do not delete this folder unless you also remove or replace the matching panel
widget setup in `desktop/kde/kmos-kde-post.sh`.
