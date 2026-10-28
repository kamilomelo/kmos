#!/usr/bin/env bash
# Read-only mocked adoption preview: no packages, accounts or host changes.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/kmos-adopt-headless.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

for term in xterm-256color linux; do
  (
    TERM=$term
    # shellcheck disable=SC1090
    source "$script"
    eligible() { :; }
    packages_for_host() { PACKAGES=(git openssh); }
    installed() { [[ $1 == git ]]; }
    current_hostname() { printf 'fixture-arch\n'; }
    regular_users() { printf 'tester:x:1000:1000::/home/tester:/bin/bash\n'; }
    is_admin() { return 1; }
    systemctl() {
      if [[ $1 == is-enabled ]]; then printf 'disabled\n'; else printf 'inactive\n'; fi
    }
    helper_works() { return 1; }
    preflight > "$fixture/$term.stdout" 2> "$fixture/$term.stderr"
    [[ $KT_PAUSE_SECONDS == 1 ]]
    if [[ $term == linux ]]; then
      [[ $KT_ACCENT == 37 ]]
    else
      [[ $KT_ACCENT == '38;5;244' ]]
    fi
  )
  grep -Fq 'Arch headless x86_64: eligible' "$fixture/$term.stdout"
  grep -Fq 'Current hostname: fixture-arch' "$fixture/$term.stdout"
  grep -Fq 'No changes made.' "$fixture/$term.stdout"
  grep -Fq 'Read-only preflight' "$fixture/$term.stderr"
  grep -Fq '3 ok' "$fixture/$term.stderr"
  ! grep -Fq $'\033' "$fixture/$term.stderr"
  if [[ $term == linux ]]; then
    grep -Fq '|- + Host settings unchanged' "$fixture/$term.stderr"
  else
    grep -Fq '├─ ✓ Host settings unchanged' "$fixture/$term.stderr"
  fi
done

# A checkout without the optional renderer retains its original read-only
# inventory instead of turning the preview into an installation dependency.
(
  # shellcheck disable=SC1090
  source "$script"
  SCRIPT_DIR="$fixture/without-renderer"
  eligible() { :; }
  packages_for_host() { PACKAGES=(git); }
  installed() { return 1; }
  current_hostname() { printf 'fixture-arch\n'; }
  regular_users() { :; }
  systemctl() { printf 'inactive\n'; }
  helper_works() { return 1; }
  preflight
) > "$fixture/plain.stdout" 2> "$fixture/plain.stderr"
grep -Fq 'No changes made.' "$fixture/plain.stdout"
[[ ! -s "$fixture/plain.stderr" ]]

# Both guided entry points must show a banner before the original approval
# gate; declining either one must not reach account or package operations.
(
  # shellcheck disable=SC1090
  source "$script"
  require_root() { :; }
  preflight() {
    # shellcheck disable=SC1090
    source "$repo/platforms/archlinux/tools/kartouche.sh"
    KT_NAME='kmos Adopt Headless'
  }
  ask() { return 1; }
  pacman() { printf 'Unexpected package operation.\n' >&2; return 1; }
  repair_admin_sudo() { printf 'Unexpected account operation.\n' >&2; return 1; }
  guided
  users_only
) > "$fixture/cancel.stdout" 2> "$fixture/cancel.stderr"
grep -Fq 'Review adoption before approval' "$fixture/cancel.stderr"
grep -Fq 'Review account changes' "$fixture/cancel.stderr"
[[ $(grep -Fc 'Cancelled without changes.' "$fixture/cancel.stderr") == 2 ]]
! grep -Fq 'Unexpected' "$fixture/cancel.stderr"

(
  # A fully mocked successful run checks the stage headings and end rail.
  # shellcheck disable=SC1090
  source "$script"
  MARKER="$fixture/mock-adopted"
  require_root() { :; }
  preflight() {
    # shellcheck disable=SC1090
    source "$repo/platforms/archlinux/tools/kartouche.sh"
    KT_NAME='kmos Adopt Headless'
    PACKAGES=(git)
  }
  ask() { :; }
  select_aur_helper() { printf 'yay\n'; }
  pacman() { [[ $1 == -Syu && $2 == --needed ]]; }
  configure_pacman_style() { :; } # Never touch the host's pacman.conf.
  enable_ssh() { :; }
  offer_hostname() { :; }
  create_accounts() { :; }
  aur_builder() { printf 'builder\n'; }
  choose_builder() { :; }
  install_aur() { :; }
  install_appearance() { :; }
  remove_accounts() { :; }
  guided
) > "$fixture/guided.stdout" 2> "$fixture/guided.stderr"
[[ -f "$fixture/mock-adopted" ]]
for label in 'Review adoption before approval' 'Choose AUR helper' 'Review hostname and accounts' 'Review old-account removals'; do
  grep -Fq "$label" "$fixture/guided.stderr"
done
grep -Fq '3 ok' "$fixture/guided.stderr"

printf 'Arch adoption Kartouche preflight: OK (fixtures only).\n'
