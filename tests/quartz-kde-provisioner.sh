#!/usr/bin/env bash
# Offline KDE selection tests: no real pacman, service changes or board access.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"
REPOSITORY_DIR=$repo

(
  ask_yes_no() { [[ "$1" == 'Do you want to install a desktop?' && "$2" == yes ]]; return 1; }
  pacman() { printf 'Unexpected package operation.\n' >&2; exit 1; }
  offer_kde_desktop
  [[ -z "$KDE_PROFILE" ]]
)

# The full x86 manifest is resolved, with absent ARM apps reported and
# NetworkManager/plasma-nm excluded even if available in a repository.
(
  kde_graphics_available() { return 0; }
  ask_yes_no() { printf '%s:%s\n' "$1" "$2" >> "$fixture/full-prompts"; return 0; }
  pacman() {
    case "$1" in
      -Si) [[ "$2" != firefox-developer-edition ]] ;;
      -Q) [[ "$2" == plasma-desktop || "$2" == plasma-workspace || "$2" == kwin || "$2" == sddm ]] ;;
      -S) printf '%s\n' "${@:4}" > "$fixture/full-installed" ;;
      *) return 1 ;;
    esac
  }
  systemctl() {
    if [[ "${!#}" == NetworkManager.service ]]; then return 1; fi
    case "$1" in
      enable|is-enabled) [[ "${!#}" == sddm.service ]] ;;
      set-default) [[ "$2" == graphical.target ]] ;;
      get-default) printf 'graphical.target\n' ;;
      *) return 1 ;;
    esac
  }
  configure_kde_terminal() { [[ "$1" == "$repo" ]] && touch "$fixture/full-assets"; }
  offer_kde_desktop <<< ''
  [[ "$KDE_PROFILE" == full ]]
) >"$fixture/full-output" 2>&1
[[ -e "$fixture/full-assets" ]]
for required in plasma-desktop plasma-workspace kwin sddm; do
  grep -qx "$required" "$fixture/full-installed"
done
for excluded in networkmanager networkmanager-openvpn plasma-nm plasma-login-manager firefox-developer-edition; do
  if grep -qx "$excluded" "$fixture/full-installed"; then
    printf 'Unsafe or missing KDE package was installed: %s\n' "$excluded" >&2
    exit 1
  fi
done
grep -q 'Unavailable ARM packages: firefox-developer-edition' "$fixture/full-output"
grep -q 'Skip these packages and continue with KDE?:yes' "$fixture/full-prompts"
grep -q 'Do you want to install a desktop?:yes' "$fixture/full-prompts"

# Minimal noapps profile omits the full profile's browsers and network stack.
(
  kde_graphics_available() { return 0; }
  ask_yes_no() { return 0; }
  pacman() {
    case "$1" in
      -Si) return 0 ;;
      -Q) return 0 ;;
      -S) printf '%s\n' "${@:4}" > "$fixture/noapps-installed" ;;
      *) return 1 ;;
    esac
  }
  systemctl() {
    if [[ "${!#}" == NetworkManager.service ]]; then return 1; fi
    case "$1" in
      enable|is-enabled) [[ "${!#}" == sddm.service ]] ;;
      set-default) [[ "$2" == graphical.target ]] ;;
      get-default) printf 'graphical.target\n' ;;
    esac
  }
  configure_kde_terminal() { :; }
  offer_kde_desktop <<< 'noapps'
  [[ "$KDE_PROFILE" == noapps ]]
) >"$fixture/noapps-output" 2>&1
grep -qx plasma-desktop "$fixture/noapps-installed"
if grep -Eq '^(firefox-developer-edition|networkmanager|plasma-nm)$' "$fixture/noapps-installed"; then
  printf 'noapps profile installed full/competing networking packages.\n' >&2
  exit 1
fi

# Without the essential compositor, stay headless and do not enable a display manager.
(
  kde_graphics_available() { return 0; }
  ask_yes_no() { return 0; }
  pacman() {
    if [[ "$1" == -Si ]]; then [[ "$2" != kwin ]];
    elif [[ "$1" == -Q ]]; then return 1;
    else printf 'Unexpected KDE installation with no compositor.\n' >&2; exit 1; fi
  }
  systemctl() { [[ "${!#}" != NetworkManager.service ]] || return 1; printf 'Unexpected service change.\n' >&2; exit 1; }
  offer_kde_desktop <<< 'noapps'
  [[ -z "$KDE_PROFILE" ]]
) >"$fixture/missing-core" 2>&1
grep -q 'Essential KDE component unavailable on ARM: kwin' "$fixture/missing-core"

# A failed pacman transaction never enables the graphical boot target.
if (
  kde_graphics_available() { return 0; }
  ask_yes_no() { return 0; }
  pacman() { [[ "$1" != -S ]]; }
  systemctl() {
    if [[ "${!#}" == NetworkManager.service ]]; then return 1; fi
    printf 'Graphical service changed after pacman failure.\n' >&2
    exit 1
  }
  configure_kde_terminal() { printf 'KDE assets changed after pacman failure.\n' >&2; exit 1; }
  offer_kde_desktop <<< 'noapps'
) >"$fixture/install-failed" 2>&1; then
  printf 'A failed KDE package install was reported successful.\n' >&2
  exit 1
fi
grep -q 'headless boot target was not changed' "$fixture/install-failed"

# No DRM requires explicit consent before proceeding.
(
  kde_graphics_available() { return 1; }
  ask_yes_no() { [[ "$1" != 'Try KDE without detected DRM graphics?' ]]; }
  pacman() { printf 'Unexpected package query without graphics consent.\n' >&2; exit 1; }
  offer_kde_desktop
  [[ -z "$KDE_PROFILE" ]]
) >"$fixture/no-graphics" 2>&1
grep -q 'No DRM graphics card was found' "$fixture/no-graphics"

# Maintenance KDE entry point requests an update before offering KDE, without
# repeating the full identity/provisioning path or triggering a reboot.
(
  find_local_repository() { printf '%s\n' "$repo"; }
  require_root_and_arm() { :; }
  ask_yes_no() { [[ "$1" == 'Update Arch Linux ARM and offer KDE?' && "$2" == no ]]; }
  pacman() { [[ "$*" == $'-Syu\n--needed\n--noconfirm' ]] && printf 'update\n' >> "$fixture/maintenance-steps"; }
  offer_kde_desktop() { printf 'desktop\n' >> "$fixture/maintenance-steps"; }
  verify_runtime_network() { printf 'network\n' >> "$fixture/maintenance-steps"; }
  board_maintenance kde
)
[[ $(cat "$fixture/maintenance-steps") == $'update\ndesktop\nnetwork' ]]
printf 'Quartz KDE profile selection, ARM skips, and Wi-Fi manager isolation: OK (mocked).\n'
