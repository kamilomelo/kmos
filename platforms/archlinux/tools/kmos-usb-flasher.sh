#!/bin/bash
# kmos USB Flasher
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
# kartouche — copy this file into your project; https://github.com/kamilomelo/kartouche
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kamilo Melo
# KARTOUCHE_TEMPLATE_VERSION: 5
# Vendored from kartouche 26c10e8bcffcde4af82d9e9bc7238d020ea11042.
# MIT licensed: see the repository LICENSE; embedded here for standalone copies.

# kartouche:config begin
KT_NAME='kmos USB Flasher'
KT_VERSION=
KT_DESCRIPTION='Bootable USB creator for Arch Linux and Rocky Linux.'
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
WORK_DIR="$SCRIPT_DIR/work"
ARCH_BASE_URL="${ARCH_BASE_URL:-https://theswissbay.ch/archlinux/iso/latest}"
ARCH_BASE_URL_FALLBACKS="${ARCH_BASE_URL_FALLBACKS:-https://mirror.puzzle.ch/archlinux/iso/latest https://mirror.init7.net/archlinux/iso/latest https://mirror.arch-linux.ch/archlinux/iso/latest https://mirror.metanet.ch/archlinux/iso/latest https://geo.mirror.pkgbuild.com/iso/latest}"
ROCKY_BASE_URL="${ROCKY_BASE_URL:-https://mirror.init7.net/rockylinux}"
ROCKY_BASE_URL_FALLBACKS="${ROCKY_BASE_URL_FALLBACKS:-https://mirror.puzzle.ch/rockylinux https://rocky-linux-europe-west6.production.gcp.mirrors.ctrliq.cloud/pub/rocky https://dl.rockylinux.org/pub/rocky https://download.rockylinux.org/pub/rocky}"
ARCH="x86_64"
ARCH_BASE_URLS=()
ROCKY_BASE_URLS=()

strip_mount_metadata() {
  local source="$1"
  printf '%s\n' "${source%%\[*}"
}

parent_disk_for_mount() {
  local mount_source="$1"
  local block_source=""
  local parent_name=""

  [[ -n "$mount_source" ]] || return 0
  block_source="$(strip_mount_metadata "$mount_source")"
  parent_name="$(lsblk -no pkname "$block_source" 2>/dev/null || true)"

  if [[ -n "$parent_name" ]]; then
    printf '/dev/%s\n' "$parent_name"
  fi
}

SCRIPT_DEV="$(findmnt -n -o SOURCE --target "$SCRIPT_DIR" 2>/dev/null || true)"
SCRIPT_DISK=""
if [[ -n "$SCRIPT_DEV" ]]; then
  SCRIPT_DISK="$(parent_disk_for_mount "$SCRIPT_DEV")"
fi

ROOT_DEV="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_DISK=""
if [[ -n "$ROOT_DEV" ]]; then
  ROOT_DISK="$(parent_disk_for_mount "$ROOT_DEV")"
fi

UI_RESET=""
UI_BOLD=""
UI_DIM=""
UI_HEADER=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""
STEP_INDEX=0
STEP_LABELS=(
  'Preparing installation media'
  'Selecting target USB disk'
  'Flashing image to USB'
  'Final cleanup'
)

repeat_char() {
  local char="$1"
  local count="$2"
  local out=""

  while (( count > 0 )); do
    out+="$char"
    ((count--))
  done

  printf '%s' "$out"
}

init_ui() {
  # The Linux console does not reliably render the 256-color gray accent.
  if [[ ${TERM:-} == linux ]]; then
    KT_ACCENT=37
  fi
  if [[ -t 2 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_DIM=$'\033[2m'
    if [[ ${TERM:-} == linux ]]; then
      UI_HEADER=$'\033[37m'
    else
      UI_HEADER=$'\033[38;5;244m'
    fi
    UI_INFO=$'\033[37m'
    UI_SUCCESS=$'\033[32m'
    UI_WARN=$'\033[33m'
    UI_DANGER=$'\033[31m'
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
  local icon=▸
  if [[ $KT_GLYPHS == ascii || ( $KT_GLYPHS == auto && ( ${TERM:-} == linux || ${TERM:-} == dumb ) ) ]]; then
    icon='>'
  fi
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$icon" "$UI_RESET" "$*" >&2
}

die() {
  if ((STEP_INDEX > 0)); then
    kt_render_end 2 0 "failed at $STEP_INDEX/${#STEP_LABELS[@]} ${STEP_LABELS[STEP_INDEX-1]} · $*" >&2
  fi
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

section() {
  local title="$1"
  printf '\n%b%s%b\n' "${UI_HEADER}${UI_BOLD}" "$title" "$UI_RESET" >&2
  printf '%s\n' "$(repeat_char "=" "${#title}")" >&2
}

detail() {
  local key="$1"
  local value="$2"
  printf '  %b%-12s%b %s\n' "$UI_DIM" "$key" "$UI_RESET" "$value" >&2
}

advance_step() {
  ((STEP_INDEX += 1))
  printf '\n' >&2
  # A fresh, append-only rail snapshot is safe alongside curl/dd progress.
  kt_render_title 2 "$KT_NAME" "$KT_VERSION" >&2
  kt_render_frame 2 rail "$STEP_INDEX" "${#STEP_LABELS[@]}" \
    "${STEP_LABELS[STEP_INDEX-1]}" "${STEP_LABELS[@]}" >&2
  printf '\n' >&2
}

substep() {
  printf '  %b>%b %s\n' "$UI_DIM" "$UI_RESET" "$*" >&2
}

warning_block() {
  local message="$1"
  printf '\n%b%s%b\n' "${UI_DANGER}${UI_BOLD}" "Warning" "$UI_RESET" >&2
  printf '  %s\n' "$message" >&2
}

print_banner() {
  printf '\n' >&2
  kt_banner
  printf '\n' >&2
  log "Downloads, verifies, and writes the selected ISO to a USB device."
  log "Warning: the selected target disk will be erased."
}

normalize_url() {
  printf '%s\n' "${1%/}"
}

init_base_urls() {
  local fallback
  ARCH_BASE_URLS=("$(normalize_url "$ARCH_BASE_URL")")
  ROCKY_BASE_URLS=("$(normalize_url "$ROCKY_BASE_URL")")

  for fallback in $ARCH_BASE_URL_FALLBACKS; do
    ARCH_BASE_URLS+=("$(normalize_url "$fallback")")
  done

  for fallback in $ROCKY_BASE_URL_FALLBACKS; do
    ROCKY_BASE_URLS+=("$(normalize_url "$fallback")")
  done
}

resolve_base_url() {
  local -n mirrors_ref="$1"
  local mirror

  for mirror in "${mirrors_ref[@]}"; do
    [[ -n "$mirror" ]] || continue
    if curl -fsSL --connect-timeout 10 --max-time 20 -o /dev/null "$mirror/"; then
      printf '%s\n' "$mirror"
      return 0
    fi
    warn "Mirror unavailable: $mirror"
  done

  return 1
}

require_tools() {
  local missing=()
  local tools=(curl awk sed grep sort lsblk findmnt sha256sum b2sum dd)
  local t
  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}"
  fi
}

ensure_workdir() {
  mkdir -p "$WORK_DIR"
}

prompt_menu() {
  local prompt="$1"
  shift
  local options=("$@")
  local i=1
  local choice

  log "$prompt"
  for opt in "${options[@]}"; do
    printf '  %d) %s\n' "$i" "$opt" >&2
    ((i++))
  done

  while true; do
    read -r -p "Select [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      printf '%s\n' "$choice"
      return 0
    fi
    log "Invalid selection."
  done
}

confirm_yes_no() {
  local prompt="$1"
  local default_no="${2:-1}"
  local answer

  while true; do
    if [[ "$default_no" == "1" ]]; then
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-N}"
    else
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-Y}"
    fi

    case "$answer" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) log "Please answer yes or no." ;;
    esac
  done
}

fetch_latest_arch_iso_name() {
  local base_url="$1"
  local index
  index="$(curl -fsSL "$base_url/")" || return 1

  local latest
  latest="$(printf '%s\n' "$index" \
    | grep -Eo 'archlinux-x86_64-[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.iso' \
    | sort -u \
    | tail -n1 || true)"

  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest"
  else
    printf '%s\n' "archlinux-x86_64.iso"
  fi
}

download_file() {
  local url="$1"
  local out="$2"

  substep "Downloading $(basename "$out")"

  if [[ -t 2 ]]; then
    curl --progress-bar -fL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$out" "$url"
  else
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$out" "$url"
  fi
}

verify_arch_download() {
  local iso="$1"
  local sha_file="$2"
  local b2_file="$3"

  grep " $iso$" "$sha_file" | sha256sum -c - >/dev/null
  grep " $iso$" "$b2_file" | b2sum -c - >/dev/null
}

prepare_arch() {
  local arch_base_url
  arch_base_url="$(resolve_base_url ARCH_BASE_URLS)" || die "No reachable Arch mirror found"
  detail "Arch mirror" "$arch_base_url"

  local iso
  iso="$(fetch_latest_arch_iso_name "$arch_base_url")" || die "Cannot read Arch latest index"

  local sha_file="sha256sums.txt"
  local b2_file="b2sums.txt"
  local arch_dir="$WORK_DIR/arch"

  mkdir -p "$arch_dir"
  cd "$arch_dir"

  local needs_download=0
  [[ -f "$iso" && -f "$sha_file" && -f "$b2_file" ]] || needs_download=1

  if (( needs_download == 0 )); then
    if verify_arch_download "$iso" "$sha_file" "$b2_file"; then
      success "Arch ISO already present and verified."
      printf '%s\n' "$arch_dir/$iso"
      return 0
    fi
    warn "Existing Arch files failed verification. Re-downloading."
  else
    info "Downloading Arch ISO and checksums."
  fi

  rm -f "$iso" "$sha_file" "$b2_file"
  download_file "$arch_base_url/$iso" "$iso"
  download_file "$arch_base_url/$sha_file" "$sha_file"
  download_file "$arch_base_url/$b2_file" "$b2_file"

  verify_arch_download "$iso" "$sha_file" "$b2_file" || die "Arch checksum verification failed"
  success "Arch ISO verified."
  printf '%s\n' "$arch_dir/$iso"
}

fetch_latest_rocky_major() {
  local base_url="$1"
  local index
  index="$(curl -fsSL "$base_url/")" || return 1

  printf '%s\n' "$index" \
    | grep -Eo 'href="[0-9]+/"' \
    | grep -Eo '[0-9]+' \
    | sort -n \
    | tail -n1
}

verify_rocky_download() {
  local iso_name="$1"
  local checksum_file="$2"
  local expected actual

  expected="$(
    awk -v iso="$iso_name" '
      $0 ~ /^[[:xdigit:]]{64}[[:space:]]+\*?.+/ {
        hash=$1
        file=$2
        sub(/^\*/, "", file)
        if (file == iso) {
          print tolower(hash)
          exit
        }
      }
      $0 ~ /^SHA256 \(.+\) = [[:xdigit:]]{64}$/ {
        line=$0
        sub(/^SHA256 \(/, "", line)
        sub(/\) = [[:xdigit:]]{64}$/, "", line)
        hash=$NF
        if (line == iso) {
          print tolower(hash)
          exit
        }
      }
    ' "$checksum_file"
  )"

  [[ -n "$expected" ]] || return 1
  actual="$(sha256sum "$iso_name" | awk '{print tolower($1)}')"
  [[ "$actual" == "$expected" ]]
}

prepare_rocky() {
  local rocky_base_url
  rocky_base_url="$(resolve_base_url ROCKY_BASE_URLS)" || die "No reachable Rocky mirror found"
  detail "Rocky mirror" "$rocky_base_url"

  local major
  major="$(fetch_latest_rocky_major "$rocky_base_url")"
  [[ -n "$major" ]] || die "Cannot determine latest Rocky major version"

  local rocky_variant_choice
  rocky_variant_choice="$(prompt_menu "Choose Rocky image" "Minimal" "KDE Live")"

  local iso_dir
  local iso_name
  local checksum_name=""

  if [[ "$rocky_variant_choice" == "1" ]]; then
    iso_dir="$rocky_base_url/$major/isos/$ARCH"
    iso_name="Rocky-${major}-latest-${ARCH}-minimal.iso"
  else
    iso_dir="$rocky_base_url/$major/live/$ARCH"
    iso_name="Rocky-${major}-KDE-${ARCH}-latest.iso"
  fi
  checksum_name="${iso_name}.CHECKSUM"

  local rocky_dir="$WORK_DIR/rocky"
  mkdir -p "$rocky_dir"
  cd "$rocky_dir"

  local needs_download=0
  [[ -f "$iso_name" && -f "$checksum_name" ]] || needs_download=1

  if (( needs_download == 0 )); then
    if verify_rocky_download "$iso_name" "$checksum_name"; then
      success "Rocky ISO already present and verified."
      printf '%s\n' "$rocky_dir/$iso_name"
      return 0
    fi
    warn "Existing Rocky files failed verification. Re-downloading."
  else
    info "Downloading Rocky ISO and checksum."
  fi

  rm -f "$iso_name" "$checksum_name"
  download_file "$iso_dir/$iso_name" "$iso_name" || die "Failed downloading $iso_name"
  download_file "$iso_dir/$checksum_name" "$checksum_name" || die "Failed downloading CHECKSUM"

  verify_rocky_download "$iso_name" "$checksum_name" || die "Rocky checksum verification failed"
  success "Rocky ISO verified."
  printf '%s\n' "$rocky_dir/$iso_name"
}

list_candidate_usb_disks() {
  lsblk -dn -o NAME,TYPE,TRAN,RM \
    | awk '$2=="disk" && ($3=="usb" || $4=="1") {print "/dev/"$1}'
}

print_disks() {
  section "Available Disks"
  lsblk -d -o NAME,SIZE,TRAN,RM,MODEL >&2
}

validate_target_disk() {
  local dev="$1"
  [[ -b "$dev" ]] || return 1
  [[ "$(lsblk -dn -o TYPE "$dev" 2>/dev/null)" == "disk" ]] || return 1
  return 0
}

select_target_disk() {
  local target=""
  local candidates=()
  local use_auto=""
  local ack=""

  mapfile -t candidates < <(list_candidate_usb_disks)

  info "Insert the USB drive now, then press Enter."
  read -r

  mapfile -t candidates < <(list_candidate_usb_disks)

  if [[ ${#candidates[@]} -eq 1 ]]; then
    target="${candidates[0]}"
    success "Auto-detected USB device: $target"
    read -r -p "Use this device? [y/N]: " use_auto
    if [[ ! "$use_auto" =~ ^[Yy]$ ]]; then
      target=""
    fi
  fi

  if [[ -z "$target" ]]; then
    print_disks
    read -r -p "Enter target disk (example: /dev/sdb): " target
  fi

  validate_target_disk "$target" || die "Invalid disk: $target"

  if [[ -n "$SCRIPT_DISK" && "$target" == "$SCRIPT_DISK" ]]; then
    die "Refusing to write to the script host disk: $target"
  fi

  if [[ -n "$ROOT_DISK" && "$target" == "$ROOT_DISK" ]]; then
    read -r -p "Selected disk seems to hold current OS ($target). Type 'I understand' to continue: " ack
    [[ "$ack" == "I understand" ]] || die "Cancelled"
  fi

  printf '%s\n' "$target"
}

unmount_target_partitions() {
  local disk="$1"
  local part mp

  while read -r part mp; do
    if [[ -n "$mp" ]]; then
      run_privileged umount "/dev/$part" || die "Failed to unmount /dev/$part"
    fi
  done < <(lsblk -nr -o NAME,MOUNTPOINT "$disk")
}

run_privileged() {
  if ((EUID == 0)); then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "Root access is required, but sudo is not installed."
    info "Root access is needed to write installation media; sudo will prompt for your password."
    sudo -- "$@"
  fi
}

flash_iso() {
  local iso_path="$1"
  local target_disk="$2"

  [[ -f "$iso_path" ]] || die "ISO not found: $iso_path"

  section "Ready To Flash"
  detail "ISO" "$iso_path"
  detail "Target" "$target_disk"
  warning_block "All data on $target_disk will be permanently erased."
  confirm_yes_no "Proceed with flashing?" 1 || die "Cancelled"

  unmount_target_partitions "$target_disk"

  info "Writing image to USB. This can take several minutes."
  run_privileged dd if="$iso_path" of="$target_disk" bs=4M status=progress oflag=sync conv=fsync
  sync
  success "USB should be ready."
}

cleanup_workdir_prompt() {
  if confirm_yes_no "Delete work directory ($WORK_DIR)?" 1; then
    rm -rf -- "$WORK_DIR"
    success "Work directory deleted."
  else
    log "Work directory kept."
  fi
}

prepare_iso_for_os() {
  local os_key="$1"
  case "$os_key" in
    arch) prepare_arch ;;
    rocky) prepare_rocky ;;
    *) die "Unsupported OS provider: $os_key" ;;
  esac
}

main() {
  local label
  local -a summary_args=()
  init_ui
  require_tools
  init_base_urls
  ensure_workdir

  print_banner
  log ""
  detail "Work dir" "$WORK_DIR"

  local os_choice=""
  section "Choose Operating System"
  printf '  1) Arch Linux (default)\n' >&2
  printf '  2) Rocky Linux\n' >&2
  while true; do
    read -r -p "Select [1-2] (default: 1): " os_choice
    os_choice="${os_choice:-1}"
    if [[ "$os_choice" =~ ^[12]$ ]]; then
      break
    fi
    log "Invalid selection."
  done

  local os_key
  local os_label
  if [[ "$os_choice" == "1" ]]; then
    os_key="arch"
    os_label="Arch Linux"
  else
    os_key="rocky"
    os_label="Rocky Linux"
  fi
  detail "Selected OS" "$os_label"

  local iso_path
  advance_step
  iso_path="$(prepare_iso_for_os "$os_key")"

  local target_disk
  advance_step
  target_disk="$(select_target_disk)"

  advance_step
  flash_iso "$iso_path" "$target_disk"
  advance_step
  cleanup_workdir_prompt
  for label in "${STEP_LABELS[@]}"; do summary_args+=("$label" ok); done
  printf '\n' >&2
  kt_summary rail "${summary_args[@]}"
  printf '\n' >&2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
