#!/usr/bin/env bash
# Shared optional KDE selection for live upgrades and ISO planning.
OPTIONAL_KDE_METAPACKAGES=(
  kmos-browsers kmos-docs kmos-fonts kmos-graphics kmos-kde-multimedia
  kmos-maintenance kmos-network kmos-privacy
)
SELECTED_KDE_METAPACKAGES=()
EXTRA_KDE_PACKAGES=()

read_selector_line() { read -r "$1" </dev/tty; }

validate_kde_selection() {
  local name allowed entry
  for name in "${SELECTED_KDE_METAPACKAGES[@]}"; do
    allowed=no
    for entry in "${OPTIONAL_KDE_METAPACKAGES[@]}"; do
      [[ "$name" == "$entry" ]] && allowed=yes
    done
    [[ "$allowed" == yes ]] || { printf 'Unknown optional group: %s\n' "$name" >&2; return 1; }
  done
  for name in "${EXTRA_KDE_PACKAGES[@]}"; do
    [[ "$name" =~ ^[a-zA-Z0-9@._+-]+$ && "$name" != kmos-* ]] || {
      printf 'Invalid repository package: %s\n' "$name" >&2; return 1;
    }
  done
}

select_live_packages() {
  local selection= entry
  local -a choices=() indices=()
  SELECTED_KDE_METAPACKAGES=() EXTRA_KDE_PACKAGES=()
  printf 'Required KDE foundation: kmos-kde-noapps (includes KDE base).\n' >&2
  if command -v fzf >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
    selection=$(printf '%s\n' "${OPTIONAL_KDE_METAPACKAGES[@]}" | fzf --multi --prompt='Optional KDE groups > ' --header='TAB selects, ENTER confirms; ESC cancels') || return 1
    [[ -n "$selection" ]] && mapfile -t choices <<< "$selection"
  else
    printf 'Optional groups (enter numbers separated by spaces, or ENTER for none):\n' >&2
    for entry in "${!OPTIONAL_KDE_METAPACKAGES[@]}"; do
      printf '  %s) %s\n' "$((entry + 1))" "${OPTIONAL_KDE_METAPACKAGES[entry]}" >&2
    done
    read_selector_line selection || return 1
    read -r -a indices <<< "$selection"
    for entry in "${indices[@]}"; do
      [[ "$entry" =~ ^[1-8]$ ]] || { printf 'Invalid group number: %s\n' "$entry" >&2; return 1; }
      choices+=("${OPTIONAL_KDE_METAPACKAGES[entry - 1]}")
    done
  fi
  SELECTED_KDE_METAPACKAGES=("${choices[@]}")
  printf 'Extra official-repository package names (space-separated; ENTER for none): ' >&2
  read_selector_line selection || return 1
  read -r -a EXTRA_KDE_PACKAGES <<< "$selection"
  validate_kde_selection
}
