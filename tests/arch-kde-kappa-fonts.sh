#!/usr/bin/env bash
# Mocked target only; never install or remove fonts from the host.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
MOUNT_POINT="$fixture/target"

write_konsole_profile "$fixture/kmos.profile"
write_konsole_default_profile "$fixture/Default.profile"
write_konsole_dolphin_profile "$fixture/kmos-dolphin.profile"
for profile in "$fixture"/*.profile \
  "$repo/platforms/archlinux/assets/konsole/kmos.profile" \
  "$repo/platforms/archlinux/assets/konsole/kmos-dolphin.profile"; do
  grep -Fxq 'Font=Kappa Mono,11,-1,5,50,0,0,0,0,0' "$profile"
done
grep -Fxq "  'wqy-microhei'" "$repo/platforms/archlinux/packages/metapackages/desktop-shared/fonts/PKGBUILD"

arch-chroot() {
  if [[ "$2" == fc-match ]]; then
    printf 'Kappa Mono\n'
  else
    [[ "$2" == fc-cache ]]
  fi
}
curl() {
  if [[ "$1" == -fsSL && "${3:-}" == -o ]]; then
    printf 'fixture font\n' > "$4"
    return
  fi
  if [[ "$2" == *'/kappa-mono/'* ]]; then
    if [[ "${SKIP_REGULAR:-no}" == yes ]]; then
      printf '%s\n' 'https://raw.githubusercontent.com/kappa-type/KappaMono-Bold.ttf'
    else
      printf '%s\n' 'https://raw.githubusercontent.com/kappa-type/KappaMono-Regular.ttf'
    fi
  else
    printf '%s\n' 'https://raw.githubusercontent.com/kappa-type/KappaText-Regular.ttf'
  fi
}

if ! (install_extra_fonts) > "$fixture/font-log" 2>&1; then
  cat "$fixture/font-log" >&2
  exit 1
fi
[[ -s "$MOUNT_POINT/usr/local/share/fonts/kmos/KappaMono-Regular.ttf" ]]
[[ $(stat -c %a "$MOUNT_POINT/usr/local/share/fonts/kmos/KappaMono-Regular.ttf") == 644 ]]
if (SKIP_REGULAR=yes install_extra_fonts) > "$fixture/missing-regular" 2>&1; then
  echo 'Missing Kappa Mono Regular was accepted.' >&2; exit 1
fi
grep -Fq 'Kappa Mono Regular was not downloaded' "$fixture/missing-regular"
echo 'KDE Kappa Mono profile, target font and CJK package: OK (mocked only).'
