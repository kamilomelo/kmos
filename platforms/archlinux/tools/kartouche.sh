# kartouche — copy this file into your project; https://github.com/kamilomelo/kartouche
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kamilo Melo
# KARTOUCHE_TEMPLATE_VERSION: 6
# Vendored from kartouche 40cea4fe3cb120c0a084668c10c5cc6f0df0633b.
# Pinned source for embedding in standalone KMOS scripts; see kartouche.LICENSE.

# kartouche:config begin
KT_NAME='kmos USB Flasher'
KT_VERSION=
KT_DESCRIPTION='Bootable USB creator for Arch Linux and Rocky Linux.'
KT_ACCENT='38;5;244'
KT_APPEND_ONLY=true
KT_GLYPHS=auto
KT_PAUSE_SECONDS=1
# kartouche:config end

# kartouche:code begin v6
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

_kt_pause() {
    if [[ -t 2 && $KT_PAUSE_SECONDS != 0 ]]; then sleep "$KT_PAUSE_SECONDS" || :; fi
    return 0
}
_kt_after_block() { _kt_pause; printf '\n' >&2 || :; return 0; }
_kt_print_block() {
    [[ -n $1 ]] || return 0
    printf '\n%s\n' "$1" >&2 || :
    _kt_after_block
}
kt_banner() {
    local text; text=$(kt_render_banner 2 "$KT_NAME" "$KT_VERSION" "$KT_DESCRIPTION" "${1:-}") || :
    _kt_print_block "$text"
}
kt_card() {
    local text; text=$(kt_render_card 2 "$KT_NAME" "$KT_VERSION" "$KT_DESCRIPTION") || :
    _kt_print_block "$text"
}
kt_summary() {
    local style=${1:-} text; (( $# )) && shift || :
    text=$(kt_render_summary 2 "$style" "$KT_NAME" "$KT_VERSION" "$@") || :
    _kt_print_block "$text"
}
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
    printf '\n' >&2 || :
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
    _kt_after_block
    return 0
}
kt_steps_fail() {
    [[ ${_kt_finished:-true} == true ]] && return 0
    _kt_finished=true
    local text=failed reason=${1:-}
    if (( _kt_total )); then text="failed at $_kt_n/$_kt_total $(_kt_text "${_kt_labels[_kt_n-1]}")"; fi
    [[ -n $reason ]] && text+=" · $(_kt_text "$reason")"
    _kt_show "$(kt_render_end 2 0 "$text")"
    _kt_after_block
    return 0
}
# kartouche:code end
