#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNTED_PATHS=()

log()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "This command must run as root."
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

map_arches() {
  case "$ARCH" in
    amd64)
      DEB_ARCH=amd64
      RHEL_ARCH=x86_64
      ALPINE_ARCH=x86_64
      QEMU_STATIC=""
      ;;
    arm64)
      DEB_ARCH=arm64
      RHEL_ARCH=aarch64
      ALPINE_ARCH=aarch64
      QEMU_STATIC=/usr/bin/qemu-aarch64-static
      ;;
    *) die "Unsupported architecture: $ARCH" ;;
  esac
  export DEB_ARCH RHEL_ARCH ALPINE_ARCH QEMU_STATIC
}

copy_resolver() {
  mkdir -p "$ROOTFS/etc"
  rm -f "$ROOTFS/etc/resolv.conf"
  cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
}

install_qemu_if_needed() {
  if [[ -n "$QEMU_STATIC" ]]; then
    [[ -x "$QEMU_STATIC" ]] || die "Missing $QEMU_STATIC; install qemu-user-static."
    mkdir -p "$ROOTFS/usr/bin"
    cp "$QEMU_STATIC" "$ROOTFS/usr/bin/"
  fi
}

remove_qemu() {
  rm -f "$ROOTFS/usr/bin/qemu-aarch64-static" "$ROOTFS/usr/bin/qemu-x86_64-static"
}

mount_chroot() {
  mkdir -p "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" "$ROOTFS/run"

  if ! mountpoint -q "$ROOTFS/proc"; then
    mount -t proc proc "$ROOTFS/proc"
    MOUNTED_PATHS+=("$ROOTFS/proc")
  fi
  if ! mountpoint -q "$ROOTFS/sys"; then
    mount --rbind /sys "$ROOTFS/sys"
    mount --make-rslave "$ROOTFS/sys"
    MOUNTED_PATHS+=("$ROOTFS/sys")
  fi
  if ! mountpoint -q "$ROOTFS/dev"; then
    mount --rbind /dev "$ROOTFS/dev"
    mount --make-rslave "$ROOTFS/dev"
    MOUNTED_PATHS+=("$ROOTFS/dev")
  fi
}

unmount_chroot() {
  local i path
  for ((i=${#MOUNTED_PATHS[@]}-1; i>=0; i--)); do
    path=${MOUNTED_PATHS[$i]}
    mountpoint -q "$path" && umount -l "$path" || true
  done
  MOUNTED_PATHS=()
}

in_root() {
  chroot "$ROOTFS" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=xterm \
    LANG=C.UTF-8 \
    "$@"
}

systemctl_root() {
  systemctl --root="$ROOTFS" "$@" >/dev/null 2>&1 || true
}

ensure_rootfs_dirs() {
  mkdir -p \
    "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run" \
    "$ROOTFS/tmp" "$ROOTFS/var/tmp" "$ROOTFS/root" "$ROOTFS/etc"
  chmod 1777 "$ROOTFS/tmp" "$ROOTFS/var/tmp"
}

safe_empty_dir() {
  local dir=$1
  [[ "$dir" == "$ROOTFS"/* ]] || die "Refusing to clean path outside rootfs: $dir"
  mkdir -p "$dir"
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

cleanup_on_exit() {
  unmount_chroot
}
