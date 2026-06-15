#!/usr/bin/env bash
set -Eeuo pipefail
: "${ROOTFS:?}" "${FAMILY:?}"

rm -rf \
  "$ROOTFS/var/cache/apt"/* \
  "$ROOTFS/var/lib/apt/lists"/* \
  "$ROOTFS/var/cache/dnf"/* \
  "$ROOTFS/var/cache/yum"/* \
  "$ROOTFS/var/cache/apk"/* \
  "$ROOTFS/tmp"/* \
  "$ROOTFS/var/tmp"/* \
  "$ROOTFS/var/log"/* \
  "$ROOTFS/root/.cache" \
  "$ROOTFS/root/.npm" \
  "$ROOTFS/root/.cargo/registry" \
  "$ROOTFS/root/.cargo/git" 2>/dev/null || true

find "$ROOTFS/home" -type f \( -name '.bash_history' -o -name '.zsh_history' \) -delete 2>/dev/null || true
rm -f "$ROOTFS/root/.bash_history" "$ROOTFS/root/.zsh_history"
rm -f "$ROOTFS/var/lib/systemd/random-seed"
rm -f "$ROOTFS/var/lib/pve-template/initialized"
rm -f "$ROOTFS/etc/ssh/ssh_host_"*
rm -f "$ROOTFS/var/lib/dhcp/"* "$ROOTFS/var/lib/NetworkManager/"*.lease 2>/dev/null || true

mkdir -p "$ROOTFS/var/log" "$ROOTFS/tmp" "$ROOTFS/var/tmp" "$ROOTFS/var/lib/pve-template"
chmod 1777 "$ROOTFS/tmp" "$ROOTFS/var/tmp"

: > "$ROOTFS/etc/machine-id"
mkdir -p "$ROOTFS/var/lib/dbus"
ln -snf /etc/machine-id "$ROOTFS/var/lib/dbus/machine-id"

cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
# Proxmox may replace this file with the DNS settings selected for the container.
nameserver 223.5.5.5
nameserver 119.29.29.29
EOF

rm -f "$ROOTFS/usr/bin/qemu-aarch64-static" "$ROOTFS/usr/bin/qemu-x86_64-static"
