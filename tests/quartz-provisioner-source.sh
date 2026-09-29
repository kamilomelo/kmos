#!/usr/bin/env bash
# Test repository discovery and package selection without touching a board.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"

[[ $(find_local_repository) == "$repo" ]]
if grep -q 'cat > /etc/systemd/network/25-wifi-dhcp.network' "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"; then
  printf 'Provisioning reintroduced competing networkd Wi-Fi DHCP.\n' >&2
  exit 1
fi
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
ask_yes_no() {
  [[ "$1" == 'Continue with provisioning and the full Arch Linux ARM update?' && "$2" == yes ]] || exit 1
  return 1
}
require_root_and_arm() { :; }
initialize_pacman() { printf 'Unexpected pacman initialization.\n' >&2; exit 1; }
if (main) > "$fixture/declined-output" 2>&1; then
  printf 'Declined provisioning unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -q 'Cancelled without modifying the system' "$fixture/declined-output"

# With consent, optional Wi-Fi precedes the first package stage, using this checkout.
(
  ask_yes_no() {
    [[ "$1" == 'Continue with provisioning and the full Arch Linux ARM update?' && "$2" == yes ]] || exit 1
    return 0
  }
  configure_wifi() { printf 'wifi\n' >> "$fixture/early-steps"; }
  initialize_pacman() { printf 'pacman\n' >> "$fixture/early-steps"; }
  install_kmos_packages() {
    [[ "$1" == "$repo" ]] || exit 1
    exit 0
  }
  main
)
[[ $(cat "$fixture/early-steps") == $'wifi\npacman' ]]

# Even an affirmative Wi-Fi answer is harmless when no adapter is present.
ask_yes_no() { [[ "$1" == 'Configure persistent Wi-Fi now?' && "$2" == yes ]]; }
detect_wifi_adapter() { return 1; }
configure_wifi 2> "$fixture/wifi-warning"
grep -q 'No Wi-Fi adapter detected' "$fixture/wifi-warning"
ask_yes_no() { return 0; }

# A deliberate Wi-Fi cancellation can finish only with an explicit Ethernet choice.
mkdir -p "$fixture/board/platforms/archlinuxarm/boards/quartz64b"
printf '#!/bin/sh\nexit 2\n' > "$fixture/board/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
chmod +x "$fixture/board/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
(
  REPOSITORY_DIR="$fixture/board"
  detect_wifi_adapter() { printf 'wlan0\n'; }
  ethernet_available() { return 0; }
  ask_yes_no() { [[ "$1" != 'iwd Wi-Fi was not verified. Try wpa_supplicant after updating over Ethernet?' ]]; }
  configure_wifi
  [[ -z "$WIFI_ADAPTER" ]]
)
(
  REPOSITORY_DIR="$fixture/board"
  detect_wifi_adapter() { printf 'wlan0\n'; }
  ethernet_available() { return 0; }
  configure_wifi
  [[ "$WIFI_FALLBACK_REQUESTED" == 1 && "$WIFI_ADAPTER" == wlan0 ]]
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
cat > "$fixture/board/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "${1:-iwd}" >> "$KMOS_WIFI_TEST_STEPS"
EOF
export KMOS_WIFI_TEST_STEPS="$fixture/wifi-steps"
(
  REPOSITORY_DIR="$fixture/board"
  detect_wifi_adapter() { printf 'wlan0\n'; }
  configure_wifi
  [[ "$WIFI_ADAPTER" == wlan0 ]]
)
[[ $(cat "$fixture/wifi-steps") == iwd ]]
(
  REPOSITORY_DIR="$fixture/board"
  WIFI_ADAPTER=wlan0
  WIFI_FALLBACK_REQUESTED=1
  pacman() { [[ "$*" == $'-S\n--needed\n--noconfirm\nwpa_supplicant' ]]; }
  configure_wpa_fallback_after_update
  [[ "$WIFI_BACKEND" == wpa ]]
)
[[ $(tail -n 1 "$fixture/wifi-steps") == --wpa-fallback ]]
(
  find_local_repository() { printf '%s\n' "$fixture/board"; }
  require_root_and_arm() { :; }
  pacman() {
    [[ "$1" != -Q ]] || return 1
    printf '%s\n' "$*" >> "$fixture/wpa-maintenance-packages"
  }
  ask_yes_no() { return 0; }
  board_maintenance wifi-fallback
)
grep -q -- '-Syu' "$fixture/wpa-maintenance-packages"
grep -q 'wpa_supplicant' "$fixture/wpa-maintenance-packages"
[[ $(tail -n 1 "$fixture/wifi-steps") == --wpa-fallback ]]
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

# Both Syncthing answers must allow provisioning to reach verification/finish.
(
  PRIMARY_USER='admin'
  pacman() { [[ "$1" == -Q && "$2" == syncthing ]]; }
  ask_yes_no() { return 1; }
  systemctl() { printf 'Syncthing was enabled despite being declined.\n' >&2; exit 1; }
  configure_syncthing
  printf 'continued\n' > "$fixture/syncthing-declined"
)
grep -qx continued "$fixture/syncthing-declined"
(
  PRIMARY_USER='admin'
  pacman() { [[ "$1" == -Q && "$2" == syncthing ]]; }
  ask_yes_no() { return 0; }
  systemctl() {
    [[ "$1" == enable && "$2" == --now && "$3" == syncthing@admin.service ]]
    return 1
  }
  configure_syncthing
  printf 'continued\n' > "$fixture/syncthing-failed"
) 2>"$fixture/syncthing-warning"
grep -qx continued "$fixture/syncthing-failed"
grep -q 'continuing installation' "$fixture/syncthing-warning"

# Do not replace an active swapfile if swapoff fails; inactive files need no swapoff.
printf 'Filename Type Size Used Priority\n/swapfile file 1024 0 -2\n' > "$fixture/swaps"
(
  swapoff() { [[ "$1" == /swapfile ]] && return 1; }
  if (disable_active_swapfile "$fixture/swaps") >"$fixture/swap-error" 2>&1; then
    printf 'Failed swapoff was accepted.\n' >&2
    exit 1
  fi
)
grep -q 'refusing to replace it' "$fixture/swap-error"
if (disable_active_swapfile "$fixture/missing-swaps") >"$fixture/swap-error" 2>&1; then
  printf 'Unreadable swap state was accepted.\n' >&2
  exit 1
fi
grep -q 'Could not inspect active swap' "$fixture/swap-error"
(
  swapoff() { [[ "$1" == /swapfile ]] && printf 'disabled\n' > "$fixture/swap-disabled"; }
  disable_active_swapfile "$fixture/swaps"
)
grep -qx disabled "$fixture/swap-disabled"
printf 'Filename Type Size Used Priority\n' > "$fixture/swaps"
(
  swapoff() { printf 'Inactive swapfile unexpectedly disabled.\n' >&2; exit 1; }
  disable_active_swapfile "$fixture/swaps"
)

# Verify live networking after installation, not just enabled unit files.
if (
  systemctl() { [[ "$3" != sshd.service ]]; }
  verify_runtime_network
) >"$fixture/no-ssh" 2>&1; then
  printf 'Inactive SSH service was accepted.\n' >&2
  exit 1
fi
grep -q 'sshd.service is not active' "$fixture/no-ssh"
(
  systemctl() { [[ "$1" == is-active && "$2" == --quiet ]]; }
  ip() { [[ "$1" == -4 && "$2" == route && "$3" == show && "$4" == default ]] && printf 'default via 192.0.2.1\n'; }
  curl() { [[ "$1" == --fail && "${!#}" == https://github.com/ ]]; }
  verify_runtime_network
)
if (
  systemctl() { [[ "$1" == is-active && "$2" == --quiet ]]; }
  ip() { :; }
  curl() { printf 'Internet probe must not run without a route.\n' >&2; exit 1; }
  verify_runtime_network
) >"$fixture/no-route" 2>&1; then
  printf 'Missing IPv4 default route was accepted.\n' >&2
  exit 1
fi
grep -q 'No IPv4 default route' "$fixture/no-route"
if (
  systemctl() { [[ "$1" == is-active && "$2" == --quiet ]]; }
  ip() { printf 'default via 192.0.2.1\n'; }
  curl() { return 1; }
  verify_runtime_network
) >"$fixture/no-internet" 2>&1; then
  printf 'Failed internet probe was accepted.\n' >&2
  exit 1
fi
grep -q 'Live internet access could not be verified' "$fixture/no-internet"

# Ethernet remains usable when optional Wi-Fi and Syncthing are declined; KDE stays disabled.
(
  find_local_repository() { printf '%s\n' "$repo"; }
  require_root_and_arm() { :; }
  ask_yes_no() { [[ "$1" != 'Configure persistent Wi-Fi now?' && "$1" != 'Enable Syncthing for admin?' ]]; }
  PRIMARY_USER='admin'
  pacman() { [[ "$1" == -Q && "$2" == syncthing ]]; }
  initialize_pacman() { :; }
  install_kmos_packages() { :; }
  install_kappa_mono_fonts() { printf 'fonts\n' >> "$fixture/steps"; }
  configure_kmos_terminal() { printf 'terminal\n' >> "$fixture/steps"; }
  configure_identity() { :; }
  create_administrator() { :; }
  configure_ssh() { :; }
  configure_networkd() { :; }
  configure_swap() { :; }
  remove_alarm() { :; }
  # shellcheck disable=SC2329 # An invocation here would fail this test.
  offer_kde_desktop() { printf 'KDE ran during headless provisioning.\n' >&2; exit 1; }
  detect_wifi_adapter() { printf 'Wi-Fi adapter detection ran after Wi-Fi was declined.\n' >&2; exit 1; }
  verify_installation() { printf 'verify\n' >> "$fixture/steps"; }
  offer_aur_helper() { printf 'aur\n' >> "$fixture/steps"; }
  verify_runtime_network() { printf 'network\n' >> "$fixture/steps"; }
  finish_installation() { printf 'finish\n' >> "$fixture/steps"; }
  main
)
[[ $(cat "$fixture/steps") == $'fonts\nterminal\nverify\naur\nnetwork\nfinish' ]]
printf 'Quartz provisioner uses local KMOS files and honors skipped packages: OK.\n'
