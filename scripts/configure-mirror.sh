#!/usr/bin/env bash
set -Eeuo pipefail

: "${ROOTFS:?}" "${DISTRO:?}" "${VERSION:?}" "${ARCH:?}" "${MIRROR:?}"

case "$MIRROR" in
  ustc) MIRROR_ROOT="https://mirrors.ustc.edu.cn" ;;
  tuna) MIRROR_ROOT="https://mirrors.tuna.tsinghua.edu.cn" ;;
  aliyun) MIRROR_ROOT="https://mirrors.aliyun.com" ;;
  *) echo "Unsupported mirror: $MIRROR" >&2; exit 1 ;;
esac

configure_deb() {
  rm -rf "$ROOTFS/etc/apt/sources.list.d"
  mkdir -p "$ROOTFS/etc/apt/sources.list.d"

  if [[ "$DISTRO" == debian ]]; then
    cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $MIRROR_ROOT/debian $CODENAME main contrib non-free non-free-firmware
deb $MIRROR_ROOT/debian $CODENAME-updates main contrib non-free non-free-firmware
deb $MIRROR_ROOT/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb $MIRROR_ROOT/debian $CODENAME-backports main contrib non-free non-free-firmware
EOF
  else
    local suffix=ubuntu
    [[ "$ARCH" == arm64 ]] && suffix=ubuntu-ports
    cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $MIRROR_ROOT/$suffix $CODENAME main restricted universe multiverse
deb $MIRROR_ROOT/$suffix $CODENAME-updates main restricted universe multiverse
deb $MIRROR_ROOT/$suffix $CODENAME-security main restricted universe multiverse
deb $MIRROR_ROOT/$suffix $CODENAME-backports main restricted universe multiverse
EOF
  fi

  cat > "$ROOTFS/etc/apt/apt.conf.d/99pve-template" <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Retries "3";
EOF
}

configure_rhel() {
  local distro_path stream_version crb_path
  rm -rf "$ROOTFS/etc/yum.repos.d"
  mkdir -p "$ROOTFS/etc/yum.repos.d"

  case "$DISTRO" in
    almalinux) distro_path=almalinux ;;
    rockylinux)
      if [[ "$MIRROR" == aliyun ]]; then distro_path=rockylinux; else distro_path=rocky; fi
      ;;
    centos-stream) distro_path=centos-stream ;;
  esac

  stream_version="$VERSION"
  [[ "$DISTRO" == centos-stream ]] && stream_version="${VERSION}-stream"
  crb_path=CRB
  [[ "$VERSION" == 8 ]] && crb_path=PowerTools

  cat > "$ROOTFS/etc/yum.repos.d/domestic.repo" <<EOF
[baseos]
name=$DISTRO $VERSION - BaseOS
baseurl=$MIRROR_ROOT/$distro_path/$stream_version/BaseOS/$RHEL_ARCH/os/
enabled=1
gpgcheck=1
repo_gpgcheck=0

[appstream]
name=$DISTRO $VERSION - AppStream
baseurl=$MIRROR_ROOT/$distro_path/$stream_version/AppStream/$RHEL_ARCH/os/
enabled=1
gpgcheck=1
repo_gpgcheck=0

[crb]
name=$DISTRO $VERSION - CRB/PowerTools
baseurl=$MIRROR_ROOT/$distro_path/$stream_version/$crb_path/$RHEL_ARCH/os/
enabled=1
gpgcheck=1
repo_gpgcheck=0
EOF
}

configure_alpine() {
  mkdir -p "$ROOTFS/etc/apk"
  cat > "$ROOTFS/etc/apk/repositories" <<EOF
$MIRROR_ROOT/alpine/v$VERSION/main
$MIRROR_ROOT/alpine/v$VERSION/community
EOF
}

case "$DISTRO" in
  debian|ubuntu) configure_deb ;;
  almalinux|rockylinux|centos-stream) configure_rhel ;;
  alpine) configure_alpine ;;
  *) echo "Unsupported distro: $DISTRO" >&2; exit 1 ;;
esac
