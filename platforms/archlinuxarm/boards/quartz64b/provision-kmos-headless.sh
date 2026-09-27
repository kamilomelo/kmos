#!/usr/bin/env bash
# Provision the userspace of a Quartz64 Arch Linux ARM install with KMOS headless settings.
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail
IFS=$'\n\t'

readonly KMOS_REPOSITORY='https://github.com/kamilomelo/kmos.git'
SCRIPT_DIR=$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")
REPOSITORY_DIR=""
PRIMARY_USER=""
HOSTNAME_VALUE=""
WIFI_ADAPTER=""
AVAILABLE_PACKAGES=()
SKIPPED_PACKAGES=()
KDE_PACKAGES=()
KDE_METAPACKAGES=()

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

info() {
  printf '==> %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage: ./provision-kmos-headless.sh

Requires a working network connection on an already booted Quartz64. Clones
KMOS from GitHub, records one commit, and uses that checkout for every package
manifest, asset and helper. Does not modify the board's bootloader.
EOF
}

ask_yes_no() {
  local prompt=$1 default=${2:-no} answer
  while true; do
    if [[ "$default" == yes ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer=${answer:-Y}
    else
      read -r -p "$prompt [y/N]: " answer
      answer=${answer:-N}
    fi
    case "$answer" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) warn 'Responda y o n.' ;;
    esac
  done
}

prompt_secret() {
  local prompt=$1 first second
  while true; do
    read -r -s -p "$prompt: " first
    printf '\n' >&2
    [[ -n "$first" ]] || { warn 'La contrasena no puede estar vacia.'; continue; }
    read -r -s -p "Confirme $prompt: " second
    printf '\n' >&2
    [[ "$first" == "$second" ]] || { warn 'Las contrasenas no coinciden.'; continue; }
    printf '%s\n' "$first"
    unset first second
    return
  done
}

require_root_and_arm() {
  [[ $(uname -m) == aarch64 ]] || die "Este script es para aarch64; arquitectura actual: $(uname -m)"
  ((EUID == 0)) && return
  command -v sudo >/dev/null 2>&1 || die 'Se requiere acceso root, pero sudo no esta instalado.'
  info 'Se requiere acceso root; sudo solicitara su contrasena.'
  exec sudo -- "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
}

parse_arguments() {
  while (($#)); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) die "Opcion desconocida: $1" ;;
    esac
  done
}

find_local_repository() {
  local repository_dir=""
  repository_dir=$(cd -- "$SCRIPT_DIR/../../../.." && pwd -P) || die 'No se pudo localizar la copia local de KMOS.'
  validate_repository "$repository_dir"
  printf '%s\n' "$repository_dir"
}

validate_repository() {
  local repository_dir=$1
  [[ -r "$repository_dir/platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD" ]] || die 'Falta el manifiesto headless. Copie el repositorio KMOS completo al Quartz64 antes de ejecutar el script.'
  [[ -r "$repository_dir/platforms/archlinux/assets/starship-presets/tty-term.toml" ]] || die 'Faltan los presets de KMOS. Copie el repositorio completo.'
  [[ -r "$repository_dir/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh" ]] || die 'Falta el provisionador Quartz64 en la copia local.'
  [[ -x "$repository_dir/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh" ]] || die 'Falta el helper Wi-Fi de Quartz64.'
  [[ -r "$repository_dir/platforms/archlinux/packages/metapackages/kde/noapps/PKGBUILD" ]] || die 'Falta el manifiesto KDE de KMOS.'
}

checkout_kmos() {
  local work_dir repository_dir
  work_dir=$(mktemp -d "${TMPDIR:-/var/tmp}/kmos-quartz.XXXXXXXX") || die 'No se pudo crear un directorio de descarga privado.'
  repository_dir="$work_dir/kmos"
  info "Descargando KMOS de GitHub a $repository_dir"
  git clone --depth 1 --branch main "$KMOS_REPOSITORY" "$repository_dir" || die "Fallo la descarga; se conserva $work_dir para inspeccion."
  validate_repository "$repository_dir"
  printf '%s\n' "$repository_dir"
}

configure_pacman() {
  local pacman_conf=/etc/pacman.conf
  sed -i 's/^#Color$/Color/' "$pacman_conf"
  if grep -q '^#ParallelDownloads = ' "$pacman_conf"; then
    sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 6/' "$pacman_conf"
  elif ! grep -q '^ParallelDownloads = ' "$pacman_conf"; then
    printf '\nParallelDownloads = 6\n' >> "$pacman_conf"
  fi
  grep -q '^ILoveCandy$' "$pacman_conf" || sed -i '/^ParallelDownloads = /a ILoveCandy' "$pacman_conf"
}

initialize_pacman() {
  info 'Inicializando keyring y actualizando Arch Linux ARM.'
  pacman-key --init
  pacman-key --populate archlinuxarm
  pacman -Syu --needed --noconfirm
  pacman -S --needed --noconfirm git iwd nano openssh sudo
  configure_pacman
}

load_kmos_packages() {
  local pkgbuild=$1
  [[ -r "$pkgbuild" ]] || die "No existe el metapaquete KMOS: $pkgbuild"
  awk -F"'" '
    /^depends=\(/ { in_depends=1; next }
    in_depends && /^\)/ { exit }
    in_depends && NF >= 3 { print $2 }
  ' "$pkgbuild"
}

handle_unavailable_package() {
  local package=$1 choice
  printf '\n%s no esta disponible en los repositorios aarch64.\n' "$package"
  case "$package" in
    opencode) printf 'Fuente oficial para inspeccionar/compilar: https://github.com/anomalyco/opencode\n' ;;
    *) printf 'No hay una fuente oficial de compilacion declarada automaticamente para este paquete.\n' ;;
  esac
  while true; do
    read -r -p 'Omitir [o], cancelar [c], o mostrar fuente [f]? [o]: ' choice
    choice=${choice:-o}
    case "$choice" in
      [Oo]) warn "Se omitira $package."; return ;;
      [Ff])
        case "$package" in
          opencode) printf 'Fuente oficial: https://github.com/anomalyco/opencode\n' ;;
          *) printf 'No hay fuente declarada para %s.\n' "$package" ;;
        esac
        ;;
      [Cc]) die "Cancelado antes de omitir $package." ;;
      *) warn 'Seleccione o, c o f.' ;;
    esac
  done
}

install_kmos_packages() {
  local repository_dir=$1 package package_lines package_summary=""
  local -a packages=()
  package_lines=$(load_kmos_packages "$repository_dir/platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD") || die 'No se pudo leer el manifiesto headless.'
  [[ -n "$package_lines" ]] || die 'KMOS no definio paquetes headless.'
  mapfile -t packages <<< "$package_lines"
  ((${#packages[@]} > 0)) || die 'KMOS no definio paquetes headless.'
  printf -v package_summary '%s ' "${packages[@]}"
  info "Conjunto KMOS actual: ${package_summary% }"
  for package in "${packages[@]}"; do
    [[ "$package" =~ ^[a-zA-Z0-9@._+:-]+$ ]] || die "Nombre de paquete invalido en KMOS: $package"
    if pacman -Si "$package" >/dev/null 2>&1; then
      AVAILABLE_PACKAGES+=("$package")
    else
      handle_unavailable_package "$package"
      SKIPPED_PACKAGES+=("$package")
    fi
  done
  ((${#AVAILABLE_PACKAGES[@]} == 0)) || pacman -S --needed --noconfirm "${AVAILABLE_PACKAGES[@]}"
  if ((${#SKIPPED_PACKAGES[@]} > 0)); then
    printf -v package_summary '%s ' "${SKIPPED_PACKAGES[@]}"
    warn "Paquetes omitidos por decision del usuario: ${package_summary% }"
  fi
}

kde_metapackage_path() {
  case "$1" in
    kmos-audio) printf 'desktop-shared/audio/PKGBUILD\n' ;;
    kmos-browsers) printf 'desktop-shared/browsers/PKGBUILD\n' ;;
    kmos-devices) printf 'desktop-shared/devices/PKGBUILD\n' ;;
    kmos-docs) printf 'desktop-shared/docs/PKGBUILD\n' ;;
    kmos-filesystems) printf 'desktop-shared/filesystems/PKGBUILD\n' ;;
    kmos-fonts) printf 'desktop-shared/fonts/PKGBUILD\n' ;;
    kmos-graphics) printf 'desktop-shared/graphics/PKGBUILD\n' ;;
    kmos-kde-base) printf 'kde/base/PKGBUILD\n' ;;
    kmos-kde-multimedia) printf 'kde/multimedia/PKGBUILD\n' ;;
    kmos-kde-utils) printf 'kde/utils/PKGBUILD\n' ;;
    kmos-kde-noapps) printf 'kde/noapps/PKGBUILD\n' ;;
    kmos-kde-plasma) printf 'kde/base/plasma/PKGBUILD\n' ;;
    kmos-maintenance) printf 'desktop-shared/maintenance/PKGBUILD\n' ;;
    kmos-network) printf 'desktop-shared/network/PKGBUILD\n' ;;
    kmos-privacy) printf 'desktop-shared/privacy/PKGBUILD\n' ;;
    *) return 1 ;;
  esac
}

resolve_kde_metapackage() {
  local name=$1 relative dependency manifest package_lines seen=0
  local -a dependencies=()
  local previous
  for previous in "${KDE_METAPACKAGES[@]}"; do
    [[ "$previous" != "$name" ]] || return 0
  done
  relative=$(kde_metapackage_path "$name") || die "Metapaquete KDE desconocido: $name"
  manifest="$REPOSITORY_DIR/platforms/archlinux/packages/metapackages/$relative"
  package_lines=$(load_kmos_packages "$manifest") || die "No se pudo leer $manifest"
  if [[ -n "$package_lines" ]]; then mapfile -t dependencies <<< "$package_lines"; fi
  KDE_METAPACKAGES+=("$name")
  for dependency in "${dependencies[@]}"; do
    [[ "$dependency" =~ ^[a-zA-Z0-9@._+:-]+$ ]] || die "Dependencia KDE invalida: $dependency"
    if [[ "$dependency" == kmos-* ]]; then
      resolve_kde_metapackage "$dependency"
    else
      seen=0
      for previous in "${KDE_PACKAGES[@]}"; do
        if [[ "$previous" == "$dependency" ]]; then seen=1; break; fi
      done
      if ((seen == 0)); then KDE_PACKAGES+=("$dependency"); fi
    fi
  done
}

offer_kde_desktop() {
  local profile package summary="" missing_summary="" graphics_device=""
  local -a available=() missing=()
  local -a full=(kmos-audio kmos-browsers kmos-devices kmos-docs kmos-filesystems kmos-fonts kmos-graphics kmos-kde-base kmos-kde-multimedia kmos-kde-utils kmos-maintenance kmos-network kmos-privacy)
  local metapackage
  ask_yes_no 'Instalar un escritorio KDE ahora?' no || return 0
  for graphics_device in /dev/dri/card[0-9]*; do
    [[ -e "$graphics_device" ]] && break
  done
  [[ -e "$graphics_device" ]] || { warn 'No se detecto un dispositivo DRM en /dev/dri; KDE no se instalara hasta verificar graficos en Quartz64.'; return 0; }
  read -r -p 'Perfil KDE [noapps/full] (noapps): ' profile
  profile=${profile:-noapps}
  case "$profile" in
    noapps) resolve_kde_metapackage kmos-kde-noapps ;;
    full)
      for metapackage in "${full[@]}"; do resolve_kde_metapackage "$metapackage"; done
      ;;
    *) die 'Perfil KDE invalido; se conserva el sistema headless.' ;;
  esac
  for package in "${KDE_PACKAGES[@]}"; do
    if pacman -Si "$package" >/dev/null 2>&1; then
      available+=("$package")
    else
      missing+=("$package")
    fi
  done
  for package in plasma-desktop plasma-workspace kwin sddm networkmanager; do
    if ! pacman -Si "$package" >/dev/null 2>&1; then
      warn "Componente KDE esencial no disponible para ARM: $package. No se instalaran paquetes KDE."
      return 0
    fi
  done
  if ((${#missing[@]} > 0)); then
    printf -v missing_summary '%s ' "${missing[@]}"
    warn "Dependencias KDE opcionales no disponibles en ARM: ${missing_summary% }."
    info 'No se compilaran fuentes ni se usaran binarios x86 automaticamente.'
    ask_yes_no 'Omitir esos paquetes y continuar con KDE?' no || { info 'KDE aplazado; el sistema headless sigue funcionando.'; return 0; }
  fi
  ((${#available[@]} > 0)) || die 'No hay paquetes KDE disponibles.'
  printf -v summary '%s ' "${available[@]}"
  info "KDE $profile instalara: ${summary% }"
  ask_yes_no 'Instalar KDE en el Quartz64?' no || return 0
  pacman -S --needed --noconfirm "${available[@]}"
  for package in plasma-desktop plasma-workspace kwin sddm networkmanager; do
    pacman -Q "$package" >/dev/null || die "Falta componente KDE despues de instalar: $package"
  done
  # Keep iwd + networkd in charge of Wi-Fi and Ethernet until NM migration is
  # verified on the physical board; never disable the working network here.
  systemctl enable sddm.service
  systemctl set-default graphical.target
  info 'KDE instalado. La red headless sigue activa; NetworkManager no se iniciara hasta validar la migracion en el board.'
}

configure_kmos_terminal() {
  local repository_dir=$1
  local preset="$repository_dir/platforms/archlinux/assets/starship-presets/tty-term.toml"
  [[ -r "$preset" ]] || die 'No se encontro el preset tty de KMOS.'
  install -Dm0644 "$preset" /usr/share/kmos/starship-presets/tty-term.toml
  install -Dm0644 /dev/stdin /etc/profile.d/10-kmos-starship.sh <<'EOF'
export STARSHIP_CONFIG=/usr/share/kmos/starship-presets/tty-term.toml
EOF
  touch /etc/bash.bashrc
  if ! grep -q '^# kmos headless shell$' /etc/bash.bashrc; then
    cat >> /etc/bash.bashrc <<'EOF'

# kmos headless shell
if [[ $- == *i* ]] && command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
if [[ $- == *i* ]] && command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi
export EDITOR=nano
export VISUAL=nano
EOF
  fi
  install -d -m 0755 /opt/kmos/assets/starship-presets
  cp -a "$repository_dir/platforms/archlinux/assets/starship-presets/." /opt/kmos/assets/starship-presets/
}

configure_identity() {
  local timezone locale keymap
  read -r -p 'Hostname nuevo: ' HOSTNAME_VALUE
  [[ "$HOSTNAME_VALUE" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die 'Hostname invalido.'
  read -r -p 'Timezone [Europe/Zurich]: ' timezone
  timezone=${timezone:-Europe/Zurich}
  [[ "$timezone" =~ ^[a-zA-Z0-9_+/-]+$ && "$timezone" != *..* ]] || die 'Timezone invalida.'
  [[ -e "/usr/share/zoneinfo/$timezone" ]] || die "Timezone inexistente: $timezone"
  read -r -p 'Locale [en_US.UTF-8]: ' locale
  locale=${locale:-en_US.UTF-8}
  [[ "$locale" =~ ^[a-zA-Z_]+\.UTF-8$ ]] || die 'Locale invalida.'
  read -r -p 'Keymap de consola [us]: ' keymap
  keymap=${keymap:-us}
  [[ "$keymap" =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Keymap invalido.'
  ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
  if [[ -e /dev/rtc0 ]]; then
    hwclock --systohc || warn 'No se pudo actualizar el reloj de hardware; se conservara la hora del sistema.'
  fi
  grep -q "^$locale UTF-8" /etc/locale.gen || sed -i "s/^#$locale UTF-8/$locale UTF-8/" /etc/locale.gen
  grep -q "^$locale UTF-8" /etc/locale.gen || printf '%s UTF-8\n' "$locale" >> /etc/locale.gen
  locale-gen
  printf 'LANG=%s\n' "$locale" > /etc/locale.conf
  printf 'KEYMAP=%s\n' "$keymap" > /etc/vconsole.conf
  printf '%s\n' "$HOSTNAME_VALUE" > /etc/hostname
  cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME_VALUE.localdomain $HOSTNAME_VALUE
EOF
}

create_administrator() {
  local username password additional add_password
  while true; do
    read -r -p 'Usuario administrador principal: ' username
    [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] && break
    warn 'Nombre de usuario invalido.'
  done
  password=$(prompt_secret "Contrasena de $username")
  if id "$username" >/dev/null 2>&1; then
    usermod -aG wheel "$username"
  else
    useradd -m -G wheel -s /bin/bash "$username"
  fi
  printf '%s:%s\n' "$username" "$password" | chpasswd
  unset password
  PRIMARY_USER=$username

  while ask_yes_no 'Crear otro usuario?' no; do
    read -r -p 'Usuario adicional: ' additional
    [[ "$additional" =~ ^[a-z_][a-z0-9_-]*$ ]] || { warn 'Nombre de usuario invalido.'; continue; }
    add_password=$(prompt_secret "Contrasena de $additional")
    if id "$additional" >/dev/null 2>&1; then
      usermod -aG users "$additional"
    else
      useradd -m -s /bin/bash "$additional"
    fi
    if ask_yes_no "Dar sudo a $additional?" no; then
      usermod -aG wheel "$additional"
    fi
    printf '%s:%s\n' "$additional" "$add_password" | chpasswd
    unset add_password
  done
  install -Dm0440 /dev/stdin /etc/sudoers.d/00-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
}

configure_ssh() {
  install -Dm0644 /dev/stdin /etc/ssh/sshd_config.d/10-kmos.conf <<'EOF'
PermitRootLogin no
PermitEmptyPasswords no
PasswordAuthentication yes
EOF
  systemctl enable sshd.service
}

configure_networkd() {
  install -d -m 0755 /etc/systemd/network
  cat > /etc/systemd/network/20-ethernet-dhcp.network <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=100
EOF
  cat > /etc/systemd/network/25-wifi-dhcp.network <<'EOF'
[Match]
Name=wl* wlan*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=600
EOF
  ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  systemctl enable systemd-networkd.service systemd-resolved.service
}

detect_wifi_adapter() {
  local interface
  for interface in /sys/class/net/*; do
    [[ -d "$interface/wireless" ]] || continue
    printf '%s\n' "${interface##*/}"
    return
  done
  return 1
}

configure_wifi() {
  ask_yes_no 'Configurar Wi-Fi persistente ahora?' no || return
  WIFI_ADAPTER=$(detect_wifi_adapter || true)
  [[ -n "$WIFI_ADAPTER" ]] || { warn 'No se detecto adaptador Wi-Fi. Se conserva Ethernet.'; return; }
  "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/connect-quartz64b-wifi.sh"
  info 'Wi-Fi configurado; iwd y systemd-networkd conservaran la conexion al reiniciar.'
}

configure_swap() {
  local size
  read -r -p 'Swapfile [4G, 0 para omitir]: ' size
  size=${size:-4G}
  [[ "$size" == 0 ]] && return
  [[ "$size" =~ ^[1-9][0-9]*[MG]$ ]] || die 'Swap invalido. Use 0, 512M o 4G.'
  if [[ -e /swapfile || -L /swapfile ]]; then
    if ! ask_yes_no 'Ya existe /swapfile. Reemplazarlo? Esto destruye su contenido.' no; then
      info 'Swap existente conservado.'
      return 0
    fi
  fi
  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  fallocate -l "$size" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  sed -i '\|^/swapfile |d' /etc/fstab
  printf '/swapfile none swap defaults 0 0\n' >> /etc/fstab
}

remove_alarm() {
  getent passwd alarm >/dev/null || return
  ask_yes_no 'Eliminar el usuario inicial alarm y su home?' yes || return
  id "$PRIMARY_USER" >/dev/null || die 'El usuario administrador no existe; alarm no sera eliminado.'
  userdel -r alarm
}

configure_syncthing() {
  pacman -Q syncthing >/dev/null 2>&1 || { warn 'Syncthing no esta instalado; se omite su servicio.'; return; }
  ask_yes_no "Activar Syncthing para $PRIMARY_USER?" no || return
  systemctl enable --now "syncthing@$PRIMARY_USER.service"
}

verify_installation() {
  local package
  info 'Verificando configuracion.'
  for package in iwd nano openssh sudo "${AVAILABLE_PACKAGES[@]}"; do
    pacman -Q "$package" >/dev/null || die "Falta el paquete esperado: $package"
  done
  id "$PRIMARY_USER" >/dev/null
  id -nG "$PRIMARY_USER" | grep -qw wheel || die "$PRIMARY_USER no pertenece a wheel."
  sudo -l -U "$PRIMARY_USER" >/dev/null
  [[ $(cat /etc/hostname) == "$HOSTNAME_VALUE" ]] || die 'Hostname no coincide.'
  systemctl is-enabled sshd.service systemd-networkd.service systemd-resolved.service >/dev/null
  [[ -f /usr/share/kmos/starship-presets/tty-term.toml ]] || die 'Falta preset de Starship.'
  if [[ -n "$WIFI_ADAPTER" ]]; then
    systemctl is-enabled iwd.service >/dev/null
    iwctl station "$WIFI_ADAPTER" show || warn 'No se pudo consultar el estado Wi-Fi.'
  fi
}

main() {
  parse_arguments "$@"
  require_root_and_arm "$@"
  info 'Se actualizara Arch Linux ARM, se descargara KMOS de GitHub y se configurara el sistema.'
  ask_yes_no 'Continuar con el aprovisionamiento?' no || die 'Cancelado sin modificar el sistema.'
  if [[ -n "${KMOS_PINNED_CHECKOUT:-}" ]]; then
    REPOSITORY_DIR=$KMOS_PINNED_CHECKOUT
    validate_repository "$REPOSITORY_DIR"
  else
    initialize_pacman
    REPOSITORY_DIR=$(checkout_kmos)
    if ! cmp -s -- "${BASH_SOURCE[0]}" "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh"; then
      info 'El script descargado difiere; continuando con el provisionador del mismo commit que sus archivos.'
      export KMOS_PINNED_CHECKOUT=$REPOSITORY_DIR
      exec "$REPOSITORY_DIR/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh" "$@"
    fi
  fi
  info "KMOS commit usado: $(git -C "$REPOSITORY_DIR" rev-parse HEAD)"
  install_kmos_packages "$REPOSITORY_DIR"
  configure_kmos_terminal "$REPOSITORY_DIR"
  configure_identity
  create_administrator
  configure_ssh
  configure_networkd
  configure_wifi
  configure_swap
  configure_syncthing
  remove_alarm
  verify_installation
  info 'Provisionamiento KMOS headless completado.'
  offer_kde_desktop
  info 'Reinicie cuando le convenga y compruebe red y sesion grafica localmente.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
