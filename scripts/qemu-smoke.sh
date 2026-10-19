#!/usr/bin/env bash
# Documented QEMU workflow for manual smoke testing (run from a Linux host).
set -euo pipefail

ISO="${ISO:-$HOME/Downloads/archlinux-x86_64.iso}"
DISK="${DISK:-/tmp/archmage-test.qcow2}"
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ ! -f "$ISO" ]]; then
  echo "Set ISO to your Arch install image path. Missing: $ISO" >&2
  exit 1
fi

if [[ ! -f "$DISK" ]]; then
  qemu-img create -f qcow2 "$DISK" 20G
fi

cat <<EOF
Starting QEMU (UEFI). Inside the live shell:

  pacman -Sy git jq
  git clone <your-remote> /root/archmage
  cd /root/archmage
  chmod +x archmage
  cp examples/answers.json /tmp/answers.json
  # Edit disk path and passwords in /tmp/answers.json
  ./archmage --dry-run --config /tmp/answers.json

Press Ctrl+Alt+G to release mouse if needed.
EOF

exec qemu-system-x86_64 \
  -m 4096 \
  -smp 4 \
  -enable-kvm \
  -boot d \
  -cdrom "$ISO" \
  -drive file="$DISK",format=qcow2,if=virtio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -display default
