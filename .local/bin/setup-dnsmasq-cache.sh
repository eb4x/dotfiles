#!/usr/bin/env bash
set -euo pipefail

tftp_root=$HOME/src/tftp

for releasever in 8 9; do
  work_dir=$tftp_root/almalinux/$releasever/x86_64/os
  mkdir -p $work_dir/images/pxeboot

  http_root=https://almalinux.uib.no/$releasever/BaseOS/x86_64/os
  for pxe_file in images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      curl -L "$http_root/$pxe_file" -o $work_dir/$pxe_file
    fi
  done
done

for releasever in 41; do
  work_dir=$tftp_root/fedora/$releasever/x86_64/os
  mkdir -p $work_dir/images/pxeboot

  http_root=https://download.fedoraproject.org/pub/fedora/linux/releases/$releasever/Everything/x86_64/os
  for pxe_file in images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      curl -L "$http_root/$pxe_file" -o $work_dir/$pxe_file
    fi
  done
done

sudo tee /var/lib/tftp/cached.ipxe > /dev/null << 'EOF'
#!ipxe

menu Cached installers
item almalinux-9 AlmaLinux 9
item almalinux-8 AlmaLinux 8
item fedora-41   Fedora 41
item fedora-40   Fedora 40
choose os
goto ${os}

:almalinux-9
kernel http://${next-server}/almalinux/9/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://${next-server}/almalinux/9/x86_64/os inst.repo=https://almalinux.uib.no/9/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd http://${next-server}/almalinux/9/x86_64/os/images/pxeboot/initrd.img
boot

:almalinux-8
kernel http://${next-server}/almalinux/8/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://${next-server}/almalinux/8/x86_64/os inst.repo=https://almalinux.uib.no/8/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd http://${next-server}/almalinux/8/x86_64/os/images/pxeboot/initrd.img
boot

:fedora-41
kernel http://${next-server}/fedora/41/x86_64/os/images/vmlinuz ip=dhcp inst.stage2=http://${next-server}/fedora/41/x86_64/os inst.repo=https://fedora.uib.no/fedora/linux/releases/41/Everything/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/fedora.ks
initrd http://${next-server}/fedora/41/x86_64/os/images/initrd.img
boot
EOF
