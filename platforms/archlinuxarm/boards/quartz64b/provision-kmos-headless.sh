#!/usr/bin/env bash
# Provision the userspace of a Quartz64 Arch Linux ARM install with KMOS headless settings.
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")
REPOSITORY_DIR=""
PRIMARY_USER=""
HOSTNAME_VALUE=""
WIFI_ADAPTER=""
AVAILABLE_PACKAGES=()
SKIPPED_PACKAGES=()

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

Run from a matching local kmos tree copied to an already booted Quartz64.
Installs the headless package set and terminal configuration from that exact
copy. No Git clone, remote main checkout, or board bootloader changes.
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
  [[ -r "$repository_dir/platforms/archlinux/packages/metapackages/nodesktop/PKGBUILD" ]] || die 'Falta el manifiesto headless. Copie el repositorio KMOS completo al Quartz64 antes de ejecutar el script.'
  [[ -r "$repository_dir/platforms/archlinux/assets/starship-presets/tty-term.toml" ]] || die 'Faltan los presets de KMOS. Copie el repositorio completo.'
  [[ -r "$repository_dir/platforms/archlinuxarm/boards/quartz64b/provision-kmos-headless.sh" ]] || die 'Falta el provisionador Quartz64 en la copia local.'
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
  pacman -S --needed --noconfirm iwd nano openssh sudo
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
  [[ -e "/usr/share/zoneinfo/$timezone" ]] || die "Timezone inexistente: $timezone"
  read -r -p 'Locale [en_US.UTF-8]: ' locale
  locale=${locale:-en_US.UTF-8}
  read -r -p 'Keymap de consola [us]: ' keymap
  keymap=${keymap:-us}
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
  local ssid password hidden
  ask_yes_no 'Configurar Wi-Fi persistente ahora?' no || return
  WIFI_ADAPTER=$(detect_wifi_adapter || true)
  [[ -n "$WIFI_ADAPTER" ]] || { warn 'No se detecto adaptador Wi-Fi. Se conserva Ethernet.'; return; }
  info "Adaptador Wi-Fi detectado: $WIFI_ADAPTER"
  rfkill unblock wlan || true
  install -Dm0644 /dev/stdin /etc/iwd/main.conf <<'EOF'
[General]
EnableNetworkConfiguration=false
EOF
  systemctl enable --now iwd.service
  iwctl station "$WIFI_ADAPTER" scan || warn 'No se pudo escanear; aun puede ingresar SSID manualmente.'
  sleep 2
  printf '\nRedes detectadas:\n'
  iwctl station "$WIFI_ADAPTER" get-networks || true
  read -r -p 'SSID (escribalo exactamente, incluso si aparece arriba): ' ssid
  [[ -n "$ssid" ]] || die 'SSID no puede estar vacio.'
  if ask_yes_no 'Es una red oculta?' no; then hidden=1; else hidden=0; fi
  password=$(prompt_secret 'Contrasena Wi-Fi')
  if [[ "$hidden" == 1 ]]; then
    iwctl --passphrase "$password" station "$WIFI_ADAPTER" connect-hidden "$ssid"
  else
    iwctl --passphrase "$password" station "$WIFI_ADAPTER" connect "$ssid"
  fi
  unset password
  networkctl reload
  networkctl reconfigure "$WIFI_ADAPTER" || true
  systemctl enable iwd.service
  info 'Wi-Fi conectado. iwd conserva el perfil y systemd-networkd solicitara DHCP en cada reboot.'
}

configure_swap() {
  local size
  read -r -p 'Swapfile [4G, 0 para omitir]: ' size
  size=${size:-4G}
  [[ "$size" == 0 ]] && return
  [[ "$size" =~ ^[1-9][0-9]*[MG]$ ]] || die 'Swap invalido. Use 0, 512M o 4G.'
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
  REPOSITORY_DIR=$(find_local_repository)
  require_root_and_arm "$@"
  info "Usando la copia local de KMOS: $REPOSITORY_DIR"
  info 'Se actualizara Arch Linux ARM y se instalaran herramientas base antes de configurar usuarios y servicios.'
  ask_yes_no 'Continuar con el aprovisionamiento?' no || die 'Cancelado sin modificar el sistema.'
  initialize_pacman
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
  info 'Provisionamiento KMOS headless completado. Reinicie cuando le convenga.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
