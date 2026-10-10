#!/usr/bin/env bash
# Fixture-only settings review: never alter the host's KDE or its backups.
# Mocked writers and state are consumed by the sourced finishing script.
# shellcheck disable=SC1090,SC2329,SC2034
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
script="$repo/platforms/archlinux/desktop/kde/kmos-kde-finish.sh"
"$script" --help > "$fixture/help"
grep -Fq -- '--plan' "$fixture/help"
grep -Fq -- '--apply --all-users' "$fixture/help"

(
  # shellcheck disable=SC1091
  source "$script"
  temp="$fixture"
  mode=plan
  writer() { printf 'KMOS default\n' > "$1"; }
  printf 'user choice\n' > "$fixture/setting"
  stage_file system "$fixture/setting" writer
  [[ $(cat "$fixture/setting") == 'user choice' ]]
  [[ "$backup_bytes" == "$(wc -c < "$fixture/setting")" ]]
) > "$fixture/plan"
grep -Fq 'approval and backup required' "$fixture/plan"

(
  # shellcheck disable=SC1091
  source "$script"
  temp="$fixture"
  mode=apply
  writer() { printf 'KMOS default\n' > "$1"; }
  ask_replace() { return 1; }
  backup_file() { printf 'Unexpected backup\n' >&2; return 1; }
  stage_file system "$fixture/setting" writer
  [[ $(cat "$fixture/setting") == 'user choice' ]]
  [[ "$skipped" == 1 ]]
) > "$fixture/declined"

(
  # shellcheck disable=SC1091
  source "$script"
  temp="$fixture"
  mode=apply
  writer() { printf 'KMOS default\n' > "$1"; }
  ask_replace() { :; }
  backup_file() { cp -- "$2" "$fixture/saved-setting"; }
  stage_file system "$fixture/setting" writer
  [[ $(cat "$fixture/saved-setting") == 'user choice' ]]
  [[ $(cat "$fixture/setting") == 'KMOS default' ]]
  # A second run must not ask again or generate another backup.
  ask_replace() { printf 'Unnecessary prompt.\n' >&2; return 1; }
  backup_file() { printf 'Unnecessary backup.\n' >&2; return 1; }
  stage_file system "$fixture/setting" writer
) > "$fixture/approved"

(
  # shellcheck disable=SC1091
  source "$script"
  temp="$fixture"
  mode=apply
  writer() { printf 'new default\n' > "$1"; }
  ask_replace() { printf 'Unexpected prompt for missing file.\n' >&2; return 1; }
  stage_file system "$fixture/missing" writer
  [[ $(cat "$fixture/missing") == 'new default' ]]
  ln -s "$fixture/setting" "$fixture/symlink"
  if stage_file system "$fixture/symlink" writer > "$fixture/symlink-output" 2>&1; then
    printf 'Symlink accepted.\n' >&2; exit 1
  fi
) > "$fixture/new"
grep -Fq 'Symlink refused' "$fixture/symlink-output"

(
  # shellcheck disable=SC1091
  source "$script"
  temp="$fixture"
  mode=apply user=fixture
  home="$fixture/owned-home"
  mkdir -p "$home"
  writer() { printf 'user defaults\n' > "$1"; }
  runuser() { shift 3; printf '%s\n' "$*" >> "$fixture/user-mkdir"; "$@"; }
  chown() { :; }
  stage_file user "$home/.local/share/konsole/kmos.profile" writer
  [[ -f "$home/.local/share/konsole/kmos.profile" ]]
) > "$fixture/user-file"
grep -Fxq "mkdir -p -- $fixture/owned-home/.local/share/konsole" "$fixture/user-mkdir"

(
  # shellcheck disable=SC1091
  source "$script"
  user=fixture
  home="$fixture/home"
  backup_stamp=fixture-date
  system_backup_root="$fixture/system-backups"
  mkdir -p "$home/.config"
  printf 'personal\n' > "$home/.config/example"
  runuser() { shift 3; "$@"; }
  backup_file user "$home/.config/example"
  user_backup="$home/.local/share/kmos/backups/kde-fixture-date/.config/example"
  [[ $(cat "$user_backup") == personal ]]
  [[ $(stat -c %a "$home/.local/share/kmos/backups") == 700 ]]
  if backup_file user "$home/.config/example" > /dev/null 2>&1; then
    printf 'Existing user backup was replaced.\n' >&2; exit 1
  fi
  backup_file system "$fixture/setting"
  [[ $(cat "$system_backup_root/kde-fixture-date/${fixture#/}/setting") == 'KMOS default' ]]
) > "$fixture/backups"

(
  # shellcheck disable=SC1091
  source "$script"
  temp="$fixture"
  font_dir="$fixture/fonts"
  mode=plan
  curl() { printf 'Plan fetched fonts unexpectedly.\n' >&2; return 1; }
  stage_fonts
  [[ ! -e "$font_dir" ]]
  mode=apply
  curl() {
    if [[ "${3:-}" == -o ]]; then
      printf 'fixture font\n' > "$4"
    else
      printf '"download_url": "https://raw.githubusercontent.com/kamilomelo/kappa-type/main/fonts/KappaMono-Regular.ttf"\n'
    fi
  }
  fc-cache() { :; }
  fc-match() { printf 'Kappa Mono\n'; }
  stage_fonts
  [[ $(cat "$font_dir/KappaMono-Regular.ttf") == 'fixture font' ]]
) > "$fixture/fonts-log"

(
  # shellcheck disable=SC1091
  source "$script"
  user=fixture home="$fixture/home"
  stage_sddm_assets() { printf 'sddm\n' >> "$fixture/stages"; }
  stage_fonts() { printf 'fonts\n' >> "$fixture/stages"; }
  stage_file() { printf '%s\n' "$2" >> "$fixture/stages"; }
  stage_defaults
)
grep -Fq "$fixture/home/.config/konsolerc" "$fixture/stages"
grep -Fq "$fixture/home/.config/kwinrc" "$fixture/stages"
grep -Fq '/etc/xdg/kscreenlockerrc' "$fixture/stages"
if grep -Eq 'plasma-org\.kde\.plasma\.desktop-appletsrc|wifi|NetworkManager' "$fixture/stages"; then
  printf 'Finishing stage touched panels or networking.\n' >&2; exit 1
fi

cat > "$fixture/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
fixture-f:x:1000:1000::/home/fixture-f:/bin/bash
system-daemon:x:1001:1001::/var/lib/system-daemon:/usr/bin/nologin
fixture-k:x:1002:1002::/home/fixture-k:/bin/bash
nobody:x:65534:65534::/home/nobody:/usr/bin/nologin
EOF
(
  # shellcheck disable=SC1091
  source "$script"
  local_passwd_file="$fixture/passwd"
  list_local_users accounts
  [[ ${accounts[*]} == 'fixture-f fixture-k' ]]
  choose_user() { user="$1" home="$fixture/$1"; }
  check_system() { :; }
  require_root_for_all_user_plan() { :; }
  load_finish_assets() { :; }
  stage_system_defaults() { printf 'system\n' >> "$fixture/all-user-stages"; }
  stage_user_defaults() { printf '%s %s\n' "$user" "$home" >> "$fixture/all-user-stages"; }
  main --plan --all-users
) > "$fixture/all-user-plan"
[[ $(cat "$fixture/all-user-stages") == "$(printf 'system\nfixture-f %s/fixture-f\nfixture-k %s/fixture-k' "$fixture" "$fixture")" ]]

if (
  # shellcheck disable=SC1091
  source "$script"
  local_passwd_file="$fixture/passwd"
  choose_user() { [[ "$1" != fixture-k ]] || return 1; user="$1" home="$fixture/$1"; }
  check_system() { :; }
  require_root_for_all_user_plan() { :; }
  load_finish_assets() { :; }
  stage_system_defaults() { printf 'Unexpected write.\n' > "$fixture/invalid-all-user-write"; }
  main --plan --all-users
) > "$fixture/invalid-all-user-plan" 2>&1; then
  printf 'A bad account was accepted for all-user finishing.\n' >&2; exit 1
fi
[[ ! -e "$fixture/invalid-all-user-write" ]]

printf 'KDE finishing step previews, backs up, skips and protects settings (fixtures only).\n'
