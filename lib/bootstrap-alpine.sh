#!/usr/bin/env bash

latest_alpine_minirootfs() {
  local base="https://dl-cdn.alpinelinux.org/alpine/v${VERSION}/releases/${ALPINE_ARCH}"
  local escaped_version filename
  escaped_version=${VERSION//./\\.}
  filename=$(curl -fsSL "$base/" \
    | grep -oE "alpine-minirootfs-${escaped_version}\.[0-9]+-${ALPINE_ARCH}\.tar\.gz" \
    | sort -V \
    | tail -n1)
  [[ -n "$filename" ]] || die "Could not discover Alpine $VERSION minirootfs for $ALPINE_ARCH"
  printf '%s/%s\n' "$base" "$filename"
}

bootstrap_alpine_base() {
  local url archive checksum
  url=$(latest_alpine_minirootfs)
  archive="$WORK_DIR/$(basename "$url")"
  checksum="$archive.sha256"

  log "Downloading $(basename "$url")"
  curl -fL --retry 3 -o "$archive" "$url"
  curl -fL --retry 3 -o "$checksum" "$url.sha256"
  (cd "$WORK_DIR" && sha256sum -c "$(basename "$checksum")")

  tar -xzf "$archive" -C "$ROOTFS"
  ensure_rootfs_dirs
  install_qemu_if_needed
  copy_resolver
  mount_chroot
}

apk_install_strict() {
  in_root apk add --no-cache "$@"
}

apk_install_resilient() {
  local packages=("$@") pkg
  ((${#packages[@]})) || return 0

  if in_root apk add --no-cache "${packages[@]}"; then
    return 0
  fi

  warn "An APK package batch failed; retrying packages individually."
  for pkg in "${packages[@]}"; do
    in_root apk add --no-cache "$pkg" || warn "Optional package unavailable: $pkg"
  done
}

install_alpine_packages() {
  local minimal standard full
  mapfile -t minimal < <(packages_alpine_minimal)
  mapfile -t standard < <(packages_alpine_standard)
  mapfile -t full < <(packages_alpine_full)

  in_root apk update
  apk_install_strict "${minimal[@]}"

  case "$PROFILE" in
    minimal) ;;
    standard) apk_install_resilient "${standard[@]}" ;;
    full)
      apk_install_resilient "${standard[@]}"
      apk_install_resilient "${full[@]}"
      if ! in_root apk add --no-cache php84 php84-cli php84-phar; then
        in_root apk add --no-cache php83 php83-cli php83-phar || warn "No supported PHP package set was available."
      fi
      ;;
  esac

  in_root apk del dhcpcd || true
  in_root rc-update add sshd default || true
  in_root rc-update add pve-static-only boot || true
  in_root rc-update add pve-firstboot boot || true
}
