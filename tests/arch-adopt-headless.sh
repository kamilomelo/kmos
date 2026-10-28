#!/usr/bin/env bash
# Source-only fixture: never modify actual host accounts, packages, or settings.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/kmos-adopt-headless.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

"$script" --help > "$fixture/help"
grep -Fq -- '--preflight' "$fixture/help"
bash -n "$script"

(
  # shellcheck disable=SC1090
  source "$script"
  # Minimal Arch need not install the separate hostname executable.
  hostname() { printf 'Unexpected hostname command.\n' >&2; return 1; }
  [[ $(current_hostname) == "$(</proc/sys/kernel/hostname)" ]]
  eligible() { :; }
  installed() { [[ "$1" == nvidia-utils ]]; }
  has_nvidia() { return 0; }
  packages_for_host
  printf '%s\n' "${PACKAGES[@]}" > "$fixture/packages"
  [[ $(grep -xc fastfetch "$fixture/packages") == 1 ]]
  [[ $(grep -xc nvtop "$fixture/packages") == 1 ]]
  for pkg in btop opencode ripgrep starship syncthing tree zoxide git base-devel sudo nano openssh; do
    grep -Fxq "$pkg" "$fixture/packages"
  done
  [[ $(grep -xc openssh "$fixture/packages") == 1 ]]
  [[ $(grep -xc tododo-bin "$fixture/packages" || :) == 0 ]]
  valid_name admin_1
  if valid_name root || valid_name 'bad;name' || valid_name a/b; then exit 1; fi
)

(
  # shellcheck disable=SC1090
  source "$script"
  PRESETS="$fixture/source-presets"
  SHARE_KMOS="$fixture/share/kmos"
  STARSHIP_PROFILE="$fixture/etc/profile.d/10-kmos-starship.sh"
  BASHRC="$fixture/etc/bash.bashrc"
  mkdir -p "$PRESETS" "$fixture/etc"
  printf 'format = test\n' > "$PRESETS/tty-term.toml"
  install_appearance
  install_appearance
  sh -n "$STARSHIP_PROFILE"
  [[ $(grep -Fc '# kmos headless adoption' "$BASHRC") == 1 ]]
  [[ -f "$SHARE_KMOS/starship-presets/tty-term.toml" ]]
  printf 'personal preset\n' > "$SHARE_KMOS/starship-presets/tty-term.toml"
  install_appearance 2> "$fixture/appearance-warning"
  grep -Fxq 'personal preset' "$SHARE_KMOS/starship-presets/tty-term.toml"
  grep -Fq 'Differing preset preserved' "$fixture/appearance-warning"
  printf 'existing unrelated integration\nstarship init bash\n' > "$BASHRC"
  install_appearance 2> "$fixture/conflict-warning"
  [[ $(grep -Fc '# kmos headless adoption' "$BASHRC" || :) == 0 ]]
  grep -Fq 'integration skipped' "$fixture/conflict-warning"
)

(
  # shellcheck disable=SC1090
  source "$script"
  SUDO_USER=replacement
  regular_user() { [[ "$1" == oldadmin || "$1" == replacement ]]; }
  is_admin() { [[ "$1" == oldadmin || "$1" == replacement ]]; }
  regular_users() {
    printf 'oldadmin:x:1001:1001::/home/oldadmin:/bin/bash\nreplacement:x:1002:1002::/home/replacement:/bin/bash\n'
  }
  getent() { printf '%s:x:1001:1001::/home/%s:/bin/bash\n' "$2" "$2"; }
  loginctl() { :; }
  pgrep() { return 1; }
  input() { printf 'REMOVE oldadmin\n'; }
  ask() { return 1; } # Keep home, remove account only.
  userdel() { printf '%s\n' "$*" > "$fixture/removed"; }
  remove_account oldadmin
  [[ $(cat "$fixture/removed") == '-- oldadmin' ]]
  if remove_account replacement > "$fixture/self" 2>&1; then exit 1; fi
  grep -Fq 'current login' "$fixture/self"
  regular_users() { printf 'oldadmin:x:1001:1001::/home/oldadmin:/bin/bash\n'; }
  if remove_account oldadmin > "$fixture/last-admin" 2>&1; then exit 1; fi
  grep -Fq 'last regular administrator' "$fixture/last-admin"
  regular_users() { printf 'oldadmin:x:1001:1001::/home/oldadmin:/bin/bash\nreplacement:x:1002:1002::/home/replacement:/bin/bash\n'; }
  pgrep() { return 0; }
  if remove_account oldadmin > "$fixture/active" 2>&1; then exit 1; fi
  grep -Fq 'running processes' "$fixture/active"
)

(
  # shellcheck disable=SC1090
  source "$script"
  MARKER="$fixture/adopted"
  PACKAGES=(fastfetch starship openssh)
  USERS_CREATED=()
  SUDO_USER=builder
  preflight() { printf 'preflight\n' >> "$fixture/order"; }
  require_root() { :; }
  ask() { return 0; }
  input() { printf '2\n'; }
  create_accounts() { printf 'create\n' >> "$fixture/order"; }
  regular_user() { [[ "$1" == builder ]]; }
  is_admin() { [[ "$1" == builder ]]; }
  pacman() { printf 'pacman %s\n' "$*" >> "$fixture/order"; }
  configure_pacman_style() { :; } # Never touch the host's pacman.conf.
  choose_builder() { printf 'builder %s\n' "$1" >> "$fixture/order"; }
  enable_ssh() { printf 'enable sshd\n' >> "$fixture/order"; }
  offer_hostname() { printf 'hostname\n' >> "$fixture/order"; }
  install_aur() { printf 'aur %s\n' "$*" >> "$fixture/order"; }
  install_appearance() { printf 'appearance\n' >> "$fixture/order"; }
  remove_accounts() { printf 'remove\n' >> "$fixture/order"; }
  guided
  [[ $(cat "$fixture/order") == $'preflight\npacman -Syu --needed -- fastfetch starship openssh\nenable sshd\nhostname\ncreate\nbuilder builder\naur builder yay\nappearance\nremove' ]]
  [[ -f "$MARKER" ]]
)

(
  # Source-only hostname fixture: no real host or network settings are changed.
  # shellcheck disable=SC1090
  source "$script"
  for name in vps-01 vps-01.example.org a 7; do valid_hostname "$name"; done
  for name in '' '-vps' 'vps-' 'vps..example' 'vps.' 'vps_name' 'vps name' 'UPPER' "$(printf '%064d' 0)"; do
    if valid_hostname "$name"; then printf 'Accepted invalid hostname: %s\n' "$name" >&2; exit 1; fi
  done
  current_hostname() { printf 'old-vps\n'; }
  hostnamectl() { printf '%s\n' "$*" >> "$fixture/hostname-changes"; }
  ask() { return 1; }
  offer_hostname
  [[ ! -e "$fixture/hostname-changes" ]]
  ask() { return 0; }
  input() { printf 'new-vps.example.org\n'; }
  offer_hostname
  [[ $(cat "$fixture/hostname-changes") == 'set-hostname new-vps.example.org' ]]
  : > "$fixture/hostname-changes"
  ask() { [[ "$1" == 'Change hostname'* ]]; }
  offer_hostname
  [[ ! -s "$fixture/hostname-changes" ]]
  ask() { return 0; }
  input() { printf '\n'; }
  offer_hostname
  [[ ! -s "$fixture/hostname-changes" ]]
  input() {
    if [[ ! -e "$fixture/hostname-retry" ]]; then
      touch "$fixture/hostname-retry"
      printf 'bad_name\n'
    else
      printf 'fixed-vps\n'
    fi
  }
  offer_hostname 2> "$fixture/hostname-warning"
  grep -Fq 'Invalid hostname' "$fixture/hostname-warning"
  [[ $(cat "$fixture/hostname-changes") == 'set-hostname fixed-vps' ]]
)

(
  # shellcheck disable=SC1090
  source "$script"
  installed() { [[ "$1" == openssh ]]; }
  ssh-keygen() { printf 'keys %s\n' "$*" >> "$fixture/sshd-order"; }
  sshd() { printf 'validate %s\n' "$*" >> "$fixture/sshd-order"; }
  systemctl() {
    case "$1" in
      is-enabled) [[ -f "$fixture/sshd-enabled" ]] ;;
      is-active) [[ -f "$fixture/sshd-active" ]] ;;
      enable) touch "$fixture/sshd-enabled"; printf 'enable sshd\n' >> "$fixture/sshd-order" ;;
      start) touch "$fixture/sshd-active"; printf 'start sshd\n' >> "$fixture/sshd-order" ;;
      *) return 1 ;;
    esac
  }
  enable_ssh
  [[ $(cat "$fixture/sshd-order") == $'keys -A\nvalidate -t\nenable sshd\nstart sshd' ]]
  : > "$fixture/sshd-order"
  enable_ssh
  [[ $(cat "$fixture/sshd-order") == $'keys -A\nvalidate -t' ]]
  rm -f -- "$fixture/sshd-enabled" "$fixture/sshd-active"
  sshd() { return 1; }
  if enable_ssh > "$fixture/sshd-invalid" 2>&1; then exit 1; fi
  [[ ! -e "$fixture/sshd-enabled" && ! -e "$fixture/sshd-active" ]]
  grep -Fq 'configuration is invalid' "$fixture/sshd-invalid"
)

(
  # shellcheck disable=SC1090
  source "$script"
  # Installed helper, but tododo-bin must still be installed as the build user.
  paru() { :; }
  installed() { [[ "$1" == paru || -f "$fixture/tododo" && "$1" == tododo-bin ]]; }
  runuser() {
    [[ " $* " == *' --version '* ]] && return 0
    printf '%s\n' "$*" > "$fixture/aur-call"
    touch "$fixture/tododo"
  }
  install_aur builder paru
  [[ $(cat "$fixture/aur-call") == '-u builder -- paru -S --needed tododo-bin' ]]
  rm -f -- "$fixture/tododo"
  runuser() { :; }
  if install_aur builder paru > "$fixture/missing-aur" 2>&1; then exit 1; fi
  grep -Fq 'tododo-bin is mandatory' "$fixture/missing-aur"
)

(
  # shellcheck disable=SC1090
  source "$script"
  paru() { return 1; }
  yay() { [[ "$1" == --version ]]; }
  input() { printf '\n'; }
  [[ $(select_aur_helper) == paru ]]
  input() { printf '2\n'; }
  [[ $(select_aur_helper) == yay ]]
  yay() { return 1; }
  if select_aur_helper > "$fixture/broken-helper" 2>&1; then exit 1; fi
  grep -Fq 'cannot start' "$fixture/broken-helper"
  input() {
    if [[ ! -f "$fixture/helper-retry" ]]; then
      touch "$fixture/helper-retry"
      printf '9\n'
    else
      printf '1\n'
    fi
  }
  [[ $(select_aur_helper 2> "$fixture/invalid-helper") == paru ]]
  grep -Fq 'Invalid selection.' "$fixture/invalid-helper"
)

(
  # shellcheck disable=SC1090
  source "$script"
  installed() {
    case "$1" in
      paru-bin|paru-bin-debug|tododo-bin) return 0 ;;
      paru) [[ -f "$fixture/source-installed" ]] ;;
      *) return 1 ;;
    esac
  }
  chown() { :; }
  ask() { [[ "$1" != 'Approve removing '* || ! -e "$fixture/decline-removal" ]]; }
  pacman() {
    printf 'pacman %s\n' "$*" >> "$fixture/source-order"
    [[ "$1" == -U ]] && touch "$fixture/source-installed"
    return 0
  }
  helper_works() { [[ "$1" == paru && -f "$fixture/source-installed" ]]; }
  runuser() {
    case "$*" in
      *'git clone https://aur.archlinux.org/paru.git '*)
        printf '%s\n' "${@: -1}" > "$fixture/source-dir"
        mkdir -p "${@: -1}"
        printf 'pkgname=paru\n' > "${@: -1}/PKGBUILD" ;;
      *'makepkg -s'*) touch "$(cat "$fixture/source-dir")/paru-1-1-x86_64.pkg.tar.zst" ;;
      *'makepkg --packagelist'*) printf '%s/paru-1-1-x86_64.pkg.tar.zst\n' "$(cat "$fixture/source-dir")" ;;
      *'-- paru --version') : ;;
      *) printf 'Unexpected runuser: %s\n' "$*" >&2; return 1 ;;
    esac
  }
  install_aur builder paru > "$fixture/source-output"
  [[ $(cat "$fixture/source-order") == $'pacman -Syu --needed -- rust\npacman -R -- paru-bin-debug paru-bin\npacman -U -- '* ]]
  [[ ! -d $(cat "$fixture/source-dir") ]]
  grep -Fq 'pkgname=paru' "$fixture/source-output"
  rm -f -- "$fixture/source-installed" "$fixture/source-order"
  touch "$fixture/decline-removal"
  if install_source_paru builder > "$fixture/source-declined" 2>&1; then exit 1; fi
  [[ $(cat "$fixture/source-order") == 'pacman -Syu --needed -- rust' ]]
  grep -Fq 'preserved' "$fixture/source-declined"
)

(
  # shellcheck disable=SC1090
  source "$script"
  installed() { [[ "$1" == paru-bin ]]; }
  chown() { :; }
  ask() { return 0; }
  pacman() { printf '%s\n' "$*" >> "$fixture/build-failure-order"; }
  runuser() {
    case "$*" in
      *'git clone https://aur.archlinux.org/paru.git '*)
        mkdir -p "${@: -1}"
        printf 'pkgname=paru\n' > "${@: -1}/PKGBUILD" ;;
      *'makepkg -s'*) return 1 ;;
      *) return 1 ;;
    esac
  }
  if install_source_paru builder > "$fixture/build-failure" 2>&1; then exit 1; fi
  [[ $(cat "$fixture/build-failure-order") == '-Syu --needed -- rust' ]]
  grep -Fq 'installed AUR helpers were preserved' "$fixture/build-failure"
)

(
  # shellcheck disable=SC1090
  source "$script"
  regular_user() { [[ "$1" == kko || "$1" == fresh ]]; }
  is_admin() { [[ "$1" == kko || "$1" == fresh ]]; }
  SUDO_USER=kko
  [[ $(aur_builder) == kko ]]
  SUDO_USER=root USERS_CREATED=(fresh)
  [[ $(aur_builder) == fresh ]]
)

(
  # shellcheck disable=SC1090
  source "$script"
  require_root() { :; }
  preflight() { printf 'preflight\n' >> "$fixture/users-order"; }
  ask() { return 0; }
  repair_admin_sudo() { printf 'repair\n' >> "$fixture/users-order"; }
  create_accounts() { printf 'create\n' >> "$fixture/users-order"; }
  remove_accounts() { printf 'remove\n' >> "$fixture/users-order"; }
  pacman() { printf 'unexpected pacman\n' >> "$fixture/users-order"; return 1; }
  users_only
  [[ $(cat "$fixture/users-order") == $'preflight\nrepair\ncreate\nremove' ]]
)

(
  # shellcheck disable=SC1090
  source "$script"
  SUDO_RULE_DIR="$fixture/sudoers.d"
  regular_user() { [[ "$1" == builder ]]; }
  is_admin() { [[ "$1" == builder ]]; }
  sudo() { return 1; }
  ask() { return 1; }
  if ensure_admin_sudo builder > "$fixture/sudo-declined" 2>&1; then exit 1; fi
  [[ ! -e "$SUDO_RULE_DIR/20-kmos-adopt-builder" ]]
  grep -Fq 'builder ONLY' "$fixture/sudo-declined"
)

(
  # shellcheck disable=SC1090
  source "$script"
  marker="$fixture/created"
  ask() { if [[ ! -e "$marker" ]]; then return 0; fi; return 1; }
  input() { printf 'newadmin\n'; }
  getent() { return 2; }
  useradd() { printf '%s\n' "$*" > "$marker"; }
  passwd() { :; }
  add_key() { :; }
  ensure_admin_sudo() { printf '%s\n' "$1" > "$fixture/new-admin-sudo"; }
  create_accounts
  [[ $(cat "$marker") == '-m -s /bin/bash -G wheel newadmin' ]]
  [[ $(cat "$fixture/new-admin-sudo") == newadmin ]]
  [[ " ${USERS_CREATED[*]} " == *' newadmin '* ]]
  remove_accounts > "$fixture/remove-skipped" 2>&1
  grep -Fq 'No accounts will be removed' "$fixture/remove-skipped"
)

(
  # Declining a new admin's sudo grant must stop adoption, not claim success.
  # shellcheck disable=SC1090
  source "$script"
  ask() { [[ "$1" == 'Create a local user?' || "$1" == 'Grant '* ]]; }
  input() { printf 'unverified\n'; }
  getent() { return 2; }
  useradd() { :; }
  passwd() { :; }
  add_key() { :; }
  ensure_admin_sudo() { return 1; }
  if create_accounts > "$fixture/unverified-admin" 2>&1; then exit 1; fi
  [[ " ${USERS_CREATED[*]} " == *' unverified '* ]]
  grep -Fq 'does not have verified sudo access' "$fixture/unverified-admin"
)

(
  # Source-only sudo repair: no host sudoers or accounts are touched.
  # shellcheck disable=SC1090
  source "$script"
  SUDO_RULE_DIR="$fixture/sudoers.d"
  regular_user() { [[ "$1" == itadmin || "$1" == arch ]]; }
  is_admin() { [[ "$1" == itadmin || "$1" == arch ]]; }
  regular_users() { printf 'itadmin:x:1001:1001::/home/itadmin:/bin/bash\narch:x:1002:1002::/home/arch:/bin/bash\n'; }
  sudo() {
    [[ "$*" == *' -U arch '* ]] && return 0
    [[ "$*" == *' -U itadmin '* && -f "$SUDO_RULE_DIR/20-kmos-adopt-itadmin" && ! -L "$SUDO_RULE_DIR/20-kmos-adopt-itadmin" ]]
  }
  ask() { [[ "$1" == *itadmin* ]]; }
  visudo() { grep -Fxq 'itadmin ALL=(ALL:ALL) ALL' "${@: -1}"; }
  install() {
    if [[ "$1" == -m && "$3" == -o ]]; then command install -m "$2" "${@: -2}";
    else command install "$@"; fi
  }
  repair_admin_sudo
  [[ -f "$SUDO_RULE_DIR/20-kmos-adopt-itadmin" ]]
  [[ ! -e "$SUDO_RULE_DIR/20-kmos-adopt-arch" ]]
  [[ $(stat -c %a "$SUDO_RULE_DIR/20-kmos-adopt-itadmin") == 440 ]]
  repair_admin_sudo
  [[ $(find "$SUDO_RULE_DIR" -maxdepth 1 -type f | wc -l) == 1 ]]
  rm -f "$SUDO_RULE_DIR/20-kmos-adopt-itadmin"
  ln -s /dev/null "$SUDO_RULE_DIR/20-kmos-adopt-itadmin"
  if ensure_admin_sudo itadmin > "$fixture/sudo-conflict" 2>&1; then exit 1; fi
  [[ -L "$SUDO_RULE_DIR/20-kmos-adopt-itadmin" ]]
  grep -Fq 'needs manual review' "$fixture/sudo-conflict"
)

printf 'Arch VPS/headless adoption package, appearance, and account guards: OK (fixtures only).\n'
