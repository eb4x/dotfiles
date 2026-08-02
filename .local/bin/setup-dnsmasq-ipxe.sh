#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y dnsmasq nginx policycoreutils-python-utils

tftp_root=/var/lib/tftp
sudo mkdir -p $tftp_root

# iPXE binaries for the first DHCP round, built by build-ipxe.sh and vendored in
# this repo. Not downloaded here on purpose: boot.ipxe.org tracks git master and
# rebuilds several times a day, publishing no version, checksum or signature --
# there is nothing stable to pin a hash against, because the bytes behind a given
# URL are not the same bytes an hour later. The distro packages are no better:
# AlmaLinux 10 ships neither ipxe-x86_64.efi nor ipxe-i386.efi, and Alma 8's
# build predates HTTPS support, so the same script would deploy a different iPXE
# depending on which host it ran on. Vendoring means every machine boots the
# binary that was built, tested and disassembled.
#
# Deployed unconditionally (like the menus below), so `build-ipxe.sh` plus a
# `dotfiles pull` is the whole procedure for moving to a newer iPXE.
ipxe_blobs=~/.local/share/ipxe/blobs

if ! (cd $ipxe_blobs && sha256sum --quiet --strict --check sha256sums); then
  echo "ERROR: vendored iPXE blobs do not match $ipxe_blobs/sha256sums" >&2
  exit 1
fi

sudo install -m 0644 \
  $ipxe_blobs/undionly.kpxe $ipxe_blobs/ipxe.efi $ipxe_blobs/ipxe-i386.efi \
  $tftp_root/

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

# Nothing here configures which root certificates iPXE trusts. iPXE does have a
# "trust" setting (option 175 sub-option 90) that looks like the natural place
# for it, and it is not: crypto/rootcert.c reads that setting in rootcert_init(),
# a STARTUP_LATE function that latches `initialised = 1` on its first run, which
# happens before any DHCP lease exists. `show trust` in the iPXE shell will
# happily print whatever dnsmasq sent -- that reads the settings tree live -- but
# a DEBUG=rootcert build on a real PXE boot reports "ROOTCERT using 1 built-in
# certificate(s)", the iPXE CA, regardless. The anchors are therefore baked in by
# build-ipxe.sh via CERT= and TRUST=.

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
