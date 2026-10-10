#!/usr/bin/env bash
# Mocked preflight and upgrade; never install packages on the host.
# Mock functions are consumed by the sourced preflight.
# shellcheck disable=SC2329,SC2034,SC1090
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

"$script" --help > "$fixture/help"
grep -Fq -- '--install [--profile full|noapps]' "$fixture/help"
if "$script" --install --profile invalid > "$fixture/rejected" 2>&1; then
  printf 'Unexpectedly accepted an invalid installation profile.\n' >&2; exit 1
fi
grep -Fq -- '--preflight' "$fixture/rejected"

(
  # shellcheck disable=SC1091 # Sourced entry point is guarded against execution.
  source "$script"
  os_id() { printf 'arch\n'; }
  uname() { printf 'x86_64\n'; }
  headless_marker_present() { :; }
  kde_profile_present() { return 1; }
  package_installed() { [[ "$1" == iwd || "$1" == openssh ]]; }
  ip() { printf 'default via 192.0.2.1 dev eth0 proto dhcp\n'; }
  service_state() { [[ "$1" == sshd.service ]] && printf 'active\n' || printf 'inactive\n'; }
  service_enabled() { [[ "$1" == sshd.service ]] && printf 'enabled\n' || printf 'disabled\n'; }
  SSH_CONNECTION='fixture-only'
  preflight
) > "$fixture/report"
grep -Fq 'Default-route interface: eth0' "$fixture/report"
grep -Fq 'Package iwd              installed' "$fixture/report"
grep -Fq 'Service sshd.service            active=active enabled=enabled' "$fixture/report"
grep -Fq 'This shell is over SSH: yes' "$fixture/report"
grep -Fq 'Preflight complete: nothing was changed.' "$fixture/report"

if (
  # shellcheck disable=SC1091
  source "$script"
  os_id() { printf 'rocky\n'; }
  preflight
) > "$fixture/wrong-os" 2>&1; then
  printf 'Preflight accepted a different operating system.\n' >&2; exit 1
fi
grep -Fq 'Only installed Arch Linux x86_64 is supported' "$fixture/wrong-os"

# The live-system path must not run the ISO KDE installer's package removal,
# Wi-Fi migration, or network service switches. All commands are mocked.
(
  # shellcheck disable=SC1091
  source "$script"
  preflight() { printf 'preflight\n' >> "$fixture/order"; }
  kde_profile_present() { return 1; }
  upgrade_in_progress() { return 1; }
  package_installed() { return 1; }
  panel_template_available() { :; }
  resolve_kde_packages() { printf 'plasma-desktop\nsddm\nnetworkmanager\n'; }
  require_root() { printf 'root-check\n' >> "$fixture/order"; }
  confirm_install() { printf 'confirm\n' >> "$fixture/order"; }
  mark_upgrade() { printf 'mark-upgrade\n' >> "$fixture/order"; }
  clear_upgrade() { printf 'clear-upgrade\n' >> "$fixture/order"; }
  pacman() {
    [[ "$1" == -Syu && "$2" == --needed && "$3" == -- ]] || return 1
    printf 'packages\n' >> "$fixture/order"
  }
  service_state() { printf 'active\n'; }
  service_enabled() { printf 'disabled\n'; }
  stage_live_defaults() { printf 'defaults\n' >> "$fixture/order"; }
  install() {
    [[ "$1" == -Dm0644 && "$2" == /dev/stdin && "$3" == /usr/share/kmos/kde-profile ]] || return 1
    cat > "$fixture/profile"
    printf 'record-profile\n' >> "$fixture/order"
  }
  systemctl() {
    case "$*" in
      'enable sddm.service'|'set-default graphical.target') printf '%s\n' "$*" >> "$fixture/order" ;;
      *) printf 'Network service changed: %s\n' "$*" >&2; return 1 ;;
    esac
  }
  install_layer noapps
) > "$fixture/install-report"
[[ $(cat "$fixture/order") == $'preflight\nroot-check\nconfirm\nmark-upgrade\npackages\ndefaults\nenable sddm.service\nset-default graphical.target\nrecord-profile\nclear-upgrade' ]]
[[ $(cat "$fixture/profile") == noapps ]]
grep -Fq 'Active networking stays unchanged; guided mode may offer next-boot NetworkManager staging.' "$fixture/install-report"

(
  # shellcheck disable=SC1091
  source "$script"
  preflight() { :; }
  kde_profile_present() { :; }
  pacman() { printf 'Packages changed on second run.\n' >&2; return 1; }
  install_layer full
) > "$fixture/second-run"
grep -Fq 'already recorded; no changes made' "$fixture/second-run"

if (
  # shellcheck disable=SC1091
  source "$script"
  preflight() { :; }
  kde_profile_present() { return 1; }
  upgrade_in_progress() { return 1; }
  package_installed() { [[ "$1" == plasma-desktop ]]; }
  pacman() { printf 'Preexisting KDE was changed.\n' >&2; return 1; }
  install_layer full
) > "$fixture/existing-kde" 2>&1; then
  printf 'Preexisting KDE was accepted for upgrade.\n' >&2; exit 1
fi
grep -Fq 'existing KDE/SDDM install needs manual review' "$fixture/existing-kde"

if (
  # shellcheck disable=SC1091
  source "$script"
  preflight() { :; }
  kde_profile_present() { return 1; }
  upgrade_in_progress() { return 1; }
  package_installed() { return 1; }
  panel_template_available() { return 1; }
  pacman() { printf 'Unexpected package operation.\n' >&2; return 1; }
  install_layer full
) > "$fixture/panel-refusal" 2>&1; then
  printf 'An existing panel template was accepted for replacement.\n' >&2; exit 1
fi
grep -Fq 'refusing to replace it' "$fixture/panel-refusal"

if (
  # shellcheck disable=SC1091
  source "$script"
  preflight() { :; }
  kde_profile_present() { return 1; }
  upgrade_in_progress() { return 1; }
  package_installed() { return 1; }
  panel_template_available() { :; }
  resolve_kde_packages() { printf 'plasma-desktop\n'; }
  require_root() { :; }
  confirm_install() { :; }
  mark_upgrade() { :; }
  service_state() { printf 'active\n'; }
  service_enabled() { printf 'disabled\n'; }
  pacman() { return 1; }
  stage_live_defaults() { printf 'Defaults changed after package failure.\n' >&2; return 1; }
  systemctl() { printf 'Services changed after package failure.\n' >&2; return 1; }
  install_layer noapps
) > "$fixture/failed-packages" 2>&1; then
  printf 'A failed package transaction was accepted.\n' >&2; exit 1
fi
if grep -Eq 'Defaults changed|Services changed' "$fixture/failed-packages"; then
  printf 'Staging proceeded after a failed package transaction.\n' >&2; exit 1
fi

if (
  # shellcheck disable=SC1091
  source "$script"
  preflight() { :; }
  kde_profile_present() { return 1; }
  upgrade_in_progress() { return 1; }
  package_installed() { return 1; }
  panel_template_available() { :; }
  resolve_kde_packages() { printf 'plasma-desktop\n'; }
  require_root() { :; }
  confirm_install() { :; }
  mark_upgrade() { :; }
  service_state() {
    if [[ "$1" == iwd.service && -e "$fixture/pacman-ran" ]]; then
      printf 'inactive\n'
    else
      printf 'active\n'
    fi
  }
  service_enabled() { printf 'disabled\n'; }
  pacman() { : > "$fixture/pacman-ran"; }
  stage_live_defaults() { printf 'Defaults changed despite lost Wi-Fi.\n' >&2; return 1; }
  systemctl() { printf 'Services changed despite lost Wi-Fi.\n' >&2; return 1; }
  install_layer full
) > "$fixture/lost-wifi" 2>&1; then
  printf 'Install continued after the active Wi-Fi service stopped.\n' >&2; exit 1
fi
grep -Fq 'Network service changed' "$fixture/lost-wifi"
if grep -Eq 'Defaults changed|Services changed' "$fixture/lost-wifi"; then
  printf 'Staging continued after loss of Wi-Fi.\n' >&2; exit 1
fi

(
  # shellcheck disable=SC1091
  source "$repo/platforms/archlinux/desktop/kde/kmos-kde-post.sh"
  MOUNT_POINT=/
  chown() { printf '%s\n' "$*" > "$fixture/live-chown"; }
  arch-chroot() { printf 'Chroot attempted on live /.\n' >&2; return 1; }
  target_chown fixture:fixture /home/fixture/.config
)
[[ $(cat "$fixture/live-chown") == 'fixture:fixture /home/fixture/.config' ]]

printf 'Headless KDE preflight and network-preserving stage ordering: OK (mocked only).\n'
