#!/usr/bin/env bash
set -euo pipefail

tftp_root=/var/lib/tftp
sudo mkdir -p $tftp_root

declare -A ipxe_files=(
  [ipxe.efi]="sha256:18765cb827377edfd895d2a805adcff0bdedd8f45a039b8374a4a598c5485731"
  [undionly.kpxe]="sha256:a5709eb9262dda827e5b10503b212822dd7608f6574056967f6bc15da9ca8dc8"
)

for ipxe_file in ${!ipxe_files[*]}; do
  if [ ! -f /var/lib/tftp/${ipxe_file} ]; then
    sudo curl https://boot.ipxe.org/${ipxe_file} -o /var/lib/tftp/${ipxe_file}
  fi

  if [ "sha256:$(sha256sum /var/lib/tftp/${ipxe_file} | awk '{print $1}')" != "${ipxe_files[$ipxe_file]}" ]; then
    echo "Unexpected sha256sum"
  fi
done

if [ ! -f /var/lib/tftp/autoexec.ipxe ]; then
  sudo tee /var/lib/tftp/autoexec.ipxe > /dev/null << 'EOF'
#!ipxe

dhcp

#cpuid --ext 29 && set arch x86_64 || set arch i386

#set fedora-mirror-url https://fedora.uib.no/fedora/linux/releases
#set fedora-mirror-url https://mirror.accum.se/mirror/fedora/linux/releases
set fedora-mirror-url https://mirrors.dotsrc.org/fedora-enchilada/linux/releases
#set fedora-mirror-url https://www.nic.funet.fi/pub/mirrors/fedora.redhat.com/pub/fedora/linux/releases

:start
menu Operating systems
item almalinux-9 AlmaLinux 9
item fedora-41   Fedora 41
item fedora-40   Fedora 40
choose os
goto ${os}

:almalinux-9
kernel https://almalinux.uib.no/9/BaseOS/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.repo=https://almalinux.uib.no/9/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd https://almalinux.uib.no/9/BaseOS/x86_64/os/images/pxeboot/initrd.img
boot

:fedora-41
set fedora-inst-repo-url ${fedora-mirror-url}/41/Everything/x86_64/os

kernel ${fedora-inst-repo-url}/images/pxeboot/vmlinuz ip=dhcp inst.repo=${fedora-inst-repo-url} inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/fedora.ks
initrd ${fedora-inst-repo-url}/images/pxeboot/initrd.img
boot

:fedora-40
set fedora-inst-repo-url ${fedora-mirror-url}/40/Everything/x86_64/os

kernel ${fedora-inst-repo-url}/images/pxeboot/vmlinuz ip=dhcp inst.repo=${fedora-inst-repo-url} inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/fedora.ks
initrd ${fedora-inst-repo-url}/images/pxeboot/initrd.img
boot
EOF
fi

sudo dnf install policycoreutils-python-utils
sudo semanage fcontext -a -t tftpdir_t "/var/lib/tftp(/.*)?"
sudo restorecon -Rv /var/lib/tftp

if [ ! -f /etc/dnsmasq.d/ipxe.conf ]; then
  sudo tee /etc/dnsmasq.d/ipxe.conf > /dev/null << EOF
enable-tftp
tftp-root=/var/lib/tftp

# Legacy PXE Boot
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:bios,undionly.kpxe

# UEFI
dhcp-match=set:uefi,option:client-arch,7
dhcp-boot=tag:uefi,ipxe.efi

# iPXE
dhcp-match=set:ipxe,175
dhcp-boot=tag:ipxe,autoexec.ipxe
EOF
fi

sudo systemctl restart dnsmasq.service
