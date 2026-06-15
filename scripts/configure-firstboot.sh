#!/usr/bin/env bash
set -Eeuo pipefail
: "${ROOTFS:?}" "${DISTRO:?}"

mkdir -p "$ROOTFS/usr/local/sbin" "$ROOTFS/var/lib/pve-template"
cat > "$ROOTFS/usr/local/sbin/pve-firstboot" <<'SCRIPT'
#!/bin/sh
set -eu

marker=/var/lib/pve-template/initialized
[ -e "$marker" ] && exit 0
mkdir -p /var/lib/pve-template

if [ ! -s /etc/machine-id ]; then
  if command -v systemd-machine-id-setup >/dev/null 2>&1; then
    rm -f /etc/machine-id
    : > /etc/machine-id
    systemd-machine-id-setup >/dev/null 2>&1 || true
  elif command -v dbus-uuidgen >/dev/null 2>&1; then
    dbus-uuidgen --ensure=/etc/machine-id
  else
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' > /etc/machine-id
  fi
fi

mkdir -p /var/lib/dbus
ln -sf /etc/machine-id /var/lib/dbus/machine-id

if command -v ssh-keygen >/dev/null 2>&1; then
  ssh-keygen -A
  chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
  chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
fi

chmod 700 /root 2>/dev/null || true
touch "$marker"
SCRIPT
chmod 755 "$ROOTFS/usr/local/sbin/pve-firstboot"

if [[ "$DISTRO" == alpine ]]; then
  mkdir -p "$ROOTFS/etc/init.d"
  cat > "$ROOTFS/etc/init.d/pve-firstboot" <<'EOF'
#!/sbin/openrc-run
name="PVE template first boot initialization"
command="/usr/local/sbin/pve-firstboot"
command_background="no"

depend() {
  need localmount
  after pve-static-only
  before sshd
}
EOF
  chmod 755 "$ROOTFS/etc/init.d/pve-firstboot"
else
  mkdir -p "$ROOTFS/etc/systemd/system"
  cat > "$ROOTFS/etc/systemd/system/pve-firstboot.service" <<'EOF'
[Unit]
Description=Initialize cloned PVE LXC container identity
After=local-fs.target pve-static-only.service
Before=ssh.service sshd.service
ConditionPathExists=!/var/lib/pve-template/initialized

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pve-firstboot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
fi
