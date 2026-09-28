#!/usr/bin/env bash
# systemd-only cleanup: the installer may have been launched by alarm itself.
set -Eeuo pipefail

if record=$(getent passwd alarm); then
  IFS=: read -r _ _ _ _ _ home shell <<< "$record"
  if [[ "$home" != /home/alarm || "$shell" != /usr/bin/nologin ]]; then
    printf 'ERROR: alarm changed since removal was scheduled; refusing to remove it.\n' >&2
    exit 1
  fi
  userdel -r alarm
fi
if getent passwd alarm >/dev/null; then
  printf 'ERROR: alarm still exists; retry or inspect the service logs.\n' >&2
  exit 1
fi
if [[ -e /home/alarm || -L /home/alarm ]]; then
  printf 'ERROR: /home/alarm still exists; inspect it before removing anything.\n' >&2
  exit 1
fi
systemctl disable kmos-remove-alarm.service
printf 'Initial alarm account and home have been removed.\n'
