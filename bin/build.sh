#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/packages.sh"
source "$PROJECT_ROOT/lib/bootstrap-deb.sh"
source "$PROJECT_ROOT/lib/bootstrap-rhel.sh"
source "$PROJECT_ROOT/lib/bootstrap-alpine.sh"

usage() {
  cat <<'EOF'
Usage:
  sudo ./bin/build.sh --target TARGET --arch amd64|arm64 \
    --profile minimal|standard|full --mirror ustc|tuna|aliyun [--output DIR]
EOF
}

TARGET=""
ARCH=amd64
PROFILE=full
MIRROR=ustc
OUTPUT_DIR="$PROJECT_ROOT/dist"

while (($#)); do
  case "$1" in
    --target) TARGET=${2:-}; shift 2 ;;
    --arch) ARCH=${2:-}; shift 2 ;;
    --profile) PROFILE=${2:-}; shift 2 ;;
    --mirror) MIRROR=${2:-}; shift 2 ;;
    --output) OUTPUT_DIR=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

require_root
[[ -n "$TARGET" ]] || { usage; die "--target is required"; }
[[ "$ARCH" =~ ^(amd64|arm64)$ ]] || die "Invalid architecture: $ARCH"
[[ "$PROFILE" =~ ^(minimal|standard|full)$ ]] || die "Invalid profile: $PROFILE"
[[ "$MIRROR" =~ ^(ustc|tuna|aliyun)$ ]] || die "Invalid mirror: $MIRROR"

TARGET_JSON=$(jq -cer --arg id "$TARGET" '.[] | select(.id == $id)' "$PROJECT_ROOT/config/targets.json") \
  || die "Unknown target: $TARGET"
FAMILY=$(jq -r '.family' <<<"$TARGET_JSON")
DISTRO=$(jq -r '.distro' <<<"$TARGET_JSON")
VERSION=$(jq -r '.version' <<<"$TARGET_JSON")
CODENAME=$(jq -r '.codename' <<<"$TARGET_JSON")

WORK_DIR=${WORK_DIR:-"$PROJECT_ROOT/work/${TARGET}-${ARCH}-${PROFILE}-${MIRROR}"}
ROOTFS="$WORK_DIR/rootfs"
OUTPUT_DIR=$(realpath -m "$OUTPUT_DIR")

export PROJECT_ROOT TARGET ARCH PROFILE MIRROR OUTPUT_DIR FAMILY DISTRO VERSION CODENAME WORK_DIR ROOTFS
map_arches

trap cleanup_on_exit EXIT INT TERM
rm -rf "$WORK_DIR"
mkdir -p "$ROOTFS" "$OUTPUT_DIR"

log "Target=$TARGET Arch=$ARCH Profile=$PROFILE Mirror=$MIRROR"

case "$FAMILY" in
  deb) bootstrap_deb_base ;;
  rhel) bootstrap_rhel_base ;;
  alpine) bootstrap_alpine_base ;;
  *) die "Unsupported family: $FAMILY" ;;
esac

"$PROJECT_ROOT/scripts/configure-mirror.sh"

case "$FAMILY" in
  deb) install_deb_packages ;;
  rhel) install_rhel_packages ;;
  alpine) install_alpine_packages ;;
esac

# Apply template policies after the distro packages have created their defaults.
"$PROJECT_ROOT/scripts/configure-network.sh"
"$PROJECT_ROOT/scripts/configure-firstboot.sh"
"$PROJECT_ROOT/scripts/configure-ssh.sh"

# Enable services after their unit/init files and packages exist.
if [[ "$DISTRO" == alpine ]]; then
  in_root rc-update add pve-static-only boot || true
  in_root rc-update add pve-firstboot boot || true
  in_root rc-update add sshd default || true
else
  systemctl_root enable pve-static-only.service pve-firstboot.service
  if [[ "$FAMILY" == deb ]]; then
    systemctl_root enable ssh.service networking.service
  else
    systemctl_root enable sshd.service NetworkManager.service
  fi
fi

unmount_chroot
"$PROJECT_ROOT/scripts/container-compat.sh"
"$PROJECT_ROOT/scripts/cleanup.sh"
"$PROJECT_ROOT/scripts/validate.sh"
"$PROJECT_ROOT/scripts/package.sh"

log "Build completed successfully."
