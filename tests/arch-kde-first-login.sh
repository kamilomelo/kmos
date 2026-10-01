#!/usr/bin/env bash
# Test fresh KDE defaults in fixtures, never the host's Plasma configuration.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
MOUNT_POINT="$fixture/target"
mkdir -p "$fixture/bin" "$fixture/home/.config" "$MOUNT_POINT/etc/skel/.local/share/konsole"
arch-chroot() { :; }  # Never touch a real user's files or system services.

mkdir -p "$MOUNT_POINT/home/alice/.config"
printf '[General]\nColorScheme=BreezeDark\n' > "$MOUNT_POINT/home/alice/.config/kdeglobals"
cp "$MOUNT_POINT/home/alice/.config/kdeglobals" "$fixture/user-preference"
apply_color_scheme_defaults > "$fixture/colors-log" 2>&1
cmp "$fixture/user-preference" "$MOUNT_POINT/home/alice/.config/kdeglobals"
grep -A1 '^\[KDE\]$' "$MOUNT_POINT/etc/skel/.config/kdeglobals" \
  | grep -qx 'LookAndFeelPackage=org.kde.kmos.desktop'
if grep -A4 '^\[General\]$' "$MOUNT_POINT/etc/skel/.config/kdeglobals" \
  | grep -q 'LookAndFeelPackage='; then
  printf 'LookAndFeelPackage was written into the wrong group.\n' >&2; exit 1
fi
mkdir -p "$MOUNT_POINT/home/alice/.local/share/konsole" "$MOUNT_POINT/home/bob/.config"
printf 'Personal profile\n' > "$MOUNT_POINT/home/alice/.local/share/konsole/kmos.profile"
printf 'Personal default\n' > "$MOUNT_POINT/home/alice/.local/share/konsole/Default.profile"
printf 'Personal Konsole settings\n' > "$MOUNT_POINT/home/alice/.config/konsolerc"
apply_konsole_defaults > "$fixture/konsole-log" 2>&1
[[ $(cat "$MOUNT_POINT/home/alice/.local/share/konsole/kmos.profile") == 'Personal profile' ]]
[[ $(cat "$MOUNT_POINT/home/alice/.local/share/konsole/Default.profile") == 'Personal default' ]]
[[ $(cat "$MOUNT_POINT/home/alice/.config/konsolerc") == 'Personal Konsole settings' ]]
grep -qx 'Font=Kappa Mono,11,-1,5,50,0,0,0,0,0' "$MOUNT_POINT/home/bob/.local/share/konsole/kmos.profile"

script="$fixture/apply-colorscheme.sh"
entry="$fixture/autostart.desktop"
write_color_scheme_autostart "$script" "$entry"
grep -qx 'Exec=/usr/share/kmos/bin/kmos-apply-colorscheme.sh' "$entry"
if grep -q 'Autostart-enabled=false\|/mnt/usr/share' "$entry"; then
  printf 'First-login color autostart is disabled or points into /mnt.\n' >&2; exit 1
fi
cat > "$fixture/bin/plasma-apply-colorscheme" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >> "$CALLS"
[ "${FAIL_APPLY:-no}" = no ]
EOF
chmod +x "$fixture/bin/plasma-apply-colorscheme"
export PATH="$fixture/bin:$PATH" HOME="$fixture/home" CALLS="$fixture/calls"
printf '[General]\nColorScheme=kmos\n' > "$HOME/.config/kdeglobals"
"$script"
[[ -f "$HOME/.config/.kmos-colorscheme-applied" && $(cat "$CALLS") == kmos ]]
"$script"
[[ $(wc -l < "$CALLS") == 1 ]]  # Never reapply over a later user choice.

rm "$HOME/.config/.kmos-colorscheme-applied"
printf '[General]\nColorScheme=BreezeDark\n' > "$HOME/.config/kdeglobals"
"$script"
[[ ! -e "$HOME/.config/.kmos-colorscheme-applied" && $(wc -l < "$CALLS") == 1 ]]
printf '[General]\nColorScheme=kmos\n' > "$HOME/.config/kdeglobals"
if FAIL_APPLY=yes "$script"; then
  printf 'Failed color application was reported as successful.\n' >&2; exit 1
fi
[[ ! -e "$HOME/.config/.kmos-colorscheme-applied" ]]

write_konsole_default_profile "$MOUNT_POINT/etc/skel/.local/share/konsole/Default.profile"
for profile in "$repo/platforms/archlinux/assets/konsole/kmos.profile" \
  "$repo/platforms/archlinux/assets/konsole/kmos-dolphin.profile" \
  "$MOUNT_POINT/etc/skel/.local/share/konsole/Default.profile"; do
  grep -qx 'Font=Kappa Mono,11,-1,5,50,0,0,0,0,0' "$profile"
done
printf 'KDE first-login color and Kappa Mono defaults: OK (fixtures only).\n'
