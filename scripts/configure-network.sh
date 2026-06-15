#!/usr/bin/env bash
set -Eeuo pipefail
: "${ROOTFS:?}" "${DISTRO:?}"

mkdir -p "$ROOTFS/usr/local/sbin" "$ROOTFS/etc/sysctl.d"

cat > "$ROOTFS/usr/local/sbin/pve-static-only" <<'SCRIPT'
#!/bin/sh
set -eu

rewrite_interfaces() {
  file=$1
  [ -f "$file" ] || return 0
  tmp="${file}.pve-static.$$"
  awk '
    /^[[:space:]]*iface[[:space:]]+/ {
      if ($3 == "inet" && $4 == "dhcp") $4 = "manual"
      if ($3 == "inet6" && ($4 == "dhcp" || $4 == "auto")) $4 = "manual"
      print
      next
    }
    /^[[:space:]]*(accept_ra|autoconf)[[:space:]]+/ { next }
    { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

rewrite_nm_keyfile() {
  file=$1
  [ -f "$file" ] || return 0
  tmp="${file}.pve-static.$$"
  awk '
    /^\[/ { section=$0 }
    section == "[ipv4]" && /^method=(auto|shared)$/ { print "method=disabled"; next }
    section == "[ipv6]" && /^method=(auto|dhcp|shared)$/ { print "method=disabled"; next }
    { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  chmod 600 "$file" 2>/dev/null || true
  rm -f "$tmp"
}

rewrite_interfaces /etc/network/interfaces
for f in /etc/network/interfaces.d/*; do
  [ -f "$f" ] && rewrite_interfaces "$f"
done

for f in /etc/systemd/network/*.network; do
  [ -f "$f" ] || continue
  sed -i -E \
    -e 's/^[[:space:]]*DHCP=.*/DHCP=no/' \
    -e 's/^[[:space:]]*IPv6AcceptRA=.*/IPv6AcceptRA=no/' \
    "$f"
done

for f in /etc/netplan/*.yaml /etc/netplan/*.yml; do
  [ -f "$f" ] || continue
  sed -i -E \
    -e 's/(dhcp4:)[[:space:]]*true/\1 false/g' \
    -e 's/(dhcp6:)[[:space:]]*true/\1 false/g' \
    -e 's/(accept-ra:)[[:space:]]*true/\1 false/g' \
    "$f"
done

for f in /etc/NetworkManager/system-connections/*; do
  [ -f "$f" ] && rewrite_nm_keyfile "$f"
done

for f in /etc/sysconfig/network-scripts/ifcfg-*; do
  [ -f "$f" ] || continue
  sed -i -E \
    -e 's/^BOOTPROTO=.*/BOOTPROTO=none/' \
    -e 's/^IPV6_AUTOCONF=.*/IPV6_AUTOCONF=no/' \
    -e 's/^DHCPV6C=.*/DHCPV6C=no/' \
    "$f"
done

rm -f /var/lib/dhcp/* /var/lib/NetworkManager/*.lease /var/lib/dhcpcd/* 2>/dev/null || true

if command -v sysctl >/dev/null 2>&1; then
  sysctl -q -w net.ipv6.conf.all.accept_ra=0 || true
  sysctl -q -w net.ipv6.conf.default.accept_ra=0 || true
  sysctl -q -w net.ipv6.conf.all.autoconf=0 || true
  sysctl -q -w net.ipv6.conf.default.autoconf=0 || true
fi
SCRIPT
chmod 755 "$ROOTFS/usr/local/sbin/pve-static-only"

cat > "$ROOTFS/etc/sysctl.d/90-pve-static-only.conf" <<'EOF'
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.default.autoconf = 0
EOF

if [[ "$DISTRO" == alpine ]]; then
  mkdir -p "$ROOTFS/etc/init.d"
  cat > "$ROOTFS/etc/init.d/pve-static-only" <<'EOF'
#!/sbin/openrc-run
name="PVE static-only network guard"
command="/usr/local/sbin/pve-static-only"
command_background="no"

depend() {
  need localmount
  before networking
}
EOF
  chmod 755 "$ROOTFS/etc/init.d/pve-static-only"
else
  mkdir -p "$ROOTFS/etc/systemd/system"
  cat > "$ROOTFS/etc/systemd/system/pve-static-only.service" <<'EOF'
[Unit]
Description=Disable DHCP, DHCPv6 and IPv6 SLAAC in PVE containers
DefaultDependencies=no
After=local-fs.target
Before=network-pre.target NetworkManager.service networking.service systemd-networkd.service
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pve-static-only
RemainAfterExit=yes

[Install]
WantedBy=network-pre.target
EOF
fi

if [[ "$DISTRO" == debian || "$DISTRO" == ubuntu || "$DISTRO" == alpine ]]; then
  mkdir -p "$ROOTFS/etc/network"
  cat > "$ROOTFS/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback
EOF
fi
