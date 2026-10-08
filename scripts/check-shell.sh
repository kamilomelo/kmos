#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'ShellCheck is required (version 0.11.0).\n' >&2
  exit 1
fi
if [[ "$(shellcheck --version | awk '/^version:/ {print $2}')" != "0.11.0" ]]; then
  printf 'ShellCheck 0.11.0 is required to compare the diagnostic baseline.\n' >&2
  exit 1
fi

# Limit the scope explicitly to platform entry points, their tests, and this checker.
# Never lint or execute unrelated or untracked work in this repository.
mapfile -d '' -t scripts < <(git ls-files -z -- 'kmos-install.sh' 'platforms/archlinux/*.sh' 'platforms/rockylinux/*.sh')
if ((${#scripts[@]} == 0)); then
  printf 'No tracked shell scripts found.\n' >&2
  exit 1
fi
scripts+=(
  platforms/archlinux/desktop/kde/kmos-kde-finish.sh
  platforms/archlinux/tools/kmos-network-migration.sh
  platforms/archlinux/desktop/kde/kmos-headless-to-kde.sh
  platforms/archlinuxarm/boards/quartz64b/prepare-quartz64b-sd.sh
  platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh
  platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh
  platforms/archlinuxarm/boards/quartz64b/try-quartz64b-wpa-wifi.sh
  scripts/check-shell.sh
  tests/archarm-dispatch.sh
  tests/arch-partition-safety.sh
  tests/arch-headless-aur.sh
  tests/arch-headless-kde-boundary.sh
  tests/arch-kde-package-parity.sh
  tests/arch-headless-kde-preflight.sh
  tests/arch-headless-wifi-helper.sh
  tests/arch-mirror-ranking.sh
  tests/arch-network-migration-plan.sh
  tests/arch-network-migration-apply.sh
  tests/arch-network-migration-stage.sh
  tests/arch-plan-before-go.sh
  tests/arch-finish-countdown.sh
  tests/arch-kde-panel-safety.sh
  tests/arch-kde-fresh-panel.sh
  tests/arch-kde-first-login-colors.sh
  tests/arch-kde-finish-safety.sh
  tests/arch-kde-kappa-fonts.sh
  tests/arch-krub-policy.sh
  tests/quartz-disk-safety.sh
  tests/quartz-bootloader-extraction.sh
  tests/quartz-workdir-safety.sh
  tests/quartz-sd-failure-paths.sh
  tests/quartz-provisioner-source.sh
  tests/quartz-wifi-bootstrap.sh
  tests/quartz-wpa-trial.sh
  tests/quartz-kde-provisioner.sh
  tests/quartz-impala-network.sh
  tests/quartz-arm-optional.sh
  tests/runtime-sudo.sh
)

for script in "${scripts[@]}"; do
  bash -n "$script"
done

diagnostics=$(mktemp)
normalized=$(mktemp)
trap 'rm -f "$diagnostics" "$normalized"' EXIT

status=0
shellcheck --shell=bash --format=gcc "${scripts[@]}" > "$diagnostics" || status=$?
if ((status > 1)); then
  cat "$diagnostics" >&2
  exit "$status"
fi

# Ignore line/column movement, but not the file, severity, code or message.
sed -E 's/:[0-9]+:[0-9]+: /: /' "$diagnostics" | LC_ALL=C sort > "$normalized"
if ! diff -u scripts/shellcheck-baseline.txt "$normalized"; then
  printf '\nShellCheck diagnostics changed. Fix new findings, then update the baseline only for intentional existing findings.\n' >&2
  exit 1
fi

printf 'Bash syntax and ShellCheck passed for %d scoped scripts (%d known diagnostics).\n' \
  "${#scripts[@]}" "$(wc -l < "$normalized")"

bash tests/arch-partition-safety.sh
bash tests/arch-headless-aur.sh
bash tests/arch-headless-kde-boundary.sh
bash tests/arch-kde-package-parity.sh
bash tests/arch-headless-kde-preflight.sh
bash tests/arch-headless-wifi-helper.sh
bash tests/arch-mirror-ranking.sh
bash tests/arch-network-migration-plan.sh
bash tests/arch-network-migration-apply.sh
bash tests/arch-network-migration-stage.sh
bash tests/arch-plan-before-go.sh
bash tests/arch-finish-countdown.sh
bash tests/arch-kde-panel-safety.sh
bash tests/arch-kde-fresh-panel.sh
bash tests/arch-kde-first-login-colors.sh
bash tests/arch-kde-finish-safety.sh
bash tests/arch-kde-kappa-fonts.sh
bash tests/arch-krub-policy.sh
bash tests/archarm-dispatch.sh
bash tests/quartz-disk-safety.sh
bash tests/quartz-bootloader-extraction.sh
bash tests/quartz-workdir-safety.sh
bash tests/quartz-sd-failure-paths.sh
bash tests/quartz-provisioner-source.sh
bash tests/quartz-wifi-bootstrap.sh
bash tests/quartz-wpa-trial.sh
bash tests/quartz-kde-provisioner.sh
bash tests/quartz-impala-network.sh
bash tests/quartz-arm-optional.sh
bash tests/runtime-sudo.sh
