#!/usr/bin/env bash
# Test repository discovery and package selection without touching a board.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"

[[ $(find_local_repository) == "$repo" ]]
REPOSITORY_DIR=$repo
resolve_kde_metapackage kmos-kde-noapps
printf '%s\n' "${KDE_PACKAGES[@]}" | grep -qx plasma-desktop
printf '%s\n' "${KDE_PACKAGES[@]}" | grep -qx networkmanager
printf '%s\n' "${KDE_PACKAGES[@]}" | grep -qx sddm
[[ $(printf '%s\n' "${KDE_PACKAGES[@]}" | sort | uniq -d | wc -l) == 0 ]]
KDE_PACKAGES=()
KDE_METAPACKAGES=()
for metapackage in kmos-audio kmos-browsers kmos-devices kmos-docs kmos-filesystems kmos-fonts kmos-graphics kmos-kde-base kmos-kde-multimedia kmos-kde-utils kmos-maintenance kmos-network kmos-privacy; do
  resolve_kde_metapackage "$metapackage"
done
printf '%s\n' "${KDE_PACKAGES[@]}" | grep -qx plasma-desktop
[[ $(printf '%s\n' "${KDE_PACKAGES[@]}" | sort | uniq -d | wc -l) == 0 ]]
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
SCRIPT_DIR="$fixture"
if (find_local_repository) >/dev/null 2>&1; then
  printf 'A standalone script was accepted without its KMOS files.\n' >&2
  exit 1
fi
SCRIPT_DIR="$repo/platforms/archlinuxarm/boards/quartz64b"

# Fake clone into an isolated private directory; never contact GitHub here.
TMPDIR=$fixture
git() {
  [[ "$1" == clone && "$2" == --depth && "$3" == 1 && "$4" == --branch && "$5" == main ]] || return 1
  local target=$7
  mkdir -p "$target/platforms/archlinux/packages/metapackages/kde/noapps" \
    "$target/platforms/archlinux/packages/metapackages/nodesktop" \
    "$target/platforms/archlinux/assets/starship-presets" \
    "$target/platforms/archlinuxarm/boards/quartz64b"
  cp "$repo/platforms/archlinux/packages/metapackages/kde/noapps/PKGBUILD" "$target/platforms/archlinux/packages/metapackages/kde/noapps/PKGBUILD"
  cp "$repo/platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD" "$target/platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD"
  cp "$repo/platforms/archlinux/assets/starship-presets/tty-term.toml" "$target/platforms/archlinux/assets/starship-presets/tty-term.toml"
  cp "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh" "$target/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"
  cp "$repo/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" "$target/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
}
checkout=$(checkout_kmos)
[[ -x "$checkout/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" ]]
unset -f git

# Declining the initial confirmation must not invoke pacman or change the board.
ask_yes_no() { return 1; }
require_root_and_arm() { :; }
initialize_pacman() { printf 'Unexpected pacman initialization.\n' >&2; exit 1; }
if (main) > "$fixture/declined-output" 2>&1; then
  printf 'Declined provisioning unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -q 'Cancelado sin modificar el sistema' "$fixture/declined-output"

# Even an affirmative Wi-Fi answer is harmless when no adapter is present.
ask_yes_no() { return 0; }
detect_wifi_adapter() { return 1; }
configure_wifi 2> "$fixture/wifi-warning"
grep -q 'No se detecto adaptador Wi-Fi' "$fixture/wifi-warning"

pacman() {
  case "$1" in
    -Si) [[ "$2" != opencode && "$2" != syncthing ]] ;;
    -S) printf '%s\n' "$@" > "$fixture/packages-installed" ;;
    -Q) [[ "$2" != syncthing ]] ;;
    *) return 1 ;;
  esac
}
handle_unavailable_package() { :; }
install_kmos_packages "$repo"
printf '%s\n' "${SKIPPED_PACKAGES[@]}" | grep -qx opencode
printf '%s\n' "${SKIPPED_PACKAGES[@]}" | grep -qx syncthing
printf '%s\n' "${AVAILABLE_PACKAGES[@]}" | grep -qx ripgrep
if printf '%s\n' "${AVAILABLE_PACKAGES[@]}" | grep -qx opencode; then
  printf 'A skipped package was incorrectly marked available.\n' >&2
  exit 1
fi
grep -qx 'ripgrep' "$fixture/packages-installed"
if grep -Eq '^(opencode|syncthing)$' "$fixture/packages-installed"; then
  printf 'A skipped package was included in the installation.\n' >&2
  exit 1
fi

PRIMARY_USER=example
configure_syncthing 2> "$fixture/syncthing-warning"
grep -q 'Syncthing no esta instalado' "$fixture/syncthing-warning"
printf 'Quartz provisioner uses local KMOS files and honors skipped packages: OK.\n'
