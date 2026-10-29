#!/usr/bin/env bash
# Manage local KMOS KDE accounts without copying another user's personal files.
# shellcheck disable=SC2034 # Renderer config is consumed by sourced Kartouche.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FINISHER=$SCRIPT_DIR/kmos-kde-finish.sh
HOME_ROOT=/home
PASSWD_FILE=/etc/passwd
# shellcheck disable=SC1090,SC1091
source "$SCRIPT_DIR/../../tools/kartouche.sh"
KT_NAME='kmos KDE Accounts'
KT_DESCRIPTION='Guarded local accounts and KMOS desktop defaults.'
KT_ACCENT='38;5;244'
[[ ${TERM:-} == linux ]] && KT_ACCENT=37
[[ ${TERM:-} == linux || ${ASCII_UI:-${kmos_ASCII_UI:-0}} == 1 ]] && KT_GLYPHS=ascii

usage() {
  cat <<'EOF'
Usage: ./platforms/archlinux/desktop/kde/kmos-kde-users.sh [--preflight|--create|--remove|--help]

No argument opens a guided create/remove menu on an installed KMOS KDE Arch
x86_64 system. --preflight is read-only and does not ask for sudo. New accounts
inherit /etc/skel; optional finishing applies KMOS defaults, NOT a copy of
another user's personal Plasma files. Creation and removal are separate runs.
Removal never happens automatically after creation. Account deletion and home
deletion require different exact typed approvals. Use a terminal (ssh -t).
EOF
}
fail() { printf 'ERROR: %s\n' "$*" >&2; return 1; }
note() { printf '%s\n' "$*" >&2; }
ask() {
  local answer
  while true; do
    printf '%s [y/N]: ' "$1" >&2
    IFS= read -r answer </dev/tty || return 1
    case $answer in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      ''|[Nn]|[Nn][Oo]) return 1 ;;
      *) note 'Please answer yes or no.' ;;
    esac
  done
}
input() {
  local answer
  printf '%s' "$1" >&2
  IFS= read -r answer </dev/tty || return 1
  printf '%s\n' "$answer"
}
valid_name() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,30}$ && $1 != root ]]; }
local_account() {
  local entry uid home shell
  valid_name "$1" || return 1
  awk -F: -v name="$1" '$1 == name {found=1} END {exit !found}' "$PASSWD_FILE" || return 1
  entry=$(getent passwd "$1") || return 1
  IFS=: read -r _ _ uid _ _ home shell <<< "$entry"
  [[ $uid =~ ^[0-9]+$ ]] && ((uid >= 1000 && uid < 65534)) &&
    [[ $home == "$HOME_ROOT/$1" && $shell != */nologin && $shell != */false ]]
}
sudo_allowed() { sudo -l -U "$1" -u root -- /usr/bin/true >/dev/null 2>&1; }
is_wheel() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -Fxq wheel; }
admin_count() {
  local name _ count=0
  while IFS=: read -r name _; do
    local_account "$name" && sudo_allowed "$name" && ((count+=1)) || :
  done <"$PASSWD_FILE"
  printf '%s\n' "$count"
}
check_host() {
  local os_id
  [[ -r /etc/os-release ]] || { fail 'Cannot identify the OS.'; return 1; }
  # shellcheck disable=SC1091
  os_id=$(. /etc/os-release; printf '%s' "${ID:-}")
  [[ $os_id == arch && $(uname -m) == x86_64 && -d /var/lib/pacman/local && -f /etc/machine-id ]] || {
    fail 'Only installed Arch Linux x86_64 is supported.'; return 1;
  }
  [[ ! -e /run/archiso && -f /usr/share/kmos/kde-profile && ! -L /usr/share/kmos/kde-profile ]] || {
    fail 'Only an installed KMOS KDE system is supported, not a live ISO.'; return 1;
  }
  if ! command -v pacman >/dev/null || ! pacman -Qq plasma-desktop sddm >/dev/null 2>&1; then
    fail 'KDE and SDDM must already be installed.'; return 1;
  fi
  [[ -f $FINISHER && -x $FINISHER && ! -L $FINISHER && -d $HOME_ROOT && ! -L $HOME_ROOT ]] || {
    fail 'A complete KMOS checkout and a real /home directory are required.'; return 1;
  }
}
require_root() {
  ((EUID == 0)) && return 0
  command -v sudo >/dev/null || { fail 'sudo is required for account changes.'; return 1; }
  exec sudo -- "$SCRIPT_DIR/kmos-kde-users.sh" "$@"
}
run_finish() { "$FINISHER" "$@"; }

create_account() {
  local name grant=no
  kt_banner 'Create a local KDE account'
  name=$(input 'New username: ') || return 1
  valid_name "$name" && ! getent passwd "$name" >/dev/null &&
    [[ ! -e $HOME_ROOT/$name && ! -L $HOME_ROOT/$name ]] || { fail 'Invalid name or existing user/home.'; return 1; }
  if ask "Grant $name sudo via wheel?"; then grant=yes; fi
  note "Proposed: create /home/$name from /etc/skel; sudo: $grant. No existing account will be removed."
  ask "Create $name?" || { note 'Cancelled without changes.'; return 0; }
  if [[ $grant == yes ]]; then
    useradd -m -s /bin/bash -G wheel -- "$name" || return 1
  else
    useradd -m -s /bin/bash -- "$name" || return 1
  fi
  note "Set $name's password using passwd (KMOS does not read it):"
  if ! passwd "$name"; then
    if passwd -l "$name"; then
      fail "Password setup failed; $name has been locked for review."
    else
      fail "Password setup and locking failed for $name; inspect this account immediately."
    fi
    return 1
  fi
  if [[ $grant == yes ]]; then
    sudo_allowed "$name" || { fail "$name was created but sudo is not authorized. Verify policy before relying on this admin."; return 1; }
  elif sudo_allowed "$name"; then
    fail "$name was created but host sudo policy grants access despite declining wheel. Review policy before using this account."
    return 1
  fi
  run_finish --plan --user "$name" || { fail "$name was created; KDE preview failed. Review the account before retrying finishing."; return 1; }
  if ask "Apply KMOS KDE defaults to $name (existing settings need separate approval)?"; then
    run_finish --apply --user "$name" || { fail "$name was created; KDE finishing needs review."; return 1; }
    kt_summary rail 'Account and password set' ok 'KMOS KDE defaults reviewed' ok 'New login not yet verified' skipped
  else
    note "$name created with /etc/skel; optional KDE finishing was skipped."
    kt_summary rail 'Account and password set' ok 'Optional finishing skipped' skipped 'New login not yet verified' skipped
  fi
  if [[ $grant == yes ]]; then
    note "Verify a NEW login and sudo as $name before removing any old administrator."
  else
    note "Verify a NEW login as $name before removing any old account."
  fi
}

active_account() {
  local name=$1 sessions status
  command -v loginctl >/dev/null && command -v pgrep >/dev/null || return 0
  sessions=$(loginctl list-sessions --no-legend) || return 0
  awk '{print $3}' <<< "$sessions" | grep -Fxq "$name" && return 0
  if pgrep -u "$name" >/dev/null 2>&1; then return 0
  else status=$?; ((status == 1)) || return 0; fi
  if pgrep -U "$name" >/dev/null 2>&1; then return 0
  else status=$?; ((status == 1)) || return 0; fi
  return 1
}
home_has_mounts() {
  local mounts status
  command -v findmnt >/dev/null || return 0
  if findmnt -rn --mountpoint "$1" >/dev/null 2>&1; then return 0
  else status=$?; ((status == 1)) || return 0; fi
  mounts=$(findmnt -rn -o TARGET) || return 0
  grep -Fq -- "$1/" <<< "$mounts" && return 0
  return 1
}
remove_account() {
  local name login answer home count
  kt_banner 'Review account removal'
  name=$(input 'Existing username to remove: ') || return 1
  local_account "$name" || { fail 'Only local regular accounts with a standard /home/name can be removed.'; return 1; }
  login=${SUDO_USER:-$(id -un)}
  [[ $name != "$login" ]] || { fail 'Cannot remove the current login.'; return 1; }
  if sudo_allowed "$name" || is_wheel "$name"; then
    if ! local_account "$login" || ! is_wheel "$login" || ! sudo_allowed "$login"; then
      fail 'Admin removal requires a different working administrator login.'; return 1;
    fi
    count=$(admin_count)
    ((count > 1)) || { fail 'Cannot remove the last working regular administrator.'; return 1; }
    answer=$(input "After verifying a NEW SSH login and sudo as $login, type VERIFIED $login: ") || return 1
    [[ $answer == "VERIFIED $login" ]] || { note 'Verification not confirmed; account retained.'; return 0; }
  fi
  if active_account "$name"; then fail 'User is logged in, has processes, or session safety could not be checked.'; return 1; fi
  home=$HOME_ROOT/$name
  note "Account: $name; home: $home. Account removal cannot be undone."
  answer=$(input "Type REMOVE $name to remove the account: ") || return 1
  [[ $answer == "REMOVE $name" ]] || { note 'Cancelled without changes.'; return 0; }
  if ask "Also permanently delete $home and its contents?"; then
    answer=$(input "Type DELETE $home to erase the home: ") || return 1
    [[ $answer == "DELETE $home" ]] || { note 'Home deletion declined; account retained.'; return 0; }
    [[ -d $home && ! -L $home && $(stat -c %u -- "$home") == "$(id -u "$name")" ]] || {
      fail 'Home is missing, symlinked, or not owned by the account; refusing deletion.'; return 1;
    }
    if home_has_mounts "$home"; then fail 'Home has a mounted filesystem or mount checks failed.'; return 1; fi
    if active_account "$name"; then fail 'Account became active; refusing removal.'; return 1; fi
    userdel -r -- "$name" || return 1
    kt_summary rail 'Account removed' ok 'Home permanently deleted' ok
  else
    if active_account "$name"; then fail 'Account became active; refusing removal.'; return 1; fi
    userdel -- "$name" || return 1
    note "Home retained at $home; review it manually when no longer needed."
    kt_summary rail 'Account removed' ok 'Home retained' skipped
  fi
}

guided() {
  local choice
  check_host || return 1
  kt_banner 'Choose a KDE account operation'
  note '  1) Create a user'
  note '  2) Remove a user (separate run, never after creation)'
  note '  3) Exit'
  choice=$(input 'Select [1-3]: ') || return 1
  case $choice in
    1) require_root --create || return 1; create_account ;;
    2) require_root --remove || return 1; remove_account ;;
    3) note 'No changes made.' ;;
    *) fail 'Invalid selection; no changes made.' ;;
  esac
}
main() {
  case ${1:-} in
    --help|-h) (($# == 1)) || { usage >&2; return 2; }; usage ;;
    --preflight) (($# == 1)) || { usage >&2; return 2; }; check_host || return 1; kt_banner 'Eligible KMOS KDE host; no changes made' ;;
    --create) (($# == 1)) || { usage >&2; return 2; }; check_host || return 1; require_root --create || return 1; create_account ;;
    --remove) (($# == 1)) || { usage >&2; return 2; }; check_host || return 1; require_root --remove || return 1; remove_account ;;
    '') (($# == 0)) || { usage >&2; return 2; }; guided ;;
    *) usage >&2; return 2 ;;
  esac
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
