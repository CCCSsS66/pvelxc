#!/usr/bin/env bash
set -Eeuo pipefail
: "${ROOTFS:?}" "${OUTPUT_DIR:?}" "${DISTRO:?}" "${VERSION:?}" "${ARCH:?}" "${PROFILE:?}" "${MIRROR:?}" "${FAMILY:?}"

log() { printf '[INFO] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
base="${DISTRO}-${VERSION}-pve-lxc-${PROFILE}-${ARCH}"
archive="$OUTPUT_DIR/${base}.tar.gz"
packages_file="$OUTPUT_DIR/${base}.packages.txt"
manifest="$OUTPUT_DIR/${base}.manifest.json"

case "$FAMILY" in
  deb)
    dpkg-query --admindir="$ROOTFS/var/lib/dpkg" -W -f='${Package}\t${Version}\n' \
      | sort > "$packages_file"
    ;;
  rhel)
    rpm --root "$ROOTFS" -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' \
      | sort > "$packages_file"
    ;;
  alpine)
    awk '
      /^P:/ { package=substr($0,3) }
      /^V:/ { version=substr($0,3); print package "\t" version }
    ' "$ROOTFS/lib/apk/db/installed" | sort > "$packages_file"
    ;;
esac

if [[ -z "${SOURCE_DATE_EPOCH:-}" || ! "${SOURCE_DATE_EPOCH:-}" =~ ^[0-9]+$ ]]; then
  SOURCE_DATE_EPOCH=$(git -C "$PROJECT_ROOT" log -1 --format=%ct 2>/dev/null || date +%s)
fi

log "Packing $archive"
tar --numeric-owner --xattrs --acls --sort=name --mtime="@$SOURCE_DATE_EPOCH" \
  -C "$ROOTFS" -cf - . | gzip -9n > "$archive"

size=$(stat -c '%s' "$archive")
limit=$((2 * 1024 * 1024 * 1024))
(( size < limit )) || die "Release asset exceeds GitHub's 2 GiB per-file limit: $archive"

sha256=$(sha256sum "$archive" | awk '{print $1}')
sha512=$(sha512sum "$archive" | awk '{print $1}')
package_count=$(wc -l < "$packages_file" | tr -d ' ')
build_time=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
git_commit=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)

python3 - "$manifest" <<PY
import json
import sys

manifest = {
    "distro": "$DISTRO",
    "version": "$VERSION",
    "architecture": "$ARCH",
    "profile": "$PROFILE",
    "mirror": "$MIRROR",
    "build_time": "$build_time",
    "git_commit": "$git_commit",
    "dhcp_disabled": True,
    "dhcpv6_disabled": True,
    "ipv6_slaac_disabled": True,
    "root_ssh_enabled": True,
    "package_count": int("$package_count"),
    "archive": "$(basename "$archive")",
    "size_bytes": int("$size"),
    "sha256": "$sha256",
    "sha512": "$sha512",
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

printf '%s  %s\n' "$sha256" "$(basename "$archive")" > "$OUTPUT_DIR/${base}.sha256"
printf '%s  %s\n' "$sha512" "$(basename "$archive")" > "$OUTPUT_DIR/${base}.sha512"

log "Created $(basename "$archive") ($(du -h "$archive" | awk '{print $1}'))"
