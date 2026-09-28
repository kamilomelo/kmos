#!/usr/bin/env bash
# A fake sudo executable records the request; no privilege or installer runs.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
cat > "$fixture/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$KMOS_SUDO_ARGS"
EOF
cat > "$fixture/uname" <<'EOF'
#!/usr/bin/env bash
printf 'aarch64\n'
EOF
chmod +x "$fixture/sudo" "$fixture/uname"
export PATH="$fixture:$PATH"
export KMOS_SUDO_ARGS="$fixture/sudo-args"

expect_prompt() {
  local script=$1
  local index=0
  shift
  rm -f "$KMOS_SUDO_ARGS"
  "$repo/$script" "$@" > "$fixture/output" 2>&1
  [[ -s "$KMOS_SUDO_ARGS" ]] || { printf 'No sudo request from %s\n' "$script" >&2; exit 1; }
  mapfile -t args < "$KMOS_SUDO_ARGS"
  [[ "${args[0]}" == -- && "${args[1]}" == "$repo/$script" ]] || {
    printf 'Wrong sudo target from %s\n' "$script" >&2
    exit 1
  }
  [[ "${#args[@]}" -eq "$(( $# + 2 ))" ]] || {
    printf 'Wrong number of forwarded arguments from %s\n' "$script" >&2
    exit 1
  }
  local expected
  for expected in "$@"; do
    [[ "${args[$((index + 2))]}" == "$expected" ]] || {
      printf 'Argument not forwarded from %s\n' "$script" >&2
      exit 1
    }
    ((index += 1))
  done
}

expect_prompt platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh --device /not-a-device
expect_prompt platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh
expect_prompt platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh
expect_prompt platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh repair-prompt
expect_prompt platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh fonts
expect_prompt platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh aur
expect_prompt platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh remove-alarm
expect_prompt platforms/archlinux/kmos-archlinux-install.sh --profile noapps
expect_prompt platforms/archlinux/desktop/kde/kmos-kde-install.sh --profile noapps
expect_prompt platforms/archlinux/desktop/kde/kmos-kde-post.sh --profile noapps
expect_prompt platforms/rockylinux/kmos-rockylinux-install.sh
expect_prompt platforms/rockylinux/tools/kmos-rockylinux-wifi-connect.sh
expect_prompt platforms/archlinux/tools/kmos-wifi-connect.sh

rm -f "$KMOS_SUDO_ARGS"
"$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh" --help > "$fixture/output"
[[ ! -e "$KMOS_SUDO_ARGS" ]] || { printf 'Help unexpectedly requested sudo.\n' >&2; exit 1; }
"$repo/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" --help > "$fixture/output"
[[ ! -e "$KMOS_SUDO_ARGS" ]] || { printf 'Wi-Fi help unexpectedly requested sudo.\n' >&2; exit 1; }
"$repo/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh" --help > "$fixture/output"
[[ ! -e "$KMOS_SUDO_ARGS" ]] || { printf 'Board help unexpectedly requested sudo.\n' >&2; exit 1; }
printf 'NO\n' | "$repo/platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh" --clean-work > "$fixture/output" 2>&1
[[ ! -e "$KMOS_SUDO_ARGS" ]] || { printf 'Declined cache cleanup unexpectedly requested sudo.\n' >&2; exit 1; }

# shellcheck disable=SC1091
source "$repo/platforms/archlinux/tools/kmos-usb-flasher.sh"
run_privileged /usr/bin/true > "$fixture/output" 2>&1
mapfile -t args < "$KMOS_SUDO_ARGS"
[[ "${args[0]}" == -- && "${args[1]}" == /usr/bin/true ]]
printf 'Root-required entry points ask through sudo at runtime: OK (fake sudo only).\n'
