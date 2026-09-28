#!/usr/bin/env bash
# Mock optional ARM AUR builds and deferred alarm removal without board writes.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"
REPOSITORY_DIR=$repo
export TMPDIR=$fixture

stage_alarm_removal "$fixture/target"
[[ -x "$fixture/target/usr/local/libexec/kmos-remove-alarm-after-boot.sh" ]]
grep -q 'Before=sshd.service systemd-user-sessions.service' "$fixture/target/etc/systemd/system/kmos-remove-alarm.service"

(
  SUDO_USER=alarm
  PRIMARY_USER='admin'
  # shellcheck disable=SC2329 # Invoked by the sourced removal function.
  ask_yes_no() { return 0; }
  # shellcheck disable=SC2329 # Invoked indirectly by remove_alarm.
  getent() { [[ "$1" == passwd && "$2" == alarm ]] && printf 'alarm:x:1000:1000::/home/alarm:/bin/bash\n'; }
  # shellcheck disable=SC2329
  id() { if [[ "$1" == -nG ]]; then printf 'admin wheel\n'; else [[ "$1" == admin ]]; fi; }
  # shellcheck disable=SC2329
  userdel() { printf 'Unexpected deletion of a logged-in user.\n' >&2; exit 1; }
  # shellcheck disable=SC2329
  usermod() { [[ "$1" == -L && "$2" == -s && "$3" == /usr/bin/nologin && "$4" == alarm ]]; }
  # shellcheck disable=SC2329 # Invoked by the sourced removal function.
  stage_alarm_removal() { touch "$fixture/scheduled"; }
  remove_alarm
  [[ "$REMOVE_ALARM_REQUESTED" == 1 && "$ALARM_REMOVAL_PENDING" == 1 ]]
)
[[ -f "$fixture/scheduled" ]]

if [[ ! -e /home/alarm && ! -L /home/alarm ]]; then
  mkdir -p "$fixture/mock-bin"
  cat > "$fixture/mock-bin/getent" <<'EOF'
#!/usr/bin/env bash
[[ -e "$MOCK_ALARM_RECORD" ]] || exit 2
printf 'alarm:x:1000:1000::/home/alarm:/usr/bin/nologin\n'
EOF
  cat > "$fixture/mock-bin/userdel" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == '-r alarm' ]] || exit 1
rm -- "$MOCK_ALARM_RECORD"
EOF
  cat > "$fixture/mock-bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == 'disable kmos-remove-alarm.service' ]] || exit 1
touch "$MOCK_ALARM_DISABLED"
EOF
  chmod +x "$fixture/mock-bin/"*
  touch "$fixture/record"
  MOCK_ALARM_RECORD="$fixture/record" MOCK_ALARM_DISABLED="$fixture/disabled" \
    PATH="$fixture/mock-bin:$PATH" bash "$fixture/target/usr/local/libexec/kmos-remove-alarm-after-boot.sh"
  [[ ! -e "$fixture/record" && -e "$fixture/disabled" ]]
fi

(
  ask_yes_no() { return 1; }
  # shellcheck disable=SC2329 # An invocation would fail this skip test.
  install_aur_helper() { printf 'Unexpected AUR build.\n' >&2; exit 1; }
  offer_aur_helper
)

(
  # No host packages, AUR network request, or real privilege change is made.
  # shellcheck disable=SC2329
  id() { if [[ "$1" == -nG ]]; then printf 'admin wheel\n'; else [[ "$1" == admin ]]; fi; }
  # shellcheck disable=SC2329
  command() {
    if [[ "$1" == -v && ( "$2" == yay || "$2" == paru ) ]]; then
      [[ -f "$fixture/$2-installed" ]]
    else
      builtin command "$@"
    fi
  }
  # shellcheck disable=SC2329 # Checked by the sourced installer.
  yay() { [[ "$1" == --version ]]; }
  # shellcheck disable=SC2329
  paru() { [[ "$1" == --version ]]; }
  # shellcheck disable=SC2329
  ask_yes_no() { return 0; }
  # shellcheck disable=SC2329
  pacman() { printf '%s\n' "$*" >> "$fixture/pacman-log"; }
  # shellcheck disable=SC2329
  chown() { :; }
  # shellcheck disable=SC2329
  git() {
    if [[ "$1" == clone ]]; then
      [[ "$2" == https://aur.archlinux.org/yay.git || "$2" == https://aur.archlinux.org/paru.git ]] || return 1
      mkdir -p "$3"
      printf 'pkgname=%s\n' "${3##*/}" > "$3/PKGBUILD"
    elif [[ "$1" == -C && "$3" == rev-parse && "$4" == HEAD ]]; then
      printf 'fixture-commit\n'
    else
      return 1
    fi
  }
  # shellcheck disable=SC2329
  runuser() {
    [[ "$1" == -u && "$2" == admin && "$3" == -- ]] || return 1
    if [[ "$4" == git ]]; then
      git "${@:5}"
    else
      [[ "$4" == bash && "$5" == -c ]] || return 1
      local target=${!#}
      touch "$fixture/${target##*/}-installed"
    fi
  }
  install_aur_helper yay admin
  install_aur_helper paru admin
)
grep -q 'base-devel' "$fixture/pacman-log"
grep -q 'go' "$fixture/pacman-log"
grep -q 'rust' "$fixture/pacman-log"
grep -q 'cargo' "$fixture/pacman-log"
[[ -f "$fixture/yay-installed" && -f "$fixture/paru-installed" ]]
printf 'Quartz optional source AUR helper and deferred alarm removal: OK (mocked).\n'
