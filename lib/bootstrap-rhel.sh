#!/usr/bin/env bash

rhel_official_root() {
  case "$DISTRO" in
    almalinux) echo "https://repo.almalinux.org/almalinux/$VERSION" ;;
    rockylinux) echo "https://dl.rockylinux.org/pub/rocky/$VERSION" ;;
    centos-stream) echo "https://mirror.stream.centos.org/${VERSION}-stream" ;;
    *) die "Unsupported RHEL-family distro: $DISTRO" ;;
  esac
}

rhel_release_package() {
  case "$DISTRO" in
    almalinux) echo almalinux-release ;;
    rockylinux) echo rocky-release ;;
    centos-stream) echo centos-stream-release ;;
  esac
}

write_bootstrap_rhel_repos() {
  local repo_dir=$1 root crb_path
  root=$(rhel_official_root)
  crb_path=CRB
  [[ "$VERSION" == 8 ]] && crb_path=PowerTools

  mkdir -p "$repo_dir"
  cat > "$repo_dir/bootstrap.repo" <<EOF
[baseos]
name=Bootstrap BaseOS
baseurl=$root/BaseOS/$RHEL_ARCH/os/
enabled=1
gpgcheck=0

[appstream]
name=Bootstrap AppStream
baseurl=$root/AppStream/$RHEL_ARCH/os/
enabled=1
gpgcheck=0

[crb]
name=Bootstrap CRB
baseurl=$root/$crb_path/$RHEL_ARCH/os/
enabled=1
gpgcheck=0
EOF
}

run_host_dnf() {
  local repo_dir=$1
  shift
  dnf -y \
    --installroot="$ROOTFS" \
    --forcearch="$RHEL_ARCH" \
    --releasever="$VERSION" \
    --setopt="reposdir=$repo_dir" \
    --setopt="module_platform_id=platform:el$VERSION" \
    --setopt=install_weak_deps=False \
    --setopt=keepcache=False \
    "$@"
}

bootstrap_rhel_base() {
  local repo_dir="$WORK_DIR/bootstrap-rhel-repos"
  local release_pkg minimal

  write_bootstrap_rhel_repos "$repo_dir"
  release_pkg=$(rhel_release_package)
  mapfile -t minimal < <(packages_rhel_minimal)

  ensure_rootfs_dirs
  install_qemu_if_needed
  copy_resolver

  log "Bootstrapping $DISTRO $VERSION ($RHEL_ARCH)"
  run_host_dnf "$repo_dir" --nogpgcheck --repo=baseos --repo=appstream --repo=crb \
    install "$release_pkg" "${minimal[@]}"

  mkdir -p "$ROOTFS/etc/pki/rpm-gpg"
  local key
  for key in "$ROOTFS"/etc/pki/rpm-gpg/*; do
    [[ -f "$key" ]] && rpm --root "$ROOTFS" --import "$key" || true
  done
}

rhel_install_resilient() {
  local repo_dir="$ROOTFS/etc/yum.repos.d"
  local packages=("$@") pkg
  ((${#packages[@]})) || return 0

  if run_host_dnf "$repo_dir" install "${packages[@]}"; then
    return 0
  fi

  warn "A DNF package batch failed; retrying packages individually."
  for pkg in "${packages[@]}"; do
    run_host_dnf "$repo_dir" install "$pkg" || warn "Optional package unavailable: $pkg"
  done
}

install_rhel_packages() {
  local standard full
  mapfile -t standard < <(packages_rhel_standard)
  mapfile -t full < <(packages_rhel_full)

  run_host_dnf "$ROOTFS/etc/yum.repos.d" makecache

  case "$PROFILE" in
    minimal) ;;
    standard) rhel_install_resilient "${standard[@]}" ;;
    full)
      rhel_install_resilient "${standard[@]}"
      rhel_install_resilient "${full[@]}"
      ;;
  esac

  systemctl_root enable sshd.service NetworkManager.service pve-static-only.service pve-firstboot.service
  systemctl_root disable NetworkManager-wait-online.service
}
