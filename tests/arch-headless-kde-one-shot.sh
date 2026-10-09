#!/usr/bin/env bash
# Network orchestration is mocked; never change the host's services or desktop.
# shellcheck disable=SC1090,SC1091,SC2329
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
cat > "$fixture/network" <<'NETWORK_MOCK'
#!/usr/bin/env bash
case "$1" in
  --can-stage) [[ "${WIRED_READY:-no}" == yes ]] ;;
  --stage-reboot) printf '%s\n' stage >> "$NETWORK_ORDER" ;;
  *) exit 1 ;;
esac
NETWORK_MOCK
chmod +x "$fixture/network"

(
  source "$script"
  network_migration_script() { printf '%s\n' "$fixture/network"; }
  NETWORK_ORDER="$fixture/no-wired-order" WIRED_READY=no
  export NETWORK_ORDER WIRED_READY
  stage_network_for_reboot
  [[ ! -e "$NETWORK_ORDER" ]]
) > "$fixture/no-wired" 2>&1
grep -Fq 'NetworkManager not staged' "$fixture/no-wired"

(
  source "$script"
  network_migration_script() { printf '%s\n' "$fixture/network"; }
  NETWORK_ORDER="$fixture/wired-order" WIRED_READY=yes
  export NETWORK_ORDER WIRED_READY
  stage_network_for_reboot
) > "$fixture/wired" 2>&1
[[ $(cat "$fixture/wired-order") == stage ]]

printf 'Guided KDE visual/network ordering and wired staging gate: OK (mocked only).\n'
