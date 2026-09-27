#!/usr/bin/env bash
# Test repository discovery and package selection without touching a board.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"

[[ $(find_local_repository) == "$repo" ]]
if LC_ALL=C grep -q '[^ -~]' "$repo/platforms/archlinux/assets/starship-presets/tty-term.toml"; then
  printf 'Linux-console Starship preset contains non-ASCII glyphs.\n' >&2
  exit 1
fi
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

# Declining the initial confirmation must not invoke pacman or change the board.
ask_yes_no() { return 1; }
require_root_and_arm() { :; }
initialize_pacman() { printf 'Unexpected pacman initialization.\n' >&2; exit 1; }
if (main) > "$fixture/declined-output" 2>&1; then
  printf 'Declined provisioning unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -q 'Cancelled without modifying the system' "$fixture/declined-output"

# With consent, the first package stage must use this checkout, not re-clone.
(
  ask_yes_no() { return 0; }
  initialize_pacman() { :; }
  install_kmos_packages() {
    [[ "$1" == "$repo" ]] || exit 1
    exit 0
  }
  main
)

# Even an affirmative Wi-Fi answer is harmless when no adapter is present.
ask_yes_no() { return 0; }
detect_wifi_adapter() { return 1; }
configure_wifi 2> "$fixture/wifi-warning"
grep -q 'No Wi-Fi adapter detected' "$fixture/wifi-warning"

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
grep -q 'Syncthing is not installed' "$fixture/syncthing-warning"

# Stage KDE fonts and Konsole settings with a fake upstream clone and fake cache.
# All destination paths are below the temporary fixture; never touch the host.
git() {
  if [[ "$1" == clone ]]; then
    local target=${!#} style
    mkdir -p "$target/fonts/kappa-mono/ttf"
    for style in Regular Bold Italic BoldItalic; do
      printf 'fixture font\n' > "$target/fonts/kappa-mono/ttf/KappaMono-$style.ttf"
    done
  elif [[ "$1" == -C && "$3" == sparse-checkout && "$4" == set ]]; then
    [[ "$5" == fonts/kappa-mono/ttf ]]
  elif [[ "$1" == -C && "$3" == rev-parse && "$4" == HEAD ]]; then
    printf 'fixture-commit\n'
  else
    return 1
  fi
}
fc-cache() { [[ "$1" == -f && "$2" == "$fixture/root/usr/local/share/fonts/kmos" ]]; }
fc-match() { printf 'Kappa Mono\n'; }
TMPDIR=$fixture
install_kappa_mono_fonts "$fixture/root/usr/local/share/fonts/kmos"
for style in Regular Bold Italic BoldItalic; do
  [[ $(stat -c %a "$fixture/root/usr/local/share/fonts/kmos/KappaMono-$style.ttf") == 644 ]]
done
configure_kde_terminal "$repo" "$fixture/root"
grep -Fxq 'Font=Kappa Mono,11,-1,5,50,0,0,0,0,0' "$fixture/root/usr/share/konsole/kmos.profile"
grep -Fxq 'DefaultProfile=kmos.profile' "$fixture/root/etc/xdg/konsolerc"
printf 'user settings\n' > "$fixture/root/etc/xdg/konsolerc"
configure_kde_terminal "$repo" "$fixture/root" 2>/dev/null
grep -Fxq 'user settings' "$fixture/root/etc/xdg/konsolerc"
unset -f git fc-cache fc-match

# Ethernet remains usable through KDE; Wi-Fi is the final configuration gate.
(
  parse_arguments() { :; }
  find_local_repository() { printf '%s\n' "$repo"; }
  require_root_and_arm() { :; }
  ask_yes_no() { return 0; }
  initialize_pacman() { :; }
  install_kmos_packages() { :; }
  configure_kmos_terminal() { :; }
  configure_identity() { :; }
  create_administrator() { :; }
  configure_ssh() { :; }
  configure_networkd() { :; }
  configure_swap() { :; }
  configure_syncthing() { :; }
  remove_alarm() { :; }
  offer_kde_desktop() { printf 'kde\n' >> "$fixture/steps"; }
  configure_wifi() { printf 'wifi\n' >> "$fixture/steps"; }
  verify_installation() { printf 'verify\n' >> "$fixture/steps"; }
  main
)
[[ $(cat "$fixture/steps") == $'kde\nwifi\nverify' ]]
printf 'Quartz provisioner uses local KMOS files and honors skipped packages: OK.\n'
