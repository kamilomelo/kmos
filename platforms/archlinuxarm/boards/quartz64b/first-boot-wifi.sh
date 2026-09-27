#!/usr/bin/env bash
# Runs natively on the Quartz64 at first boot; never on the x86 SD writer host.
set -Eeuo pipefail

install_offline_wifi() (
  local cache=$1 marker=$2 config
  local -a ell=() iwd=()
  config=$(mktemp "${TMPDIR:-/run}/kmos-wifi-pacman.XXXXXXXX")
  trap 'rm -f -- "$config"' EXIT
  shopt -s nullglob
  ell=("$cache"/ell-*-aarch64.pkg.tar.xz "$cache"/ell-*-aarch64.pkg.tar.zst)
  iwd=("$cache"/iwd-*-aarch64.pkg.tar.xz "$cache"/iwd-*-aarch64.pkg.tar.zst)
  [[ ${#ell[@]} == 1 && ${#iwd[@]} == 1 ]] || { printf 'Expected exactly one ell and iwd package in %s.\n' "$cache" >&2; return 1; }
  [[ -f "${ell[0]}.sig" && -f "${iwd[0]}.sig" ]] || { printf 'Missing detached ARM package signatures.\n' >&2; return 1; }

  pacman-key --init
  pacman-key --populate archlinuxarm
  cp "${KMOS_PACMAN_CONF:-/etc/pacman.conf}" "$config"
  if grep -q '^LocalFileSigLevel[[:space:]]*=' "$config"; then
    sed -i 's/^LocalFileSigLevel[[:space:]]*=.*/LocalFileSigLevel = Required/' "$config"
  else
    sed -i '/^\[options\]$/a LocalFileSigLevel = Required' "$config"
  fi
  pacman --config "$config" -U --noconfirm -- "${ell[0]}" "${iwd[0]}"
  pacman -Q ell iwd >/dev/null
  systemctl enable --now iwd.service
  install -d -m 0755 "${marker%/*}"
  touch "$marker"
  printf 'Offline ARM Wi-Fi packages installed; iwd enabled. Check Wi-Fi association and DHCP.\n'
)

main() {
  [[ $(uname -m) == aarch64 ]] || { printf 'Wi-Fi package install requires AArch64.\n' >&2; exit 1; }
  install_offline_wifi /var/lib/kmos/wifi-packages /var/lib/kmos/quartz64b-wifi-packages-installed
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
