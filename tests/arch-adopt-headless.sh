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
  input() { case "$1" in AUR*) printf 'yay\n' ;; *) printf 'builder\n' ;; esac; }
  create_accounts() { :; }
  regular_user() { [[ "$1" == builder ]]; }
  is_admin() { [[ "$1" == builder ]]; }
  pacman() { printf 'pacman %s\n' "$*" >> "$fixture/order"; }
  choose_builder() { printf 'builder %s\n' "$1" >> "$fixture/order"; }
  enable_ssh() { printf 'enable sshd\n' >> "$fixture/order"; }
  install_aur() { printf 'aur %s\n' "$*" >> "$fixture/order"; }
  install_appearance() { printf 'appearance\n' >> "$fixture/order"; }
  remove_accounts() { printf 'remove\n' >> "$fixture/order"; }
  guided
  [[ $(cat "$fixture/order") == $'preflight\npacman -Syu --needed -- fastfetch starship openssh\nenable sshd\nbuilder builder\naur builder yay\nappearance\nremove' ]]
  [[ -f "$MARKER" ]]
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
  installed() { [[ -f "$fixture/tododo" && "$1" == tododo-bin ]]; }
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
  [[ $(select_aur_helper) == yay ]]
  input() { printf 'paru\n'; }
  if select_aur_helper > "$fixture/broken-helper" 2>&1; then exit 1; fi
  grep -Fq 'cannot start' "$fixture/broken-helper"
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
  create_accounts() { printf 'create\n' >> "$fixture/users-order"; }
  remove_accounts() { printf 'remove\n' >> "$fixture/users-order"; }
  pacman() { printf 'unexpected pacman\n' >> "$fixture/users-order"; return 1; }
  users_only
  [[ $(cat "$fixture/users-order") == $'preflight\ncreate\nremove' ]]
)

(
  # shellcheck disable=SC1090
  source "$script"
  SUDO_RULE="$fixture/sudoers.d/20-kmos-adopt-wheel"
  sudo() { return 1; }
  ask() { return 1; }
  if enable_wheel_sudo builder > "$fixture/sudo-declined" 2>&1; then exit 1; fi
  [[ ! -e "$SUDO_RULE" ]]
  grep -Fq 'all wheel users' "$fixture/sudo-declined" || grep -Fq 'ALL wheel users' "$fixture/sudo-declined"
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
  create_accounts
  [[ $(cat "$marker") == '-m -s /bin/bash -G wheel newadmin' ]]
  [[ " ${USERS_CREATED[*]} " == *' newadmin '* ]]
  remove_accounts > "$fixture/remove-skipped" 2>&1
  grep -Fq 'No accounts will be removed' "$fixture/remove-skipped"
)

printf 'Arch VPS/headless adoption package, appearance, and account guards: OK (fixtures only).\n'
