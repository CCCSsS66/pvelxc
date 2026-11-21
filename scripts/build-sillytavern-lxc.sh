#!/usr/bin/env bash
set -Eeuo pipefail

DEBIAN_SUITE="${DEBIAN_SUITE:-trixie}"
NODE_VERSION="${NODE_VERSION:-v24.22.3}"
ST_VERSION="${ST_VERSION:-1.19.1}"
IMAGE_TAG="${IMAGE_TAG:-v1.0.0}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"
MIRROR="${DEBIAN_MIRROR:-https://deb.debian.org/debian}"
OUTPUT_DIR="${1:-$PWD/dist}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(cd -- "$SCRIPT_DIR/../rootfs" && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run this builder as root (GitHub Actions uses sudo)." >&2
    exit 1
fi

if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    echo "This builder currently targets amd64 and requires an amd64 host." >&2
    exit 1
fi

for command in debootstrap git curl tar zstd sha256sum mount chroot systemctl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing build dependency: $command" >&2
        exit 1
    fi
done

if [[ ! -r /usr/share/keyrings/debian-archive-keyring.gpg ]]; then
    echo "Missing Debian archive keyring; install debian-archive-keyring before building." >&2
    exit 1
fi

if [[ ! "$ST_VERSION" =~ ^[0-9A-Za-z._-]+$ || ! "$IMAGE_TAG" =~ ^[0-9A-Za-z._-]+$ ]]; then
    echo "ST_VERSION and IMAGE_TAG may contain only letters, digits, dots, underscores, and hyphens." >&2
    exit 1
fi

OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"
WORK_DIR="$(mktemp -d)"
ROOTFS="$WORK_DIR/rootfs"
NODE_TARBALL="node-${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_TARBALL}"
IMAGE="debian-${DEBIAN_SUITE}-sillytavern-${IMAGE_TAG}-amd64.tar.zst"
MOUNTED_PROC=0
MOUNTED_DEV=0

cleanup() {
    if [[ "$MOUNTED_PROC" -eq 1 ]]; then
        umount "$ROOTFS/proc" || true
    fi
    if [[ "$MOUNTED_DEV" -eq 1 ]]; then
        umount "$ROOTFS/dev" || true
    fi
    rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$ROOTFS"
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --include=systemd,systemd-sysv,ca-certificates,curl,git,ifupdown2,iproute2,iputils-ping,isc-dhcp-client,libstdc++6,openssl,passwd,procps,tar,xz-utils \
    "$DEBIAN_SUITE" "$ROOTFS" "$MIRROR"

cp -a "$OVERLAY_DIR/." "$ROOTFS/"
chmod 0755 "$ROOTFS/usr/local/sbin/sillytavern-firstboot"

mkdir -p "$WORK_DIR/downloads"
curl --fail --location --silent --show-error "$NODE_URL" -o "$WORK_DIR/downloads/$NODE_TARBALL"
curl --fail --location --silent --show-error \
    "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" \
    -o "$WORK_DIR/downloads/SHASUMS256.txt"
(
    cd "$WORK_DIR/downloads"
    grep "  ${NODE_TARBALL}$" SHASUMS256.txt | sha256sum --check --status
)
tar -xJf "$WORK_DIR/downloads/$NODE_TARBALL" \
    --strip-components=1 \
    -C "$ROOTFS/usr/local"

mkdir -p "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/opt"
mount --bind /dev "$ROOTFS/dev"
MOUNTED_DEV=1
mount -t proc proc "$ROOTFS/proc"
MOUNTED_PROC=1

rm -f "$ROOTFS/etc/resolv.conf"
cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
chroot "$ROOTFS" /usr/bin/apt-get update
chroot "$ROOTFS" /usr/bin/apt-get install --yes --no-install-recommends build-essential pkg-config python3

git clone \
    --depth 1 \
    --single-branch \
    --branch "$ST_VERSION" \
    https://github.com/SillyTavern/SillyTavern.git \
    "$ROOTFS/opt/sillytavern"

chroot "$ROOTFS" /bin/bash -c 'cd /opt/sillytavern && /usr/local/bin/npm ci --omit=dev --no-audit --no-fund'
rm -rf "$ROOTFS/opt/sillytavern/.git"
# ifupdown2 uses Python 3 at runtime, so keep python3 in the template.
chroot "$ROOTFS" /usr/bin/apt-get purge --yes build-essential pkg-config
chroot "$ROOTFS" /usr/bin/apt-get autoremove --yes --purge

chroot "$ROOTFS" /usr/sbin/useradd \
    --system \
    --create-home \
    --home-dir /var/lib/sillytavern \
    --user-group \
    --shell /usr/sbin/nologin \
    sillytavern

cat > "$ROOTFS/opt/sillytavern/config.yaml" <<'EOF'
listen: true
listenAddress:
  ipv4: 0.0.0.0
  ipv6: ''
protocol:
  ipv4: true
  ipv6: false
dnsPreferIPv6: false
port: 8000
browserLaunch:
  enabled: false
whitelistMode: false
basicAuthMode: true
basicAuthUser:
  username: admin
  password: generated-on-first-boot
enableUserAccounts: false
whitelist:
  - 127.0.0.1
sso:
  trustedProxies:
    - 127.0.0.1
privateAddressWhitelist:
  allowedRanges:
    - 127.0.0.0/8
EOF

cat > "$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 sillytavern
EOF

cat > "$ROOTFS/etc/hostname" <<'EOF'
sillytavern
EOF

cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:2 attempts:3
EOF

mkdir -p "$ROOTFS/etc/network"
cat > "$ROOTFS/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

cat > "$ROOTFS/etc/apt/apt.conf.d/99force-ipv4" <<'EOF'
Acquire::ForceIPv4 "true";
EOF

chroot "$ROOTFS" /usr/bin/apt-get clean
rm -rf "$ROOTFS/var/lib/apt/lists/"* "$ROOTFS/var/cache/apt/archives/"*.deb
find "$ROOTFS/var/log" -type f -delete
find "$ROOTFS/tmp" -mindepth 1 -delete
find "$ROOTFS/var/tmp" -mindepth 1 -delete
rm -f "$ROOTFS/etc/machine-id"
touch "$ROOTFS/etc/machine-id"
mkdir -p "$ROOTFS/var/lib/dbus"
ln -sf /etc/machine-id "$ROOTFS/var/lib/dbus/machine-id"
chmod 0755 "$ROOTFS/root"
chroot "$ROOTFS" /usr/bin/chown -R sillytavern:sillytavern /opt/sillytavern /var/lib/sillytavern

systemctl --root="$ROOTFS" enable sillytavern-bootstrap.service
systemctl --root="$ROOTFS" enable sillytavern-disable-ipv6.service
systemctl --root="$ROOTFS" enable sillytavern.service
systemctl --root="$ROOTFS" enable networking.service

umount "$ROOTFS/proc"
MOUNTED_PROC=0
umount "$ROOTFS/dev"
MOUNTED_DEV=0

tar \
    --sort=name \
    --mtime="@$SOURCE_DATE_EPOCH" \
    --numeric-owner \
    --xattrs \
    --acls \
    --exclude='./dev/*' \
    --exclude='./proc/*' \
    --exclude='./sys/*' \
    --exclude='./run/*' \
    --exclude='./tmp/*' \
    -C "$ROOTFS" \
    -I 'zstd -19 -T0' \
    -cf "$OUTPUT_DIR/$IMAGE" .

(
    cd "$OUTPUT_DIR"
    sha256sum "$IMAGE" > "$IMAGE.sha256"
)

echo "Built: $OUTPUT_DIR/$IMAGE"
echo "Checksum: $OUTPUT_DIR/$IMAGE.sha256"
