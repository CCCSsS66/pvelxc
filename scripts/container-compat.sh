#!/usr/bin/env bash
set -Eeuo pipefail
: "${ROOTFS:?}" "${DISTRO:?}"

mkdir -p "$ROOTFS/etc" "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run"

cat > "$ROOTFS/etc/fstab" <<'EOF'
# Filesystems are supplied by the Proxmox LXC host.
EOF

rm -rf "$ROOTFS/boot"/* "$ROOTFS/lib/modules"/* "$ROOTFS/usr/lib/modules"/* 2>/dev/null || true
rm -f "$ROOTFS/etc/udev/rules.d/70-persistent-net.rules"
rm -f "$ROOTFS/etc/hostname"
printf 'localhost\n' > "$ROOTFS/etc/hostname"
ln -snf /proc/mounts "$ROOTFS/etc/mtab"

# Device nodes are created by LXC. Never ship host-side device nodes in a template.
find "$ROOTFS/dev" -xdev \( -type b -o -type c -o -type p -o -type s \) -delete 2>/dev/null || true

if [[ "$DISTRO" != alpine ]]; then
  systemctl --root="$ROOTFS" mask \
    systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket \
    systemd-modules-load.service systemd-hwdb-update.service kmod-static-nodes.service \
    getty@tty1.service >/dev/null 2>&1 || true

  systemctl --root="$ROOTFS" disable \
    systemd-udev-trigger.service systemd-networkd-wait-online.service \
    NetworkManager-wait-online.service >/dev/null 2>&1 || true

  if [[ "$DISTRO" == debian || "$DISTRO" == ubuntu ]]; then
    systemctl --root="$ROOTFS" mask systemd-networkd.service systemd-networkd.socket >/dev/null 2>&1 || true
  fi
fi
