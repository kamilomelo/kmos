#!/usr/bin/env bash
# Shared package choices for ISO KDE and live headless -> KDE upgrades.
KDE_PERSONAL_GROUP=kmos-kamilo-productivity
OPTIONAL_KDE_METAPACKAGES=("$KDE_PERSONAL_GROUP")
OPTIONAL_KDE_AUR_PACKAGES=(
  brother-ql1100nwb kchat-appimage kdrive-bin onlyoffice-bin
  paisa-bin rtl8821au-dkms-git
)
SELECTED_KDE_METAPACKAGES=()
EXTRA_KDE_PACKAGES=()
SELECTED_KDE_AUR_PACKAGES=()

read_selector_line() { read -r "$1" </dev/tty; }

validate_kde_selection() {
  local name
  for name in "${SELECTED_KDE_METAPACKAGES[@]}"; do
    [[ "$name" == "$KDE_PERSONAL_GROUP" ]] || {
      printf 'Unknown optional group: %s\n' "$name" >&2; return 1;
    }
  done
  for name in "${EXTRA_KDE_PACKAGES[@]}"; do
    [[ "$name" =~ ^[a-zA-Z0-9@._+-]+$ && "$name" != kmos-* ]] || {
      printf 'Invalid repository package: %s\n' "$name" >&2; return 1;
    }
  done
}

validate_kde_aur_selection() {
  local name entry allowed
  for name in "${SELECTED_KDE_AUR_PACKAGES[@]}"; do
    allowed=no
    for entry in "${OPTIONAL_KDE_AUR_PACKAGES[@]}"; do
      [[ "$name" == "$entry" ]] && allowed=yes
    done
    [[ "$allowed" == yes ]] || { printf 'Unknown AUR choice: %s\n' "$name" >&2; return 1; }
  done
}

select_live_packages() {
  local selection=
  SELECTED_KDE_METAPACKAGES=() EXTRA_KDE_PACKAGES=()
  printf 'Kamilo productivity? [Y/n]: ' >&2
  read_selector_line selection || return 1
  case "$selection" in
    ''|[Yy]|[Yy][Ee][Ss]) SELECTED_KDE_METAPACKAGES=("$KDE_PERSONAL_GROUP") ;;
    [Nn]|[Nn][Oo]) ;;
    *) printf 'Answer yes or no; selection cancelled.\n' >&2; return 1 ;;
  esac
  printf 'Extra repo packages (names, Enter for none): ' >&2
  read_selector_line selection || return 1
  read -r -a EXTRA_KDE_PACKAGES <<< "$selection"
  validate_kde_selection
}

select_kde_aur() {
  local selection=
  local -a names=()
  SELECTED_KDE_AUR_PACKAGES=()
  printf 'Install AUR? [Y/n]: ' >&2
  read_selector_line selection || return 1
  case "$selection" in
    ''|[Yy]|[Yy][Ee][Ss]) INSTALL_KDE_AUR=yes ;;
    [Nn]|[Nn][Oo]) INSTALL_KDE_AUR=no; return 0 ;;
    *) printf 'Answer yes or no; selection cancelled.\n' >&2; return 1 ;;
  esac
  printf 'AUR helper [paru/yay; default paru]: ' >&2
  read_selector_line selection || return 1
  case "$selection" in
    ''|1|paru) AUR_HELPER=paru ;;
    2|yay) AUR_HELPER=yay ;;
    *) printf 'Unknown AUR helper; selection cancelled.\n' >&2; return 1 ;;
  esac
  if command -v fzf >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
    selection=$(printf '%s\n' "${OPTIONAL_KDE_AUR_PACKAGES[@]}" | fzf --multi --prompt='Optional AUR > ' --header='TAB selects, ENTER confirms; ESC cancels') || return 1
    [[ -n "$selection" ]] && mapfile -t names <<< "$selection"
  else
    printf 'Optional AUR: %s\n' "${OPTIONAL_KDE_AUR_PACKAGES[*]}" >&2
    printf 'AUR extras (names, Enter for none): ' >&2
    read_selector_line selection || return 1
    read -r -a names <<< "$selection"
  fi
  SELECTED_KDE_AUR_PACKAGES=("${names[@]}")
  validate_kde_aur_selection
}
