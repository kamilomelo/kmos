#!/bin/bash
# kmos Wi-Fi Connect
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

# kartouche — copy this file into your project; https://github.com/kamilomelo/kartouche
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kamilo Melo
# KARTOUCHE_TEMPLATE_VERSION: 5
# Vendored from kartouche 26c10e8bcffcde4af82d9e9bc7238d020ea11042.
# MIT licensed: see the repository LICENSE; embedded here for standalone ISO copies.

# kartouche:config begin
KT_NAME='kmos Wi-Fi Connect'
KT_VERSION=
KT_DESCRIPTION='Connect the Arch ISO to Wi-Fi when ethernet is unavailable.'
KT_ACCENT='38;5;244'
KT_APPEND_ONLY=true
KT_GLYPHS=auto
# kartouche:config end

# kartouche:code begin v5
_kt_glyphs() {
    local set=unicode
    [[ $KT_GLYPHS == ascii || ( $KT_GLYPHS == auto && ( ${TERM:-} == linux || ${TERM:-} == dumb ) ) ]] && set=ascii
    if [[ $set == ascii ]]; then
        _kt_tl=, _kt_tr=. _kt_bl='`' _kt_br="'" _kt_h=- _kt_v='|' _kt_mid='|' _kt_arrow='>'
        _kt_dot='*' _kt_open=o _kt_active=@ _kt_sep='>' _kt_fill== _kt_ok=+ _kt_bad=x _kt_tip== _kt_small=.
    else
        _kt_tl=╭ _kt_tr=╮ _kt_bl=╰ _kt_br=╯ _kt_h=─ _kt_v=│ _kt_mid=├ _kt_arrow=❯
        _kt_dot=● _kt_open=○ _kt_active=◉ _kt_sep=› _kt_fill=━ _kt_ok=✓ _kt_bad=✗ _kt_tip=╸ _kt_small=·
    fi
}

_kt_text() { printf '%s' "${1//$'\n'/ }"; }
_kt_style() {
    local fd=$1 role=$2 value=$3 code
    if [[ -t $fd && -z ${NO_COLOR:-} && -n $value ]]; then
        case $role in dim) code=2;; bold) code=1;; accent) code=$KT_ACCENT;; both) code="1;$KT_ACCENT";; green) code=32;; red) code=31;; esac
        printf '\033[%sm%s\033[0m' "$code" "$value"
    else printf '%s' "$value"; fi
}
_kt_ver() { local v; v=$(_kt_text "$1"); [[ $v == v* ]] && printf '%s' "$v" || printf 'v%s' "$v"; }
_kt_repeat() { local c=$1 n=$2 s=; while (( n > 0 )); do s+=$c; (( n-- )) || :; done; printf '%s' "$s"; }
_kt_line() { local fd=$1 glyph=$2; shift 2; _kt_style "$fd" dim "${glyph}${_kt_h}"; printf ' %s' "$*"; }

kt_render_title() {
    local fd=$1 name ver
    name=$(_kt_text "$2"); ver=$3; _kt_glyphs
    _kt_style "$fd" dim "${_kt_tl}${_kt_h}"; printf ' '; _kt_style "$fd" accent "$_kt_dot"
    printf ' '; _kt_style "$fd" bold "$name"
    if [[ -n $ver ]]; then printf '  '; _kt_style "$fd" dim "$(_kt_ver "$ver")"; fi
    printf '\n'
}
kt_render_banner() {
    local fd=$1 name=$2 ver=$3 desc=$4 status=${5:-}
    desc=$(_kt_text "$desc"); status=$(_kt_text "$status"); _kt_glyphs
    kt_render_title "$fd" "$name" "$ver"
    if [[ -n $status ]]; then
        if [[ -n $desc ]]; then _kt_line "$fd" "$_kt_mid" "$status"; printf '\n'
        else _kt_style "$fd" dim "${_kt_bl}${_kt_h}${_kt_arrow}"; printf ' %s\n' "$status"; fi
    fi
    if [[ -n $desc ]]; then _kt_style "$fd" dim "${_kt_bl}${_kt_h}${_kt_arrow}"; printf ' %s\n' "$desc"; fi
    return 0
}
kt_render_card() {
    local fd=$1 name ver desc left right w bars pad
    name=$(_kt_text "$2"); ver=$(_kt_ver "$3"); desc=$(_kt_text "$4"); _kt_glyphs
    left=$(( ${#name}+3 )); right=$(( ${#ver}+4 )); w=$(( ${#desc}+4 ))
    (( w < left+right+2 )) && w=$((left+right+2))
    bars=$(_kt_repeat "$_kt_h" "$((w-left-right))"); pad=$(_kt_repeat ' ' "$((w-4-${#desc}))")
    _kt_style "$fd" dim "${_kt_tl}${_kt_h} "; _kt_style "$fd" bold "$name"
    _kt_style "$fd" dim " $bars  "; _kt_style "$fd" dim "$ver"; _kt_style "$fd" dim " ${_kt_h}${_kt_tr}"
    printf '\n'; _kt_style "$fd" dim "$_kt_v"; printf '  %s%s  ' "$desc" "$pad"; _kt_style "$fd" dim "$_kt_v"
    printf '\n'; _kt_style "$fd" dim "${_kt_bl}$(_kt_repeat "$_kt_h" "$w")${_kt_br}"; printf '\n'
    return 0
}
kt_render_end() {
    local fd=$1 ok=$2 text; text=$(_kt_text "$3"); _kt_glyphs
    _kt_style "$fd" dim "${_kt_bl}${_kt_h}"; printf ' '
    if [[ $ok == 1 ]]; then _kt_style "$fd" green "$_kt_ok"; else _kt_style "$fd" red "$_kt_bad"; fi
    printf ' %s\n' "$text"
}
kt_render_frame() {
    (( $# >= 5 )) || return 0
    local fd=$1 style=$2 n=$3 total=$4 label=$5; shift 5
    local -a labels=("$@")
    local decimal='^[1-9][0-9]*$'
    [[ $n =~ $decimal && $total =~ $decimal && ${#n} -le 15 && ${#total} -le 15 ]] || return 0
    (( n <= total + 1 )) || return 0
    local i count filled longest dots text sym role bar rest end=false
    _kt_glyphs; label=$(_kt_text "$label")
    (( n > total )) && end=true
    count="$n/$total"; [[ $end == true ]] && count="$total/$total"
    [[ $style == dots && $total -gt 12 ]] && style=line
    case $style in
        dots)
            _kt_style "$fd" dim "${_kt_mid}${_kt_h}"; printf ' '
            _kt_style "$fd" accent "$(_kt_repeat "$_kt_dot" "$((n>total ? total : n))")"
            _kt_style "$fd" dim "$(_kt_repeat "$_kt_open" "$((total-n>0 ? total-n : 0))")"
            printf '  '; _kt_style "$fd" dim "$count"; printf '\n';;
        crumbs)
            _kt_style "$fd" dim "${_kt_mid}${_kt_h}"; printf ' '
            for ((i=0;i<total;i++)); do
                (( i )) && { printf ' '; _kt_style "$fd" dim "$_kt_sep"; printf ' '; }
                text=$(_kt_text "${labels[i]}")
                if (( i==n-1 && n<=total )); then _kt_style "$fd" both "$text"; else _kt_style "$fd" dim "$text"; fi
            done; printf '\n';;
        rail)
            for ((i=0;i<total;i++)); do
                if (( i<n-1 || n>total )); then sym=$_kt_ok role=green
                elif (( i==n-1 )); then sym=$_kt_active role=accent
                else sym=$_kt_open role=dim; fi
                _kt_style "$fd" dim "${_kt_mid}${_kt_h}"; printf ' '; _kt_style "$fd" "$role" "$sym"; printf ' '
                text=$(_kt_text "${labels[i]}")
                if (( i==n-1 && n<=total )); then _kt_style "$fd" bold "$text"; else printf '%s' "$text"; fi
                printf '\n'
            done;;
        line)
            filled=$(((40*(n>total ? total : n)+total)/(2*total)))
            if (( filled==20 )); then bar=$(_kt_repeat "$_kt_fill" 20)
            elif (( filled==0 )); then bar=
            else bar="$(_kt_repeat "$_kt_fill" "$((filled-1))")${_kt_tip}"; fi
            rest=$(_kt_repeat "$_kt_h" "$((20-filled))")
            _kt_style "$fd" dim "${_kt_mid}${_kt_h}"; printf ' '; _kt_style "$fd" accent "$bar"
            _kt_style "$fd" dim "$rest"; printf '  '; _kt_style "$fd" dim "$count"; printf '\n';;
        log)
            longest=0
            for text in "${labels[@]}"; do text=$(_kt_text "$text"); (( ${#text}>longest )) && longest=${#text}; done
            for ((i=0;i<n-1 && i<total;i++)); do
                text=$(_kt_text "${labels[i]}"); dots=$(_kt_repeat "$_kt_small" "$((longest-${#text}+7))")
                _kt_style "$fd" dim "${_kt_mid}${_kt_h}"; printf ' %d/%d %s %s ' "$((i+1))" "$total" "$text" "$dots"
                _kt_style "$fd" accent ok; printf '\n'
            done;;
    esac
    _kt_style "$fd" dim "${_kt_bl}${_kt_h}${_kt_arrow}"; printf ' '
    if [[ $end == true || $style == rail ]]; then printf '%s\n' "$count"
    elif [[ $style == dots || $style == line ]]; then printf '%s\n' "$label"
    else printf '%s %s\n' "$count" "$label"; fi
    return 0
}

kt_render_summary() {
    (( $# >= 4 )) || return 0
    local fd=$1 style=$2 name=$3 version=$4; shift 4
    [[ $style == rail || $style == log ]] && (( $# % 2 == 0 )) || return 0
    local -a items=("$@")
    local total=$(( ${#items[@]} / 2 )) i label state longest=0 ok=0 failed=0 skipped=0 dots glyph role
    for ((i=0;i<total;i++)); do
        case ${items[2*i+1]} in
            ok) (( ok+=1 )) || :;;
            failed) (( failed+=1 )) || :;;
            skipped) (( skipped+=1 )) || :;;
            *) return 0;;
        esac
        label=$(_kt_text "${items[2*i]}")
        (( ${#label}>longest )) && longest=${#label}
    done
    kt_render_title "$fd" "$name" "$version"
    _kt_glyphs
    for ((i=0;i<total;i++)); do
        label=$(_kt_text "${items[2*i]}"); state=${items[2*i+1]}
        _kt_style "$fd" dim "${_kt_mid}${_kt_h}"; printf ' '
        if [[ $style == rail ]]; then
            case $state in
                ok) glyph=$_kt_ok role=green;;
                failed) glyph=$_kt_bad role=red;;
                skipped) glyph=$_kt_open role=dim;;
            esac
            _kt_style "$fd" "$role" "$glyph"; printf ' %s\n' "$label"
        else
            dots=$(_kt_repeat "$_kt_small" "$((longest-${#label}+7))")
            printf '%d/%d %s %s ' "$((i+1))" "$total" "$label" "$dots"
            case $state in ok) role=accent;; failed) role=red;; skipped) role=dim;; esac
            _kt_style "$fd" "$role" "$state"; printf '\n'
        fi
    done
    if (( failed )); then glyph=$_kt_bad role=red
    elif (( skipped || total==0 )); then glyph=$_kt_open role=dim
    else glyph=$_kt_ok role=green; fi
    _kt_style "$fd" dim "${_kt_bl}${_kt_h}"; printf ' '; _kt_style "$fd" "$role" "$glyph"
    printf ' %d ok %s %d failed %s %d skipped\n' "$ok" "$_kt_small" "$failed" "$_kt_small" "$skipped"
    return 0
}

kt_banner() { kt_render_banner 2 "$KT_NAME" "$KT_VERSION" "$KT_DESCRIPTION" "${1:-}" >&2 || :; }
kt_card() { kt_render_card 2 "$KT_NAME" "$KT_VERSION" "$KT_DESCRIPTION" >&2 || :; }
kt_summary() { local style=${1:-}; (( $# )) && shift || :; kt_render_summary 2 "$style" "$KT_NAME" "$KT_VERSION" "$@" >&2 || :; }
_kt_print_region() {
    local text=$1 line
    local -a lines=()
    mapfile -t lines <<< "$text"
    if (( _kt_prev )); then printf '\033[%dA' "$_kt_prev" >&2; fi
    for line in "${lines[@]}"; do
        if (( _kt_prev )); then printf '\r\033[2K' >&2; fi
        printf '%s\n' "$line" >&2
    done
    _kt_prev=${#lines[@]}
    return 0
}
_kt_show() {
    local end=${1:-} text
    if [[ $_kt_redraw == true ]]; then
        if (( _kt_total==0 )); then [[ -n $end ]] && printf '%s\n' "$end" >&2
        else
            text=$(kt_render_frame 2 "$_kt_style_name" "${2:-$_kt_n}" "$_kt_total" "${_kt_labels[_kt_n-1]}" "${_kt_labels[@]}")
            if [[ -n $end ]]; then text="${text%$'\n'*}"$'\n'"$end"; fi
            _kt_print_region "$text"
        fi
    elif [[ -n $end ]]; then printf '%s\n' "$end" >&2
    else
        _kt_glyphs; _kt_style 2 dim "${_kt_mid}${_kt_h}" >&2
        printf ' %d/%d %s\n' "$_kt_n" "$_kt_total" "$(_kt_text "${_kt_labels[_kt_n-1]}")" >&2
    fi
    return 0
}
kt_steps_start() {
    _kt_style_name=${1:-inline}; shift || :; _kt_labels=("$@"); _kt_total=${#_kt_labels[@]}
    _kt_n=0 _kt_prev=0 _kt_finished=false _kt_started=${EPOCHREALTIME:-0}
    _kt_redraw=false; [[ -t 2 && $KT_APPEND_ONLY != true ]] && _kt_redraw=true
    kt_render_title 2 "$KT_NAME" "$KT_VERSION" >&2 || :
    if (( _kt_total )); then _kt_n=1; _kt_show; fi
    return 0
}
kt_steps_next() {
    if [[ ${_kt_finished:-true} == false ]] && (( _kt_n<_kt_total )); then
        (( _kt_n++ )) || :; _kt_show
    fi
    return 0
}
kt_steps_done() {
    [[ ${_kt_finished:-true} == true ]] && return 0
    _kt_finished=true
    local elapsed=${1:-}
    if [[ $# == 0 ]]; then
        local start=${_kt_started/./} now=${EPOCHREALTIME/./} tenths
        tenths=$(((10#$now-10#$start+50000)/100000))
        printf -v elapsed '%d.%ds' "$((tenths/10))" "$((tenths%10))"
    fi
    _kt_show "$(kt_render_end 2 1 "done in $elapsed")" "$((_kt_total+1))"
    return 0
}
kt_steps_fail() {
    [[ ${_kt_finished:-true} == true ]] && return 0
    _kt_finished=true
    local text=failed reason=${1:-}
    if (( _kt_total )); then text="failed at $_kt_n/$_kt_total $(_kt_text "${_kt_labels[_kt_n-1]}")"; fi
    [[ -n $reason ]] && text+=" · $(_kt_text "$reason")"
    _kt_show "$(kt_render_end 2 0 "$text")"
    return 0
}
# kartouche:code end

UI_RESET=""
UI_BOLD=""
UI_DIM=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""
SUCCESS_ICON="▸"
STEP_INDEX=0
STEP_LABELS=(
  'Selecting wireless adapter'
  'Selecting Wi-Fi network'
  'Connecting to Wi-Fi'
  'Verifying internet access'
)
NETWORK_NAMES=()
WIFI_HANDOFF_DIR="/run/kmos/wifi"

init_ui() {
  if [[ ${TERM:-} == linux ]]; then KT_ACCENT=37; fi
  if [[ -t 2 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_DIM=$'\033[2m'
    UI_INFO=$'\033[37m'
    UI_SUCCESS=$'\033[32m'
    UI_WARN=$'\033[33m'
    UI_DANGER=$'\033[31m'
  fi

  if [[ "${TERM:-}" == "linux" || "${kmos_ASCII_UI:-0}" == "1" ]]; then
    SUCCESS_ICON=">"
    KT_GLYPHS=ascii
  fi
}

log() {
  printf '%s\n' "$*" >&2
}

info() {
  printf '%b%s%b\n' "${UI_INFO}${UI_BOLD}" "$*" "$UI_RESET" >&2
}

warn() {
  printf '%bWARNING:%b %s\n' "${UI_WARN}${UI_BOLD}" "$UI_RESET" "$*" >&2
}

success() {
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

die() {
  if ((STEP_INDEX > 0)); then
    kt_render_end 2 0 "failed at $STEP_INDEX/${#STEP_LABELS[@]} ${STEP_LABELS[STEP_INDEX-1]} · $*" >&2
  fi
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

detail() {
  local key="$1"
  local value="$2"
  printf '  %b%-12s%b %s\n' "$UI_DIM" "$key" "$UI_RESET" "$value" >&2
}

advance_step() {
  ((STEP_INDEX += 1))
  printf '\n' >&2
  kt_render_title 2 "$KT_NAME" "$KT_VERSION" >&2
  kt_render_frame 2 rail "$STEP_INDEX" "${#STEP_LABELS[@]}" \
    "${STEP_LABELS[STEP_INDEX-1]}" "${STEP_LABELS[@]}" >&2
  printf '\n' >&2
}

print_banner() {
  printf '\n' >&2
  kt_banner
}

require_root() {
  ((EUID == 0)) && return
  command -v sudo >/dev/null 2>&1 || die "Root access is required, but sudo is not installed."
  info "Root access is needed to configure Wi-Fi; sudo will prompt for your password."
  exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
}

require_tools() {
  local missing=()
  local tools=(chmod cp ip iwctl mkdir rfkill ping sed timedatectl)
  local t

  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-}"
  local answer=""

  while true; do
    if [[ "$default" == "yes" ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-Y}"
    elif [[ "$default" == "no" ]]; then
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-N}"
    else
      read -r -p "$prompt [y/n]: " answer
    fi

    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

unblock_wireless() {
  rfkill unblock all >/dev/null 2>&1 || die "Could not unblock wireless devices."
}

detect_wireless_adapter() {
  local path=""
  local adapter=""

  for path in /sys/class/net/*; do
    [[ -e "$path" ]] || continue
    adapter="${path##*/}"
    [[ "$adapter" == "lo" ]] && continue
    if [[ -d "$path/wireless" ]]; then
      printf '%s\n' "$adapter"
      return 0
    fi
  done

  for path in /sys/class/net/wlan* /sys/class/net/wl*; do
    [[ -e "$path" ]] || continue
    adapter="${path##*/}"
    printf '%s\n' "$adapter"
    return 0
  done

  return 1
}

is_wireless_adapter() {
  local adapter="$1"

  [[ -n "$adapter" ]] || return 1
  [[ -d "/sys/class/net/$adapter" ]] || return 1
  [[ -d "/sys/class/net/$adapter/wireless" ]] || return 1
}

prompt_manual_adapter() {
  local adapter=""

  while true; do
    ip link >&2
    printf '\n' >&2
    read -r -p "Enter wireless device name [q to quit]: " adapter

    case "$adapter" in
      [Qq]) die "No valid wireless adapter selected." ;;
    esac

    if is_wireless_adapter "$adapter"; then
      printf '%s\n' "$adapter"
      return 0
    fi

    if [[ -d "/sys/class/net/$adapter" ]]; then
      warn "$adapter exists, but it does not look like a wireless adapter."
    else
      warn "$adapter was not found."
    fi

    ask_yes_no "Try another adapter?" "yes" || die "No valid wireless adapter selected."
  done
}

select_wireless_adapter() {
  local detected=""

  detected="$(detect_wireless_adapter || true)"

  if [[ -n "$detected" ]]; then
    detail "Detected" "$detected"
    if ask_yes_no "Use this wireless adapter?" "yes"; then
      if is_wireless_adapter "$detected"; then
        printf '%s\n' "$detected"
        return 0
      fi
      warn "$detected was detected by name, but it does not look like a wireless adapter."
    fi
  else
    warn "No wireless adapter was detected automatically."
  fi

  prompt_manual_adapter
}

scan_wifi_networks() {
  local adapter="$1"
  local output=""
  local line=""
  local ssid=""
  local duplicate=0
  local existing=""
  local index=1

  NETWORK_NAMES=()

  info "Scanning available Wi-Fi networks"
  if ! iwctl station "$adapter" scan; then
    warn "Wi-Fi scan failed. You can still enter the SSID manually."
    return 1
  fi

  sleep 2
  if ! output="$(iwctl station "$adapter" get-networks 2>&1)"; then
    printf '%s\n' "$output" >&2
    warn "Could not list Wi-Fi networks. You can still enter the SSID manually."
    return 1
  fi

  while IFS= read -r line; do
    line="$(printf '%s\n' "$line" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g; s/^[[:space:]>]+//; s/[[:space:]]+$//')"
    [[ -n "$line" ]] || continue
    [[ "$line" == "Available networks"* ]] && continue
    [[ "$line" == "Network name"* ]] && continue
    [[ "$line" == "Security"* ]] && continue
    [[ "$line" == --* ]] && continue

    ssid="$(printf '%s\n' "$line" | sed -E 's/[[:space:]]{2,}.*$//')"
    [[ -n "$ssid" ]] || continue

    duplicate=0
    for existing in "${NETWORK_NAMES[@]}"; do
      if [[ "$existing" == "$ssid" ]]; then
        duplicate=1
        break
      fi
    done
    (( duplicate == 0 )) && NETWORK_NAMES+=("$ssid")
  done <<< "$output"

  if [[ ${#NETWORK_NAMES[@]} -eq 0 ]]; then
    printf '%s\n' "$output" >&2
    warn "No Wi-Fi names could be parsed from the scan. You can enter the SSID manually."
    return 1
  fi

  info "Available Wi-Fi networks:"
  for ssid in "${NETWORK_NAMES[@]}"; do
    printf '  %d) %s\n' "$index" "$ssid" >&2
    ((index++))
  done
}

prompt_wifi_credentials() {
  local -n out_ssid="$1"
  local -n out_password="$2"
  local -n out_hidden="$3"
  local selected_ssid=""
  local wifi_password=""
  local choice=""

  printf '\n' >&2
  if [[ ${#NETWORK_NAMES[@]} -gt 0 ]]; then
    printf '  m) Manual or hidden network\n' >&2
    while true; do
      read -r -p "Select Wi-Fi network [1-${#NETWORK_NAMES[@]}/m]: " choice
      case "$choice" in
        [Mm])
          read -r -p "Wi-Fi SSID: " selected_ssid
          ask_yes_no "Is this a hidden network?" "no" && out_hidden=1 || out_hidden=0
          break
          ;;
        ''|*[!0-9]*)
          warn "Invalid selection."
          ;;
        *)
          if (( choice >= 1 && choice <= ${#NETWORK_NAMES[@]} )); then
            selected_ssid="${NETWORK_NAMES[$((choice - 1))]}"
            out_hidden=0
            break
          fi
          warn "Invalid selection."
          ;;
      esac
    done
  else
    read -r -p "Wi-Fi SSID: " selected_ssid
    ask_yes_no "Is this a hidden network?" "no" && out_hidden=1 || out_hidden=0
  fi

  [[ -n "$selected_ssid" ]] || die "SSID cannot be empty."
  success "Network name is $selected_ssid"

  read -r -s -p "Wi-Fi password: " wifi_password
  printf '\n' >&2
  [[ -n "$wifi_password" ]] || die "Password cannot be empty."

  out_ssid="$selected_ssid"
  out_password="$wifi_password"
}

connect_wifi() {
  local adapter="$1"
  local ssid_name="$2"
  local password="$3"
  local hidden_network="$4"

  info "Connecting to internet"
  if [[ "$hidden_network" == "1" ]]; then
    iwctl --passphrase "$password" station "$adapter" connect-hidden "$ssid_name"
  else
    iwctl --passphrase "$password" station "$adapter" connect "$ssid_name"
  fi
  sleep 2
  success "Connection command completed."
}

save_wifi_handoff() {
  local adapter="$1"
  local ssid_name="$2"
  local password="$3"
  local hidden_network="$4"

  mkdir -p "$WIFI_HANDOFF_DIR"
  chmod 700 "${WIFI_HANDOFF_DIR%/*}" "$WIFI_HANDOFF_DIR"
  printf '%s\n' "$adapter" > "$WIFI_HANDOFF_DIR/adapter"
  printf '%s\n' "$ssid_name" > "$WIFI_HANDOFF_DIR/ssid"
  printf '%s\n' "$password" > "$WIFI_HANDOFF_DIR/password"
  printf '%s\n' "$hidden_network" > "$WIFI_HANDOFF_DIR/hidden"
  chmod 600 "$WIFI_HANDOFF_DIR/adapter" "$WIFI_HANDOFF_DIR/ssid" "$WIFI_HANDOFF_DIR/password" "$WIFI_HANDOFF_DIR/hidden"

  if [[ -d /var/lib/iwd ]]; then
    mkdir -p "$WIFI_HANDOFF_DIR/iwd"
    cp -a /var/lib/iwd/. "$WIFI_HANDOFF_DIR/iwd/"
    chmod -R go-rwx "$WIFI_HANDOFF_DIR/iwd"
  fi
}

verify_internet() {
  info "Verifying internet connectivity"
  ping -c 3 km-robota.com || return 1
  sleep 1
  success "Internet connection verified."
}

print_next_commands() {
  local repo_url="https://github.com/kamilomelo/kmos.git"

  info "Next commands after network is ready:"
  printf '\n%s\n' "  git clone $repo_url" >&2
  printf '%s\n' "  cd kmos" >&2
  printf '%s\n\n' "  git pull --ff-only" >&2
}

main() {
  local adapter=""
  local ssid_name=""
  local password=""
  local hidden_network=0
  local label
  local -a summary_args=()

  init_ui
  print_banner
  require_root "$@"
  require_tools

  unblock_wireless

  advance_step
  adapter="$(select_wireless_adapter)"
  detail "Adapter" "$adapter"

  advance_step
  scan_wifi_networks "$adapter" || true
  prompt_wifi_credentials ssid_name password hidden_network

  advance_step
  connect_wifi "$adapter" "$ssid_name" "$password" "$hidden_network"

  advance_step
  verify_internet || die "Then go and fix it."
  save_wifi_handoff "$adapter" "$ssid_name" "$password" "$hidden_network"
  unset password
  printf '\n' >&2
  info "Updating system clock"
  timedatectl set-timezone Europe/Zurich
  timedatectl set-ntp true
  timedatectl status
  printf '\n' >&2
  #print_next_commands
  for label in "${STEP_LABELS[@]}"; do summary_args+=("$label" ok); done
  kt_summary rail "${summary_args[@]}"
  printf '\n' >&2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
