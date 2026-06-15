#!/usr/bin/env bash

bootstrap_deb_base() {
  local bootstrap_mirror script

  if [[ "$DISTRO" == debian ]]; then
    bootstrap_mirror="https://deb.debian.org/debian"
    script="/usr/share/debootstrap/scripts/$CODENAME"
    [[ -e "$script" ]] || script="/usr/share/debootstrap/scripts/sid"
  else
    if [[ "$ARCH" == amd64 ]]; then
      bootstrap_mirror="https://archive.ubuntu.com/ubuntu"
    else
      bootstrap_mirror="https://ports.ubuntu.com/ubuntu-ports"
    fi
    script="/usr/share/debootstrap/scripts/$CODENAME"
    [[ -e "$script" ]] || script="/usr/share/debootstrap/scripts/gutsy"
  fi

  log "Bootstrapping $DISTRO $VERSION ($DEB_ARCH)"
  if [[ "$ARCH" == arm64 ]]; then
    debootstrap --foreign --variant=minbase --arch="$DEB_ARCH" --components=main \
      "$CODENAME" "$ROOTFS" "$bootstrap_mirror" "$script"
    install_qemu_if_needed
    copy_resolver
    mount_chroot
    in_root /debootstrap/debootstrap --second-stage
  else
    debootstrap --variant=minbase --arch="$DEB_ARCH" --components=main \
      "$CODENAME" "$ROOTFS" "$bootstrap_mirror" "$script"
    copy_resolver
    mount_chroot
  fi

  ensure_rootfs_dirs
}

apt_install_strict() {
  local packages=("$@")
  in_root apt-get install -y --no-install-recommends "${packages[@]}"
}

apt_install_resilient() {
  local packages=("$@") pkg
  ((${#packages[@]})) || return 0

  if in_root apt-get install -y --no-install-recommends "${packages[@]}"; then
    return 0
  fi

  warn "A package batch failed; retrying packages individually."
  in_root apt-get -f install -y || true
  for pkg in "${packages[@]}"; do
    in_root apt-get install -y --no-install-recommends "$pkg" \
      || warn "Optional package unavailable: $pkg"
  done
}

install_deb_packages() {
  local minimal standard full
  mapfile -t minimal < <(packages_deb_minimal)
  mapfile -t standard < <(packages_deb_standard)
  mapfile -t full < <(packages_deb_full)

  log "Refreshing APT metadata from selected mirror"
  in_root apt-get update
  apt_install_strict "${minimal[@]}"

  case "$PROFILE" in
    minimal) ;;
    standard) apt_install_resilient "${standard[@]}" ;;
    full)
      apt_install_resilient "${standard[@]}"
      apt_install_resilient "${full[@]}"
      ;;
  esac

  in_root apt-get purge -y isc-dhcp-client isc-dhcp-common dhcpcd5 dhcpcd-base || true
  in_root locale-gen en_US.UTF-8 || true
  systemctl_root enable ssh.service networking.service pve-static-only.service pve-firstboot.service
}
