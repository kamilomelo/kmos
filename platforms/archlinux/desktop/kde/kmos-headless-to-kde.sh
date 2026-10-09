#!/usr/bin/env bash
# Live-system KDE layer for an installed KMOS headless system; never formats.
# KDE_PACKAGES, METAPACKAGE_ROOT_DIR and post-install assets come from the
# sourced KDE scripts; those scripts consume the profile and AUR assignments.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/kmos-kde-package-select.sh"

usage() {
  cat <<'EOF'
Usage: ./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh
       ./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --preflight
       ./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --install [--profile full|noapps]
       ./platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh --install --select

--preflight is read-only and needs no root. --install adds KDE packages and
 fresh-user defaults; it never partitions disks, requests package removal, or
 switches network services. AUR is not installed. Pacman may offer replacements
 and upgrade existing packages; review its prompts before approving.
 Running without arguments guides package selection and confirmation.
 --select installs mandatory KDE base/apps and Firefox Developer Edition,
 then offers the Kamilo productivity set and extra repository packages.
 This live upgrade does not install AUR packages.
Use a backup and arrange local console or Ethernet access for the first test.
EOF
}

os_id() {
  # shellcheck disable=SC1091 # Standard local OS identity file.
  . /etc/os-release
  printf '%s\n' "${ID:-}"
}

package_installed() {
  command -v pacman >/dev/null 2>&1 && pacman -Qq "$1" >/dev/null 2>&1
}

service_state() {
  local state
  state=$(systemctl is-active "$1" 2>/dev/null) || :
  printf '%s\n' "${state:-unknown}"
}

service_enabled() {
  local state
  state=$(systemctl is-enabled "$1" 2>/dev/null) || :
  printf '%s\n' "${state:-unknown}"
}

headless_marker_present() {
  [[ -r /usr/share/kmos/metapackages/nodesktop/PKGBUILD ]]
}

kde_profile_present() {
  [[ -e /usr/share/kmos/kde-profile ]]
}

panel_template_available() {
  local template=/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
  [[ ! -L "$template" ]] || return 1
  [[ ! -e "$template" ]] && return 0
  # Allow retry after an interrupted KMOS staging pass, but never replace
  # someone else's fresh-user layout.
  [[ -f "$template" ]] && grep -Fxq 'plugin=org.kde.plasma.kickerdash' "$template" &&
    grep -Fxq 'plugin=org.kde.plasma.systemmonitor.kmos-cpu-gpu' "$template"
}

upgrade_in_progress() {
  [[ -f /var/lib/kmos/headless-to-kde.in-progress && ! -L /var/lib/kmos/headless-to-kde.in-progress ]]
}

mark_upgrade() {
  [[ ! -L /var/lib/kmos && ! -L /var/lib/kmos/headless-to-kde.in-progress ]] || return 1
  install -Dm0644 /dev/stdin /var/lib/kmos/headless-to-kde.in-progress <<< "$1"
}

clear_upgrade() {
  rm -f -- /var/lib/kmos/headless-to-kde.in-progress
}

preflight() {
  local id iface transport pkg service
  [[ -r /etc/os-release ]] || { printf 'Cannot identify this operating system.\n' >&2; return 1; }
  id=$(os_id)
  [[ "$id" == arch ]] || { printf 'Only installed Arch Linux x86_64 is supported (found %s).\n' "$id" >&2; return 1; }
  [[ $(uname -m) == x86_64 ]] || { printf 'Only x86_64 is supported.\n' >&2; return 1; }
  headless_marker_present || {
    printf 'KMOS headless base marker not found; do not use the upgrade path on this system.\n' >&2
    return 1
  }

  printf 'KMOS headless base: present\n'
  if package_installed plasma-desktop || package_installed sddm || kde_profile_present; then
    printf 'KDE/SDDM already present: yes (upgrade path must not overwrite it)\n'
  else
    printf 'KDE/SDDM already present: no\n'
  fi

  printf 'Default-route interface: '
  iface=$(ip -o -4 route show default 2>/dev/null | awk '{for (i=1; i<NF; i++) if ($i == "dev") {print $(i+1); exit}}') || :
  if [[ -z "$iface" ]]; then
    printf 'not detected\n'
  else
    transport=Ethernet-or-other
    [[ -d "/sys/class/net/$iface/wireless" ]] && transport=Wi-Fi
    printf '%s (%s)\n' "$iface" "$transport"
  fi

  for pkg in networkmanager iwd dhcpcd wpa_supplicant openssh impala; do
    if package_installed "$pkg"; then
      printf 'Package %-16s installed\n' "$pkg"
    else
      printf 'Package %-16s absent\n' "$pkg"
    fi
  done
  for service in NetworkManager.service iwd.service dhcpcd.service sshd.service sddm.service; do
    printf 'Service %-23s active=%s enabled=%s\n' "$service" \
      "$(service_state "$service")" "$(service_enabled "$service")"
  done
  if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]]; then
    printf 'This shell is over SSH: yes (do not interrupt the active network)\n'
  else
    printf 'This shell is over SSH: no / not detected\n'
  fi
  printf 'Preflight complete: nothing was changed.\n'
}

resolve_kde_packages() (
  local profile="$1"
  shift
  # The ISO KDE stage already defines the package sets. Source it without
  # running its mounted-target installer, prune list or network migration.
  # shellcheck disable=SC1090,SC1091
  source "$SCRIPT_DIR/kmos-kde-install.sh"
  # Both paths use the same package selection and resolver. Never fall back
  # to published main manifests during an experimental live upgrade.
  KDE_PROFILE="$profile" INSTALL_AUR=no KDE_LOCAL_MANIFESTS_ONLY=yes
  if [[ "$profile" == custom ]]; then
    SELECTED_METAPACKAGES=(kmos-kde-base kmos-kde-apps kmos-desktop-productivity "$@")
  else
    select_kde_metapackages
  fi
  load_kde_metapackages
  printf '%s\n' "${KDE_PACKAGES[@]}"
)

stage_live_defaults() (
  local home_dir username cfg
  # Source only the fresh-user staging functions. Do not call apply_post_tweaks:
  # it removes fonts, changes existing user configs and runs the AUR installer.
  # shellcheck disable=SC1090,SC1091
  source "$SCRIPT_DIR/kmos-kde-post.sh"
  MOUNT_POINT=/
  KDE_PROFILE="$1"
  stage_repo_assets
  [[ -e /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc ]] || install_fresh_kmos_panel
  apply_desktop_wallpaper_defaults
  [[ -r "$ASSET_COLOR_SCHEME" ]] || die 'KMOS color scheme missing.'
  install -Dm0644 "$ASSET_COLOR_SCHEME" /usr/share/color-schemes/kmos.colors
  install_lookandfeel_defaults
  write_color_scheme_autostart /usr/share/kmos/bin/kmos-apply-colorscheme.sh \
    /etc/xdg/autostart/kmos-apply-colorscheme.desktop
  cfg=/etc/skel/.config/kdeglobals
  [[ -e "$cfg" || -L "$cfg" ]] || write_kdeglobals_defaults "$cfg"
  if [[ -d /home ]]; then
    while IFS= read -r -d '' home_dir; do
      cfg="$home_dir/.config/kdeglobals"
      [[ ! -L "$home_dir" && ! -L "$home_dir/.config" ]] || continue
      [[ ! -e "$cfg" && ! -L "$cfg" ]] || continue
      username="${home_dir##*/}"
      [[ $(id -u "$username" 2>/dev/null || true) =~ ^[0-9]+$ ]] || continue
      write_kdeglobals_defaults "$cfg"
      chown "$username:$username" "$home_dir/.config" "$cfg"
    done < <(find /home -mindepth 1 -maxdepth 1 -type d -print0)
  fi
)

confirm_install() {
  local answer
  printf 'KDE packages will be installed; pacman may upgrade existing packages.\n' >&2
  printf 'Wi-Fi (iwd/dhcpcd) and sshd will not be switched or disabled by KMOS.\n' >&2
  printf 'Type INSTALL KDE to continue: ' >&2
  read -r answer </dev/tty || return 1
  [[ "$answer" == 'INSTALL KDE' ]]
}

require_root() {
  (( EUID == 0 )) && return 0
  command -v sudo >/dev/null 2>&1 || { printf 'sudo is required for --install.\n' >&2; return 1; }
  exec sudo -- "$SCRIPT_DIR/kmos-headless-to-kde.sh" "$@"
}

install_layer() {
  local profile="$1" pkg list before_iwd before_dhcpcd before_nm before_nm_enabled
  local -a packages=()
  preflight
  if kde_profile_present; then
    printf 'KMOS KDE layer is already recorded; no changes made.\n'
    return 0
  fi
  if upgrade_in_progress && [[ $(cat /var/lib/kmos/headless-to-kde.in-progress) != "$profile" ]]; then
    printf 'An interrupted upgrade used a different profile; review before retrying.\n' >&2
    return 1
  fi
  if ! upgrade_in_progress && { package_installed plasma-desktop || package_installed sddm; }; then
    printf 'An existing KDE/SDDM install needs manual review; refusing to alter it.\n' >&2
    return 1
  fi
  panel_template_available || {
    printf 'A fresh-user panel template already exists; refusing to replace it.\n' >&2; return 1;
  }
  [[ -r "$SCRIPT_DIR/kmos-kde-install.sh" && -r "$SCRIPT_DIR/kmos-kde-post.sh" ]] || {
    printf 'Full local KDE installer sources are required.\n' >&2; return 1;
  }
  # Reject missing local manifests instead of silently pulling main's files.
  [[ -r "$SCRIPT_DIR/../../packages/metapackages/kde/base/PKGBUILD" ]] || {
    printf 'KDE package manifests are missing.\n' >&2; return 1;
  }
  if [[ "$profile" == custom ]]; then
    require_root --install --select || return 1
    select_live_packages || { printf 'Selection cancelled; nothing installed.\n' >&2; return 1; }
    list=$(resolve_kde_packages "$profile" "${SELECTED_KDE_METAPACKAGES[@]}") || return 1
  else
    list=$(resolve_kde_packages "$profile") || return 1
  fi
  mapfile -t packages <<< "$list"
  packages+=("${EXTRA_KDE_PACKAGES[@]}")
  ((${#packages[@]} > 0)) || { printf 'No KDE packages resolved.\n' >&2; return 1; }
  for pkg in "${packages[@]}"; do
    [[ "$pkg" =~ ^[a-zA-Z0-9@._+-]+$ ]] || { printf 'Invalid package: %s\n' "$pkg" >&2; return 1; }
  done
  printf 'KDE profile: %s; packages: %s; AUR: no\n' "$profile" "${#packages[@]}"
  printf 'NetworkManager may be installed as a KDE dependency but will NOT be enabled.\n'
  if [[ "$profile" != custom ]]; then require_root --install --profile "$profile"; fi
  confirm_install || { printf 'Cancelled without changes.\n' >&2; return 1; }
  mark_upgrade "$profile" || { printf 'Cannot record an upgrade attempt; no packages installed.\n' >&2; return 1; }
  before_iwd=$(service_state iwd.service)
  before_dhcpcd=$(service_state dhcpcd.service)
  before_nm=$(service_state NetworkManager.service)
  before_nm_enabled=$(service_enabled NetworkManager.service)
  # Never call pacman -R, touch disk layout, restart network, or stop sshd.
  pacman -Syu --needed -- "${packages[@]}" || return 1
  if [[ "$before_iwd" == active && $(service_state iwd.service) != active ]] ||
      [[ "$before_dhcpcd" == active && $(service_state dhcpcd.service) != active ]] ||
      [[ "$before_nm" != active && $(service_state NetworkManager.service) == active ]] ||
      [[ "$before_nm_enabled" != enabled && $(service_enabled NetworkManager.service) == enabled ]]; then
    printf 'Network service changed during package update; check connectivity before continuing.\n' >&2
    return 1
  fi
  stage_live_defaults "$profile" || return 1
  systemctl enable sddm.service || return 1
  systemctl set-default graphical.target || return 1
  install -Dm0644 /dev/stdin /usr/share/kmos/kde-profile <<< "$profile" || return 1
  clear_upgrade || return 1
  printf 'KDE staged. Network services were not switched. Reboot when you are ready.\n'
}

main() {
  case "${1:---guided}" in
    --guided) (( $# == 0 )) || { usage >&2; return 2; }; install_layer custom ;;
    --help|-h) (( $# <= 1 )) || { usage >&2; return 2; }; usage ;;
    --preflight) (( $# == 1 )) || { usage >&2; return 2; }; preflight ;;
    --install)
      local profile=full
      if (( $# == 2 )) && [[ "$2" == --select ]]; then profile=custom
      elif (( $# == 3 )) && [[ "$2" == --profile ]]; then profile="$3"
      elif (( $# != 1 )); then usage >&2; return 2
      fi
      [[ "$profile" == full || "$profile" == noapps || "$profile" == custom ]] || { usage >&2; return 2; }
      install_layer "$profile"
      ;;
    *) usage >&2; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
