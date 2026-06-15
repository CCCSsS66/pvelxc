#!/usr/bin/env bash
set -Eeuo pipefail
: "${ROOTFS:?}" "${DISTRO:?}" "${MIRROR:?}"

fail() { echo "VALIDATION ERROR: $*" >&2; exit 1; }

[[ -s "$ROOTFS/etc/os-release" ]] || fail "Missing /etc/os-release"
[[ -x "$ROOTFS/usr/local/sbin/pve-static-only" ]] || fail "Missing static-only guard"
[[ -x "$ROOTFS/usr/local/sbin/pve-firstboot" ]] || fail "Missing first-boot initializer"
[[ -f "$ROOTFS/etc/ssh/sshd_config.d/10-pve-template.conf" ]] || fail "Missing SSH policy"
[[ ! -s "$ROOTFS/etc/machine-id" ]] || fail "machine-id was not cleared"

if find "$ROOTFS/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' | grep -q .; then
  fail "Template contains reusable SSH host keys"
fi

if find "$ROOTFS/dev" -xdev \( -type b -o -type c \) | grep -q .; then
  fail "Template contains device nodes"
fi

network_paths=(
  "$ROOTFS/etc/network"
  "$ROOTFS/etc/netplan"
  "$ROOTFS/etc/systemd/network"
  "$ROOTFS/etc/NetworkManager/system-connections"
  "$ROOTFS/etc/sysconfig/network-scripts"
)

for path in "${network_paths[@]}"; do
  [[ -e "$path" ]] || continue
  if grep -RIE \
    'iface[[:space:]].*[[:space:]](dhcp|auto)$|DHCP=(yes|true|ipv4|ipv6)|dhcp[46]:[[:space:]]*true|BOOTPROTO=.?dhcp|IPV6_AUTOCONF=.?yes|method=(auto|dhcp)' \
    "$path" 2>/dev/null; then
    fail "Dynamic network configuration remains under $path"
  fi
done

case "$MIRROR" in
  ustc) expected='mirrors.ustc.edu.cn' ;;
  tuna) expected='mirrors.tuna.tsinghua.edu.cn' ;;
  aliyun) expected='mirrors.aliyun.com' ;;
esac

case "$DISTRO" in
  debian|ubuntu)
    grep -Fq "$expected" "$ROOTFS/etc/apt/sources.list" || fail "APT mirror was not applied"
    ;;
  almalinux|rockylinux|centos-stream)
    grep -RFq "$expected" "$ROOTFS/etc/yum.repos.d" || fail "DNF mirror was not applied"
    ;;
  alpine)
    grep -Fq "$expected" "$ROOTFS/etc/apk/repositories" || fail "APK mirror was not applied"
    ;;
esac

echo "Validation passed for $DISTRO"
