#!/usr/bin/env bash
# All pacman configuration edits stay inside this disposable fixture.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
script="$repo/platforms/archlinux/kmos-adopt-headless.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

(
  # shellcheck disable=SC1090
  source "$script"
  PACMAN_CONFIG="$fixture/pacman.conf"
  cat > "$PACMAN_CONFIG" <<'EOF'
[options]
#Color
#ParallelDownloads = 5
DisableDownloadTimeout

[core]
Include = /etc/pacman.d/mirrorlist
EOF
  chmod 0644 "$PACMAN_CONFIG"
  cp "$PACMAN_CONFIG" "$fixture/original"
  configure_pacman_style
  grep -Fxq Color "$PACMAN_CONFIG"
  grep -Fxq 'ParallelDownloads = 6' "$PACMAN_CONFIG"
  grep -Fxq ILoveCandy "$PACMAN_CONFIG"
  grep -Fxq DisableDownloadTimeout "$PACMAN_CONFIG"
  grep -Fxq 'Include = /etc/pacman.d/mirrorlist' "$PACMAN_CONFIG"
  [[ $(stat -c %a "$PACMAN_CONFIG") == 644 ]]
  mapfile -t backups < <(find "$fixture" -maxdepth 1 -name 'pacman.conf.kmos-backup.*' -print)
  [[ ${#backups[@]} == 1 && $(stat -c %a "${backups[0]}") == 600 ]]
  cmp -s "$fixture/original" "${backups[0]}"
  cp "$PACMAN_CONFIG" "$fixture/after-first"
  configure_pacman_style
  cmp -s "$fixture/after-first" "$PACMAN_CONFIG"
  [[ $(find "$fixture" -maxdepth 1 -name 'pacman.conf.kmos-backup.*' | wc -l) == 1 ]]
  sed -i 's/ParallelDownloads = 6/ParallelDownloads = 5/' "$PACMAN_CONFIG"
  configure_pacman_style
  grep -Fxq 'ParallelDownloads = 6' "$PACMAN_CONFIG"
  [[ $(find "$fixture" -maxdepth 1 -name 'pacman.conf.kmos-backup.*' | wc -l) == 2 ]]
  # An existing active parallel setting belongs to the host and is preserved.
  sed -i 's/ParallelDownloads = 6/ParallelDownloads = 12/' "$PACMAN_CONFIG"
  configure_pacman_style
  grep -Fxq 'ParallelDownloads = 12' "$PACMAN_CONFIG"
  [[ $(find "$fixture" -maxdepth 1 -name 'pacman.conf.kmos-backup.*' | wc -l) == 2 ]]
  ln -s "$PACMAN_CONFIG" "$fixture/symlink.conf"
  PACMAN_CONFIG="$fixture/symlink.conf"
  configure_pacman_style
  [[ -L $PACMAN_CONFIG ]]
  PACMAN_CONFIG="$fixture/no-options.conf"
  printf '[core]\n' > "$PACMAN_CONFIG"
  if configure_pacman_style; then exit 1; fi
  [[ $(cat "$PACMAN_CONFIG") == '[core]' ]]
  pacman_style_only() { printf 'standalone mode\n'; }
  main --pacman-style
) > "$fixture/report" 2>&1
grep -Fq 'standalone mode' "$fixture/report"
grep -Fq 'Pacman presentation already configured' "$fixture/report"
grep -Fq 'leaving it untouched' "$fixture/report"

printf 'Arch adoption pacman settings, backup and idempotence: OK (fixtures only).\n'
