#!/usr/bin/env bash
# Shared root-only iwd WPA-Personal profile writer for host SD prep and board.

validate_wifi_credentials() {
  local ssid=$1 passphrase=$2
  [[ "$ssid" =~ ^[a-zA-Z0-9_\ -]{1,32}$ ]] || return 1
  [[ ${#passphrase} -ge 8 && ${#passphrase} -le 63 && "$passphrase" != *$'\r'* && "$passphrase" != *$'\n'* ]] || return 1
}

write_iwd_profile() {
  local state_dir=$1 ssid=$2 passphrase=$3 hidden=$4
  local profile="$state_dir/$ssid.psk" escaped=$passphrase
  validate_wifi_credentials "$ssid" "$passphrase" || return 1
  [[ "$hidden" == true || "$hidden" == false ]] || return 1
  [[ ! -e "$profile" && ! -L "$profile" ]] || return 1
  install -d -m 0700 "$state_dir"
  # iwd uses GNOME keyfile escaping. Avoid accidental interpretation of a
  # passphrase beginning with whitespace or containing a backslash.
  escaped=${escaped//\\/\\\\}
  [[ "$escaped" != ' '* ]] || escaped="\\s${escaped:1}"
  ( umask 077
    {
      printf '[Settings]\nAutoConnect=true\nHidden=%s\n\n' "$hidden"
      printf '[Security]\nPassphrase=%s\n' "$escaped"
    } > "$profile"
  )
  chmod 0600 "$profile"
}
