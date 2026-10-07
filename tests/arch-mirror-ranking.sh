#!/usr/bin/env bash
# Bounded mirror selection and pacstrap hand-off against fixtures only.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck disable=SC1091
source "$repo/platforms/archlinux/kmos-archlinux-install.sh"

mkdir -p "$fixture/bin" "$fixture/iso" "$fixture/target/etc/pacman.d"
MOUNT_POINT="$fixture/target"
cat > "$fixture/iso/mirrorlist" <<'EOF'
## Arch ISO mirror list
Server = https://slow.example/arch/$repo/os/$arch
Server = https://fast.example/arch/$repo/os/$arch
Server = https://unreachable.example/arch/$repo/os/$arch
Server = https://medium.example/arch/$repo/os/$arch
EOF
cp "$fixture/iso/mirrorlist" "$fixture/original"
printf '[options]\nDisableDownloadTimeout\nParallelDownloads = 5\n' > "$fixture/iso/pacman.conf"
printf 'personal mirror preference\n' > "$MOUNT_POINT/etc/pacman.d/mirrorlist"
cat > "$fixture/bin/curl" <<'EOF'
#!/bin/sh
for url do :; done
printf '%s\n' "$url" >> "$PROBES"
[ "${FAIL_ALL:-no}" = no ] || exit 1
case "$url" in
  https://fast.example/*) printf '0.100000' ;;
  https://medium.example/*) printf '0.300000' ;;
  https://slow.example/*) printf '3.000000' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fixture/bin/curl"
export PATH="$fixture/bin:$PATH" PROBES="$fixture/probes"

rank_arch_mirrors "$fixture/iso/mirrorlist" "$fixture/ranked"
cmp "$fixture/original" "$fixture/iso/mirrorlist"
[[ $(grep -c '^Server = ' "$fixture/ranked") == 7 ]]
[[ $(grep -m 1 '^Server = ' "$fixture/ranked") == 'Server = https://fast.example/arch/$repo/os/$arch' ]]
[[ $(wc -l < "$PROBES") == 4 ]]
grep -Fq 'https://fast.example/arch/core/os/x86_64/core.db' "$PROBES"
if FAIL_ALL=yes rank_arch_mirrors "$fixture/iso/mirrorlist" "$fixture/fallback"; then
  echo 'Mirror ranker accepted failed probes.' >&2; exit 1
fi
cmp "$fixture/original" "$fixture/iso/mirrorlist"

cleanup_boot_artifacts() { :; }
run_with_retry() { shift; "$@"; }
genfstab() { printf 'mock fstab\n'; }
pacstrap() {
  [[ "$1" == -C && "$3" == -K && "$4" == "$MOUNT_POINT" ]]
  ! grep -Fq 'DisableDownloadTimeout' "$2"
  if [[ "${FAIL_ALL:-no}" == yes ]]; then
    cmp "$fixture/original" "$fixture/iso/mirrorlist"
  else
    [[ $(grep -m 1 '^Server = ' "$fixture/iso/mirrorlist") == 'Server = https://fast.example/arch/$repo/os/$arch' ]]
  fi
  [[ "${FAIL_PACSTRAP:-no}" == no ]]
}
install_base_system "$fixture/iso/pacman.conf" "$fixture/iso/mirrorlist" > "$fixture/success-log" 2>&1
cmp "$fixture/original" "$fixture/iso/mirrorlist"
[[ $(grep -m 1 '^Server = ' "$MOUNT_POINT/etc/pacman.d/mirrorlist") == 'Server = https://fast.example/arch/$repo/os/$arch' ]]
[[ $(cat "$MOUNT_POINT/etc/pacman.d/mirrorlist.kmos-preinstall") == 'personal mirror preference' ]]
cmp "$fixture/original" "$MOUNT_POINT/etc/pacman.d/mirrorlist.kmos-original"

FAIL_ALL=yes install_base_system "$fixture/iso/pacman.conf" "$fixture/iso/mirrorlist" > "$fixture/fallback-log" 2>&1
cmp "$fixture/original" "$fixture/iso/mirrorlist"
grep -Fq 'Too few responsive mirrors' "$fixture/fallback-log"

if FAIL_PACSTRAP=yes install_base_system "$fixture/iso/pacman.conf" "$fixture/iso/mirrorlist" > "$fixture/failure-log" 2>&1; then
  echo 'pacstrap failure was not detected.' >&2; exit 1
fi
cmp "$fixture/original" "$fixture/iso/mirrorlist"
echo 'Arch mirror ranking, fallback and restoration: OK (mocked only).'
