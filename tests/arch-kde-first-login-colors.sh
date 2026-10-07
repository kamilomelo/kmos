#!/usr/bin/env bash
# Color first-login tests run against fake homes and commands only.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
MOUNT_POINT="$fixture/target"
arch-chroot() { :; }

mkdir -p "$fixture/bin" "$fixture/home/.config" "$MOUNT_POINT/home/alice/.config" "$MOUNT_POINT/home/bob"
printf '[General]\nColorScheme=BreezeDark\n' > "$MOUNT_POINT/home/alice/.config/kdeglobals"
printf 'custom scheme\n' > "$MOUNT_POINT/home/alice/.local-colors"
cp "$MOUNT_POINT/home/alice/.config/kdeglobals" "$fixture/personal-config"
apply_color_scheme_defaults > "$fixture/install-log" 2>&1
cmp "$fixture/personal-config" "$MOUNT_POINT/home/alice/.config/kdeglobals"
grep -Fxq 'ColorScheme=kmos' "$MOUNT_POINT/home/bob/.config/kdeglobals"
autostart="$MOUNT_POINT/etc/xdg/autostart/kmos-apply-colorscheme.desktop"
script="$MOUNT_POINT/usr/share/kmos/bin/kmos-apply-colorscheme.sh"
grep -Fxq 'Exec=/usr/share/kmos/bin/kmos-apply-colorscheme.sh' "$autostart"
! grep -q 'Autostart-enabled=false\|Exec=/mnt/' "$autostart"

cat > "$fixture/bin/kreadconfig6" <<'EOF'
#!/bin/sh
file=''
key=''
while [ "$#" -gt 0 ]; do
    if [ "$1" = --file ]; then file="$2"; shift; fi
    if [ "$1" = --key ]; then key="$2"; shift; fi
    shift
done
sed -n "s/^$key=//p" "$file" | head -n 1
EOF
cat > "$fixture/bin/plasma-apply-colorscheme" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
[ "${FAIL_APPLY:-no}" = no ] || exit 1
[ "${NOOP_APPLY:-no}" = no ] || exit 0
printf 'ColorSchemeHash=%s\n' "$(sha1sum "$SCHEME_PATH" | cut -d' ' -f1)" >> "$XDG_CONFIG_HOME/kdeglobals"
EOF
chmod +x "$fixture/bin/kreadconfig6" "$fixture/bin/plasma-apply-colorscheme"
export PATH="$fixture/bin:$PATH" HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/home/.config" CALLS="$fixture/calls"
export XDG_DATA_HOME="$HOME/.local/share" SCHEME_PATH="$HOME/.local/share/color-schemes/kmos.colors"
mkdir -p "${SCHEME_PATH%/*}"
cp "$repo/platforms/archlinux/assets/color-schemes/kmos.colors" "$SCHEME_PATH"
printf '[General]\nColorScheme=kmos\n' > "$XDG_CONFIG_HOME/kdeglobals"
"$script"
[[ -f "$XDG_CONFIG_HOME/.kmos-colorscheme-applied" && $(cat "$CALLS") == "--accent-color #757575" ]]
[[ $(sha1sum "$SCHEME_PATH" | cut -d' ' -f1) == "$(sed -n 's/^ColorSchemeHash=//p' "$XDG_CONFIG_HOME/kdeglobals")" ]]
"$script"
[[ $(wc -l < "$CALLS") == 1 ]]

rm "$XDG_CONFIG_HOME/.kmos-colorscheme-applied"
printf '[General]\nColorScheme=BreezeDark\n' > "$XDG_CONFIG_HOME/kdeglobals"
"$script"
[[ -f "$XDG_CONFIG_HOME/.kmos-colorscheme-applied" && $(wc -l < "$CALLS") == 1 ]]
printf '[General]\nColorScheme=kmos\n' > "$XDG_CONFIG_HOME/kdeglobals"
"$script"
[[ $(wc -l < "$CALLS") == 1 ]]

rm "$XDG_CONFIG_HOME/.kmos-colorscheme-applied"
printf '[General]\nColorScheme=kmos\n' > "$XDG_CONFIG_HOME/kdeglobals"
if NOOP_APPLY=yes "$script"; then
  echo 'No-op color application was recorded as successful.' >&2; exit 1
fi
[[ ! -e "$XDG_CONFIG_HOME/.kmos-colorscheme-applied" ]]
if FAIL_APPLY=yes "$script"; then
  echo 'Failed color application was recorded as successful.' >&2; exit 1
fi
[[ ! -e "$XDG_CONFIG_HOME/.kmos-colorscheme-applied" ]]
"$script"
[[ -f "$XDG_CONFIG_HOME/.kmos-colorscheme-applied" ]]
echo 'KDE first-login color application: OK (mocked only).'
