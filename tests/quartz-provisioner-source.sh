#!/usr/bin/env bash
# Test repository discovery and package selection without touching a board.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"

[[ $(find_local_repository) == "$repo" ]]
if LC_ALL=C grep -q '[^ -~]' "$repo/platforms/archlinuxarm/boards/quartz64b/assets/starship-headless.toml"; then
  printf 'Quartz64 headless Starship preset contains non-ASCII glyphs.\n' >&2
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
# shellcheck disable=SC2329 # Used by the sourced provisioner's main function.
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

# A deliberate Wi-Fi cancellation can finish only with an explicit Ethernet choice.
mkdir -p "$fixture/board/platforms/archlinuxarm/boards/quartz64b"
printf '#!/bin/sh\nexit 2\n' > "$fixture/board/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
chmod +x "$fixture/board/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
(
  REPOSITORY_DIR="$fixture/board"
  detect_wifi_adapter() { printf 'wlan0\n'; }
  ethernet_available() { return 0; }
  configure_wifi
  [[ -z "$WIFI_ADAPTER" ]]
)
if (
  REPOSITORY_DIR="$fixture/board"
  detect_wifi_adapter() { printf 'wlan0\n'; }
  ethernet_available() { return 1; }
  configure_wifi
) >"$fixture/no-ethernet" 2>&1; then
  printf 'Wi-Fi cancellation incorrectly succeeded without Ethernet.\n' >&2
  exit 1
fi
grep -q 'Provisioning stopped' "$fixture/no-ethernet"
REPOSITORY_DIR=$repo

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
if printf '%s\n' "${SKIPPED_PACKAGES[@]}" | grep -qx starship; then
  printf 'Required Starship package was incorrectly skipped.\n' >&2
  exit 1
fi
if grep -Eq '^(opencode|syncthing)$' "$fixture/packages-installed"; then
  printf 'A skipped package was included in the installation.\n' >&2
  exit 1
fi

PRIMARY_USER=example
configure_syncthing 2> "$fixture/syncthing-warning"
grep -q 'Syncthing is not installed' "$fixture/syncthing-warning"

# Stage headless Kappa Mono fonts with a fake upstream clone and fake cache.
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
(
  # Headless boards need the TTFs, but must not require a new fontconfig package.
  # shellcheck disable=SC2329 # Invoked indirectly by the sourced installer.
  command() {
    if [[ "$1" == -v && ( "$2" == fc-cache || "$2" == fc-match ) ]]; then return 1; fi
    builtin command "$@"
  }
  install_kappa_mono_fonts "$fixture/no-fontconfig/fonts" >"$fixture/no-fontconfig-output" 2>&1
)
[[ -s "$fixture/no-fontconfig/fonts/KappaMono-Regular.ttf" ]]
grep -q 'no extra package was added' "$fixture/no-fontconfig-output"
configure_kde_terminal "$repo" "$fixture/root"
grep -Fxq 'Font=Kappa Mono,11,-1,5,50,0,0,0,0,0' "$fixture/root/usr/share/konsole/kmos.profile"
grep -Fxq 'DefaultProfile=kmos.profile' "$fixture/root/etc/xdg/konsolerc"
printf 'user settings\n' > "$fixture/root/etc/xdg/konsolerc"
configure_kde_terminal "$repo" "$fixture/root" 2>/dev/null
grep -Fxq 'user settings' "$fixture/root/etc/xdg/konsolerc"
unset -f git fc-cache fc-match

# SSH uses the x86 KMOS Nerd Font preset; the physical TTY keeps ASCII.
# Existing bashrc lines must not override the new selection.
mkdir -p "$fixture/headless/etc"
printf '# kmos headless shell\nexport STARSHIP_CONFIG=/usr/share/kmos/starship-presets/holow-light.toml\n' > "$fixture/headless/etc/bash.bashrc"
configure_kmos_terminal "$repo" "$fixture/headless"
[[ -r "$fixture/headless/usr/share/kmos/starship-presets/quartz-headless.toml" ]]
[[ -r "$fixture/headless/usr/share/kmos/starship-presets/holow-light.toml" ]]
[[ $(grep -c '^# kmos headless shell$' "$fixture/headless/etc/bash.bashrc") == 1 ]]
grep -q '^# kmos Quartz64 headless prompt$' "$fixture/headless/etc/bash.bashrc"
bash -n "$fixture/headless/etc/bash.bashrc" "$fixture/headless/etc/profile.d/10-kmos-starship.sh"
(
  # shellcheck disable=SC2030 # TERM is intentionally isolated for SSH.
  export XDG_CURRENT_DESKTOP=KDE SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22' TERM=xterm-256color
  # shellcheck disable=SC1091
  source "$fixture/headless/etc/profile.d/10-kmos-starship.sh"
  [[ "$STARSHIP_CONFIG" == /usr/share/kmos/starship-presets/holow-light.toml ]]
)
(
  unset SSH_CONNECTION SSH_TTY SSH_CLIENT
  # shellcheck disable=SC2031 # This subshell deliberately tests a different TERM.
  export TERM=linux
  # shellcheck disable=SC1091
  source "$fixture/headless/etc/profile.d/10-kmos-starship.sh"
  [[ "$STARSHIP_CONFIG" == /usr/share/kmos/starship-presets/quartz-headless.toml ]]
)
if command -v starship >/dev/null 2>&1; then
  STARSHIP_CONFIG="$fixture/headless/usr/share/kmos/starship-presets/quartz-headless.toml" \
    STARSHIP_LOG=warn starship prompt >"$fixture/prompt" 2>"$fixture/prompt-errors"
  [[ ! -s "$fixture/prompt-errors" && -s "$fixture/prompt" ]]
  SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22' \
    STARSHIP_CONFIG="$fixture/headless/usr/share/kmos/starship-presets/holow-light.toml" \
    STARSHIP_LOG=warn starship prompt >"$fixture/ssh-prompt" 2>"$fixture/ssh-prompt-errors"
  [[ ! -s "$fixture/ssh-prompt-errors" && -s "$fixture/ssh-prompt" ]]
  if cmp -s "$fixture/prompt" "$fixture/ssh-prompt"; then
    printf 'SSH prompt unexpectedly matched the ASCII TTY prompt.\n' >&2
    exit 1
  fi
  KMOS_PROFILE_TEST="$fixture/headless/etc/profile.d/10-kmos-starship.sh" \
    SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22' TERM=xterm-256color \
    bash --noprofile --norc -ic \
    'source "$KMOS_PROFILE_TEST"; [[ "$STARSHIP_CONFIG" == /usr/share/kmos/starship-presets/holow-light.toml && "${PROMPT_COMMAND:-}" == *starship_precmd* ]]' \
    >"$fixture/login-output" 2>&1
fi

# Ethernet remains usable; neither KDE nor Wi-Fi runs during headless provisioning.
(
  find_local_repository() { printf '%s\n' "$repo"; }
  require_root_and_arm() { :; }
  ask_yes_no() { return 0; }
  initialize_pacman() { :; }
  install_kmos_packages() { :; }
  install_kappa_mono_fonts() { printf 'fonts\n' >> "$fixture/steps"; }
  configure_kmos_terminal() { printf 'terminal\n' >> "$fixture/steps"; }
  configure_identity() { :; }
  create_administrator() { :; }
  configure_ssh() { :; }
  configure_networkd() { :; }
  configure_swap() { :; }
  configure_syncthing() { :; }
  remove_alarm() { :; }
  # shellcheck disable=SC2329 # An invocation here would fail this test.
  offer_kde_desktop() { printf 'KDE ran during headless provisioning.\n' >&2; exit 1; }
  # shellcheck disable=SC2329 # An invocation here would fail this test.
  configure_wifi() { printf 'Wi-Fi ran during headless provisioning.\n' >&2; exit 1; }
  verify_installation() { printf 'verify\n' >> "$fixture/steps"; }
  offer_aur_helper() { printf 'aur\n' >> "$fixture/steps"; }
  main
)
[[ $(cat "$fixture/steps") == $'fonts\nterminal\nverify\naur' ]]
printf 'Quartz provisioner uses local KMOS files and honors skipped packages: OK.\n'
