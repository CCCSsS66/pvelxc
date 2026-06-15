#!/usr/bin/env bash
set -Eeuo pipefail
: "${ROOTFS:?}"

mkdir -p "$ROOTFS/etc/ssh/sshd_config.d"
cat > "$ROOTFS/etc/ssh/sshd_config.d/10-pve-template.conf" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication yes
UseDNS no
EOF

main="$ROOTFS/etc/ssh/sshd_config"
if [[ -f "$main" ]]; then
  if ! head -n 5 "$main" | grep -Fq 'Include /etc/ssh/sshd_config.d/10-pve-template.conf'; then
    tmp=$(mktemp)
    {
      echo 'Include /etc/ssh/sshd_config.d/10-pve-template.conf'
      cat "$main"
    } > "$tmp"
    cat "$tmp" > "$main"
    rm -f "$tmp"
  fi
fi

# Leave the template without a reusable password. Proxmox can replace this hash.
if [[ -f "$ROOTFS/etc/shadow" ]]; then
  sed -i -E 's#^root:[^:]*:#root:!:#' "$ROOTFS/etc/shadow"
  chmod 600 "$ROOTFS/etc/shadow"
fi
