#!/usr/bin/env bash
# All account, sudo, process and KDE calls are mocked; never modify host users.
# shellcheck disable=SC1090,SC1091,SC2034,SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/desktop/kde/kmos-kde-users.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
"$script" --help > "$fixture/help"
grep -Fq 'Creation and removal are separate runs.' "$fixture/help"

(
  TERM=linux NO_COLOR=1 ASCII_UI=1
  # shellcheck disable=SC1090
  source "$script"
  check_host() { return 1; }
  require_root() { printf 'Unexpected sudo.\n' >&2; return 1; }
  if main --preflight > "$fixture/ineligible" 2>&1; then exit 1; fi
  [[ ! -e $fixture/operations ]]
  check_host() { :; }
  main --preflight > /dev/null 2> "$fixture/preflight"
  grep -Fq '|-' "$fixture/preflight"
  [[ $KT_GLYPHS == ascii && $KT_PAUSE_SECONDS == 1 ]]
) > /dev/null 2>&1

(
  # shellcheck disable=SC1090
  source "$script"
  HOME_ROOT="$fixture/homes"
  mkdir -p "$HOME_ROOT"
  getent() { return 2; }
  useradd() { printf 'useradd %s\n' "$*" >> "$fixture/create-ops"; }
  passwd() { printf 'passwd %s\n' "$*" >> "$fixture/create-ops"; }
  sudo_allowed() { [[ ${admin_allowed:-no} == yes ]]; }
  run_finish() { printf 'finish %s\n' "$*" >> "$fixture/create-ops"; }
  userdel() { printf 'Unexpected removal.\n' >&2; exit 1; }
  input() { local value; IFS= read -r value <&9 || return 1; printf '%s\n' "$value"; }
  ask() { local answer; IFS= read -r answer <&8 || return 1; [[ $answer == y ]]; }
  exec 9< <(printf 'newuser\n')
  exec 8< <(printf 'n\ny\ny\n')
  create_account > /dev/null 2> "$fixture/no-sudo"
  [[ $(cat "$fixture/create-ops") == $'useradd -m -s /bin/bash -- newuser\npasswd newuser\nfinish --plan --user newuser\nfinish --apply --user newuser' ]]
  grep -Fq 'New login not yet verified' "$fixture/no-sudo"
  : > "$fixture/create-ops"
  admin_allowed=yes
  exec 9< <(printf 'otheruser\n')
  exec 8< <(printf 'y\ny\nn\n')
  create_account > /dev/null 2> "$fixture/admin"
  [[ $(cat "$fixture/create-ops") == $'useradd -m -s /bin/bash -G wheel -- otheruser\npasswd otheruser\nfinish --plan --user otheruser' ]]
  grep -Fq 'Verify a NEW login and sudo' "$fixture/admin"
  : > "$fixture/create-ops"
  exec 9< <(printf 'invalid name\n')
  if create_account > /dev/null 2> "$fixture/invalid"; then exit 1; fi
  [[ ! -s $fixture/create-ops ]]
  admin_allowed=no
  exec 9< <(printf 'unverifiedadmin\n')
  exec 8< <(printf 'y\ny\n')
  if create_account > /dev/null 2> "$fixture/denied-sudo"; then exit 1; fi
  grep -Fq 'sudo is not authorized' "$fixture/denied-sudo"
  if grep -Fq 'finish ' "$fixture/create-ops"; then exit 1; fi
  : > "$fixture/create-ops"
  passwd() {
    printf 'passwd %s\n' "$*" >> "$fixture/create-ops"
    [[ $1 == -l ]]
  }
  exec 9< <(printf 'lockeduser\n')
  exec 8< <(printf 'n\ny\n')
  if create_account > /dev/null 2> "$fixture/password-failed"; then exit 1; fi
  grep -Fxq 'passwd -l lockeduser' "$fixture/create-ops"
  if grep -Fq 'finish ' "$fixture/create-ops"; then exit 1; fi
) > /dev/null 2>&1

(
  # shellcheck disable=SC1090
  source "$script"
  HOME_ROOT="$fixture/homes"
  LINGER_ROOT="$fixture/linger"
  SUDO_USER='admin'
  mkdir -p "$HOME_ROOT/olduser"
  local_account() { [[ $1 == olduser || $1 == admin ]]; }
  sudo_allowed() { [[ $1 == admin || ${target_admin:-no} == yes ]]; }
  is_wheel() { [[ $1 == admin || ${target_admin:-no} == yes ]]; }
  active_account() { [[ ${active:-no} == yes ]]; }
  home_has_mounts() { [[ ${mounted:-no} == yes ]]; }
  stat() { printf '1001\n'; }
  id() { if [[ $1 == -u ]]; then printf '1001\n'; else command id "$@"; fi; }
  getent() {
    if [[ $1 == passwd ]]; then printf '%s:x:1001:1001::%s/%s:/bin/bash\n' "$2" "$HOME_ROOT" "$2"
    elif [[ $1 == group && ${group_present:-no} == yes ]]; then printf '%s:x:1001:\n' "$2"
    else return 2; fi
  }
  groupdel() { printf 'groupdel %s\n' "$*" >> "$fixture/remove-ops"; }
  userdel() { printf 'userdel %s\n' "$*" >> "$fixture/remove-ops"; }
  input() { local value; IFS= read -r value <&9 || return 1; printf '%s\n' "$value"; }
  ask() { local answer; IFS= read -r answer <&8 || return 1; [[ $answer == y ]]; }
  exec 9< <(printf 'admin\n')
  if remove_account > /dev/null 2> "$fixture/self"; then exit 1; fi
  active=yes
  exec 9< <(printf 'olduser\n')
  if remove_account > /dev/null 2> "$fixture/active"; then exit 1; fi
  active=no
  exec 9< <(printf 'olduser\nWRONG\n')
  remove_account > /dev/null 2> "$fixture/refused"
  [[ ! -e $fixture/remove-ops ]]
  target_admin=yes
  exec 9< <(printf 'olduser\nWRONG\n')
  remove_account > /dev/null 2> "$fixture/last-admin-cancel"
  [[ ! -s $fixture/remove-ops ]]
  target_admin=no
  exec 9< <(printf 'olduser\nREMOVE olduser\nWRONG HOME\n')
  remove_account > /dev/null 2> "$fixture/home-refused"
  [[ ! -s $fixture/remove-ops ]]
  target_admin=no mounted=yes
  exec 9< <(printf 'olduser\nREMOVE olduser\nDELETE %s/olduser\n' "$HOME_ROOT")
  if remove_account > /dev/null 2> "$fixture/mounted"; then exit 1; fi
  [[ ! -s $fixture/remove-ops ]]
  mounted=no
  stat() { printf '1002\n'; }
  exec 9< <(printf 'olduser\nREMOVE olduser\nDELETE %s/olduser\n' "$HOME_ROOT")
  if remove_account > /dev/null 2> "$fixture/wrong-owner"; then exit 1; fi
  [[ ! -s $fixture/remove-ops ]]
  stat() { printf '1001\n'; }
  exec 9< <(printf 'olduser\nREMOVE olduser\nDELETE %s/olduser\n' "$HOME_ROOT")
  remove_account > /dev/null 2> "$fixture/deleted"
  [[ $(cat "$fixture/remove-ops") == 'userdel -r -- olduser' ]]
  : > "$fixture/remove-ops"
  group_present=yes
  PASSWD_FILE="$fixture/remaining-passwd"
  GROUP_FILE="$fixture/group"
  printf 'olduser:x:1001:\n' > "$GROUP_FILE"
  : > "$PASSWD_FILE"
  exec 9< <(printf 'olduser\nREMOVE olduser\nDELETE %s/olduser\n' "$HOME_ROOT")
  remove_account > /dev/null 2> "$fixture/group-cleaned"
  [[ $(cat "$fixture/remove-ops") == $'userdel -r -- olduser\ngroupdel -- olduser' ]]
  : > "$fixture/remove-ops"
  group_present=no
  target_admin=yes
  exec 9< <(printf 'olduser\nREMOVE olduser\nDELETE %s/olduser\n' "$HOME_ROOT")
  remove_account > /dev/null 2> "$fixture/admin-removed"
  [[ $(cat "$fixture/remove-ops") == 'userdel -r -- olduser' ]]
) > /dev/null 2>&1

(
  # A non-root removal delegates to the system root-password prompt, not sudo.
  source "$script"
  if ((EUID != 0)); then
    mkdir -p "$fixture/bin"
    cat > "$fixture/bin/su" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$KMOS_SU_LOG"
EOF
    chmod +x "$fixture/bin/su"
    PATH="$fixture/bin:$PATH" KMOS_SU_LOG="$fixture/su-args" require_removal_root
    [[ $(tail -1 "$fixture/su-args") == root ]]
    grep -Fxq -- '-c' "$fixture/su-args"
    if grep -Fq 'sudo' "$fixture/su-args"; then exit 1; fi
  fi
) > /dev/null 2>&1

(
  # Local-account recognition and admin counting use only fixture passwd data.
  source "$script"
  HOME_ROOT="$fixture/homes"
  PASSWD_FILE="$fixture/passwd"
  printf 'root:x:0:0::/root:/bin/bash\nadmin:x:1000:1000::%s/admin:/bin/bash\nolduser:x:1001:1001::%s/olduser:/bin/bash\noutsider:x:1002:1002::/elsewhere:/bin/bash\nservice:x:999:999::%s/service:/bin/bash\n' "$HOME_ROOT" "$HOME_ROOT" "$HOME_ROOT" > "$PASSWD_FILE"
  getent() { [[ $1 == passwd ]] && awk -F: -v name="$2" '$1 == name {print; found=1} END {exit !found}' "$PASSWD_FILE"; }
  sudo_allowed() { [[ $1 == admin || $1 == olduser ]]; }
  local_account admin && local_account olduser
  if local_account root || local_account outsider || local_account service; then exit 1; fi
) > /dev/null 2>&1

(
  # Fail closed when session, process or mount inspection cannot be trusted.
  # shellcheck disable=SC1090
  source "$script"
  session_state=clear process_state=clear mount_state=clear
  loginctl() {
    [[ $session_state != broken ]] || return 2
    [[ $session_state != active ]] || printf '42 1001 olduser - pts/2\n'
  }
  pgrep() {
    case $process_state in active) return 0 ;; broken) return 2 ;; *) return 1 ;; esac
  }
  findmnt() {
    if [[ $1 == -rn && $2 == --mountpoint ]]; then
      case $mount_state in mounted) return 0 ;; broken) return 2 ;; *) return 1 ;; esac
    fi
    [[ $mount_state != broken ]] || return 2
    [[ $mount_state != nested ]] || printf '%s/child\n' "$fixture/homes/olduser"
  }
  if active_account olduser; then exit 1; fi
  session_state=active; active_account olduser
  session_state=broken; active_account olduser
  session_state=clear process_state=active; active_account olduser
  process_state=broken; active_account olduser
  process_state=clear
  if home_has_mounts "$fixture/homes/olduser"; then exit 1; fi
  mount_state=mounted; home_has_mounts "$fixture/homes/olduser"
  mount_state=nested; home_has_mounts "$fixture/homes/olduser"
  mount_state=broken; home_has_mounts "$fixture/homes/olduser"
) > /dev/null 2>&1

printf 'KDE accounts: creation, sudo choice, finishing and guarded removal OK (mocked).\n'
