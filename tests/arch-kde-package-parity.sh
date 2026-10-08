#!/usr/bin/env bash
# Pin both KDE profiles to the tested ISO package sets; no package operations.
# shellcheck disable=SC1090,SC1091
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
iso="$repo/platforms/archlinux/desktop/kde/kmos-kde-install.sh"
live="$repo/platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

for profile in full noapps; do
  (
    source "$iso"
    KDE_PROFILE="$profile" INSTALL_AUR=no KDE_LOCAL_MANIFESTS_ONLY=yes
    select_kde_metapackages
    load_kde_metapackages 2> "$fixture/$profile-details"
    printf '%s\n' "${KDE_PACKAGES[@]}"
  ) > "$fixture/$profile-iso"
  (
    source "$live"
    resolve_kde_packages "$profile"
  ) > "$fixture/$profile-live" 2> "$fixture/$profile-live-details"
  cmp "$fixture/$profile-iso" "$fixture/$profile-live"
done

[[ $(wc -l < "$fixture/full-iso") == 96 ]]
[[ $(sha256sum "$fixture/full-iso" | cut -d ' ' -f 1) == 6eb146dc47bdda748f0a487554afee31f5125eca1bfd3ae6c51498092d699209 ]]
[[ $(wc -l < "$fixture/noapps-iso") == 74 ]]
[[ $(sha256sum "$fixture/noapps-iso" | cut -d ' ' -f 1) == 4a3ab32b8b53a7b2a60bfa8f447ca0403be3c5a5d9d1601e94bc4f5eb56f060b ]]

# A missing local manifest must not silently resolve against published main.
if (
  source "$iso"
  METAPACKAGE_ROOT_DIR="$fixture/missing"
  KDE_LOCAL_MANIFESTS_ONLY=yes
  get_metapackage_pkgbuild kmos-kde-noapps
) > "$fixture/missing-output" 2>&1; then
  printf 'Missing manifest was accepted by the live resolver.\n' >&2
  exit 1
fi
grep -Fq 'Local metapackage missing: kde/noapps/PKGBUILD' "$fixture/missing-output"
printf 'ISO and live full/noapps package sets match the tested baseline (fixture only).\n'
