#!/usr/bin/env bash
set -euo pipefail

echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
sudo chmod 0440 /etc/sudoers.d/$USER

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

gparted_version="1.7.0-1"
if [ ! -d "${tftp_root}/gparted/${gparted_version}" ]; then
  mkdir -p "${tftp_root}/gparted/${gparted_version}"
  curl -L https://sourceforge.net/projects/gparted/files/gparted-live-stable/${gparted_version}/gparted-live-${gparted_version}-amd64.zip/download | sudo bsdtar --extract --file - --directory $tftp_root/gparted/${gparted_version}
fi

sudo tee /var/lib/tftp/cached.ipxe > /dev/null << EOF
#!ipxe

menu Cached installers
item almalinux-9 AlmaLinux 9
item almalinux-8 AlmaLinux 8
item fedora-41   Fedora 41
item fedora-40   Fedora 40
item gparted     GParted
choose os
goto \${os}

:almalinux-9
kernel http://\${next-server}:8000/almalinux/9/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/almalinux/9/x86_64/os inst.repo=https://almalinux.uib.no/9/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd http://\${next-server}:8000/almalinux/9/x86_64/os/images/pxeboot/initrd.img
boot

:almalinux-8
kernel http://\${next-server}:8000/almalinux/8/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/almalinux/8/x86_64/os inst.repo=https://almalinux.uib.no/8/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd http://\${next-server}:8000/almalinux/8/x86_64/os/images/pxeboot/initrd.img
boot

:fedora-41
kernel http://\${next-server}:8000/fedora/41/x86_64/os/images/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/fedora/41/x86_64/os inst.repo=https://fedora.uib.no/fedora/linux/releases/41/Everything/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/fedora.ks
initrd http://\${next-server}:8000/fedora/41/x86_64/os/images/initrd.img
boot

:gparted
kernel http://\${next-server}:8000/gparted/${gparted_version}/live/vmlinuz boot=live config components union=overlay username=user noswap noeject vga=788 fetch=http://\${next-server}:8000/gparted/${gparted_version}/live/filesystem.squashfs
initrd http://\${next-server}:8000/gparted/${gparted_version}/live/initrd.img
boot
EOF

sudo rm /etc/sudoers.d/$USER
