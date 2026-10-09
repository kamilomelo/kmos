#!/usr/bin/env bash
# Verify shared ISO/live guided manifests and preserve all previous full apps.
# No package manager, network or target system operations.
# shellcheck disable=SC1090,SC1091
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
iso="$repo/platforms/archlinux/desktop/kde/kmos-kde-install.sh"
live="$repo/platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh"
base="$repo/platforms/archlinux/kmos-archlinux-install.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

(
  source "$base"
  load_nodesktop_metapackage >/dev/null 2>&1
  for required in opencode ripgrep starship btop iwd impala; do
    [[ " ${BASE_PACKAGES[*]} " == *" $required "* ]]
  done
  [[ " ${BASE_PACKAGES[*]} " != *' firefox-developer-edition '* ]]
)
if (
  source "$base"
  NODESKTOP_METAPACKAGE_DIR="$fixture/missing"
  load_nodesktop_metapackage
) > "$fixture/missing-base" 2>&1; then
  printf 'Missing mandatory shared Arch packages were accepted.\n' >&2; exit 1
fi
grep -Fq 'Mandatory shared Arch packages missing' "$fixture/missing-base"

for personal in no yes; do
  group=
  if [[ "$personal" == yes ]]; then group=kmos-kamilo-productivity; fi
  (
    source "$iso"
    KDE_PROFILE=custom INSTALL_AUR=no KDE_LOCAL_MANIFESTS_ONLY=yes
    kmos_KDE_METAPACKAGES="$group"
    select_kde_metapackages
    load_kde_metapackages 2> "$fixture/$personal-details"
    printf '%s\n' "${KDE_PACKAGES[@]}"
  ) > "$fixture/$personal-iso"
  (
    source "$live"
    if [[ -n "$group" ]]; then resolve_kde_packages custom "$group"
    else resolve_kde_packages custom; fi
  ) > "$fixture/$personal-live" 2> "$fixture/$personal-live-details"
  cmp "$fixture/$personal-iso" "$fixture/$personal-live"
  for required in plasma-desktop networkmanager sddm firefox-developer-edition spectacle kdenlive \
    pipewire-jack qt6-multimedia-ffmpeg tesseract-data-eng; do
    grep -Fxq "$required" "$fixture/$personal-iso"
  done
done
for personal in typst inkscape simple-scan rust; do
  grep -Fxq "$personal" "$fixture/yes-iso"
done
if grep -Fxq cargo "$fixture/yes-iso"; then
  printf 'Virtual Cargo target reintroduced the rust/rustup provider prompt.\n' >&2; exit 1
fi
if grep -Eq '^(typst|inkscape|simple-scan|rust)$' "$fixture/no-iso"; then
  printf 'Optional productivity package was made mandatory.\n' >&2; exit 1
fi

# Legacy full is an inventory reference: the selected Kamilo layer keeps every
# previously selected official-repository package and adds approved choices.
(
  source "$iso"
  KDE_PROFILE=full INSTALL_AUR=no KDE_LOCAL_MANIFESTS_ONLY=yes
  select_kde_metapackages
  load_kde_metapackages 2> "$fixture/legacy-details"
  printf '%s\n' "${KDE_PACKAGES[@]}"
) > "$fixture/legacy-full"
if comm -23 "$fixture/legacy-full" "$fixture/yes-iso" | grep .; then
  printf 'A legacy full package was lost in the guided profile.\n' >&2; exit 1
fi
[[ $(comm -13 "$fixture/legacy-full" "$fixture/yes-iso") == $'qt6-multimedia-ffmpeg\nrust\nsimple-scan\ntesseract-data-eng' ]]

# Never silently use published main manifests when an experimental source is missing.
if (
  source "$iso"
  METAPACKAGE_ROOT_DIR="$fixture/missing"
  KDE_LOCAL_MANIFESTS_ONLY=yes
  get_metapackage_pkgbuild kmos-kde-apps
) > "$fixture/missing-output" 2>&1; then
  printf 'Missing manifest was accepted by the live resolver.\n' >&2; exit 1
fi
grep -Fq 'Local metapackage missing: kde/apps/PKGBUILD' "$fixture/missing-output"
printf 'Guided ISO/live package parity and legacy-full coverage: OK (fixtures only).\n'
