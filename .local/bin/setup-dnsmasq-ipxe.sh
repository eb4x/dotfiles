#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y dnsmasq nginx policycoreutils-python-utils

tftp_root=/var/lib/tftp
sudo mkdir -p $tftp_root

# iPXE binaries for the first DHCP round. boot.ipxe.org rebuilds these
# periodically, so the pinned hashes will legitimately drift -- on mismatch,
# verify upstream, update the pin, and rerun (the mismatching file is removed).
declare -A ipxe_urls=(
  [undionly.kpxe]="https://boot.ipxe.org/undionly.kpxe"
  [ipxe.efi]="https://boot.ipxe.org/x86_64-efi/ipxe.efi"
  [ipxe-i386.efi]="https://boot.ipxe.org/i386-efi/ipxe.efi"
)
declare -A ipxe_sha256=(
  [undionly.kpxe]="a0d95f804bc73690fe3bb0e3bfa8304081e6b893277b54ebcf62f925893fee0f"
  [ipxe.efi]="536c351acb71b190a41cf618541d5c6f205b761cb38511cbbd08c0fc1cb050a3"
  [ipxe-i386.efi]="3478e1c21e22846d9cf8a643106eb0816de27e30c002cb85428577b2e16af4c6"
)

for ipxe_file in "${!ipxe_urls[@]}"; do
  if [ ! -f $tftp_root/$ipxe_file ]; then
    sudo curl -fL "${ipxe_urls[$ipxe_file]}" -o $tftp_root/$ipxe_file
  fi

  if [ "$(sha256sum $tftp_root/$ipxe_file | awk '{print $1}')" != "${ipxe_sha256[$ipxe_file]}" ]; then
    echo "ERROR: sha256 mismatch for $ipxe_file, expected ${ipxe_sha256[$ipxe_file]}" >&2
    sudo rm -f $tftp_root/$ipxe_file
    exit 1
  fi
done

# Boot menus and kickstarts. Deployed unconditionally so edits take effect on
# rerun.
sudo install -m 0644 ~/.local/share/ipxe/*.ipxe $tftp_root/
sudo install -m 0644 ~/.local/share/kickstart/fedora.ks ~/.local/share/kickstart/almalinux.ks $tftp_root/

# public_content_t is readable by both dnsmasq (tftp) and nginx; -m updates
# the rule if it already exists, so reruns and label changes are idempotent.
sudo semanage fcontext -a -t public_content_t "$tftp_root(/.*)?" \
  || sudo semanage fcontext -m -t public_content_t "$tftp_root(/.*)?"
sudo restorecon -Rv $tftp_root

# iPXE fetches over http more reliably than tftp, and anaconda needs http for
# stage2/kickstart anyway; nginx serves the whole tftp root on :8000.
sudo tee /etc/nginx/conf.d/tftp.conf > /dev/null << EOF
# vim: ft=nginx

server {
    listen 8000;
    server_name localhost;

    location / {
        root $tftp_root;
        autoindex on;
        sendfile on;
        default_type application/octet-stream;
    }
}
EOF

sudo systemctl enable --now nginx.service
sudo systemctl reload nginx.service

sudo tee /etc/dnsmasq.d/ipxe.conf > /dev/null << EOF
enable-tftp
tftp-root=$tftp_root

# First DHCP round: serve the iPXE binary matching the client arch. tag:!ipxe
# keeps these lines out of the second round, where iPXE (which sets both its
# arch tag and option 175) would otherwise be handed itself in a loop.

# Legacy PXE BIOS
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:bios,tag:!ipxe,undionly.kpxe

# UEFI ia32
dhcp-match=set:uefi32,option:client-arch,6
dhcp-boot=tag:uefi32,tag:!ipxe,ipxe-i386.efi

# UEFI x86-64 (7 = EFI byte-code capable, 9 = plain x86-64 UEFI)
dhcp-match=set:uefi,option:client-arch,7
dhcp-match=set:uefi,option:client-arch,9
dhcp-boot=tag:uefi,tag:!ipxe,ipxe.efi

# Second round: the loaded iPXE re-DHCPs with option 175 set; hand it the menu.
dhcp-match=set:ipxe,175
dhcp-boot=tag:ipxe,autoexec.ipxe
EOF

sudo systemctl enable --now dnsmasq.service
sudo systemctl restart dnsmasq.service
