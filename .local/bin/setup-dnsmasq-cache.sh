#!/usr/bin/env bash
set -euo pipefail

echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
sudo chmod 0440 /etc/sudoers.d/$USER

# Needs selinux relabeling to allow both dnsmasq and nginx
sudo semanage fcontext -a -t public_content_t "/var/lib/tftp(/.*)?"
sudo restorecon -Rv /var/lib/tftp
if [[ -d /etc/nginx/conf.d ]]; then
  sudo tee /etc/nginx/conf.d/tftp.conf > /dev/null << EOF
# vim: ft=nginx

server {
    listen 8000;
    server_name localhost;

    location / {
        root /var/lib/tftp;
        autoindex on;
        sendfile on;
        default_type application/octet-stream;
    }
}
EOF
fi

tftp_root=/var/lib/tftp
for releasever in 8 9 10; do
  work_dir=$tftp_root/almalinux/$releasever/x86_64/os
  mkdir -p $work_dir/images/pxeboot

  http_root=https://almalinux.uib.no/$releasever/BaseOS/x86_64/os
  for pxe_file in images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      sudo curl -L "$http_root/$pxe_file" -o $work_dir/$pxe_file
    fi
  done
done

for releasever in 41 42; do
  work_dir=$tftp_root/fedora/$releasever/x86_64/os
  mkdir -p $work_dir/images/pxeboot

  #http_root=https://fedora.uib.no/fedora/linux/releases/$releasever/Everything/x86_64/os
  http_root=https://download.fedoraproject.org/pub/fedora/linux/releases/$releasever/Everything/x86_64/os
  for pxe_file in images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      sudo curl -L "$http_root/$pxe_file" -o $work_dir/$pxe_file
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

set fedora-mirror-url https://fedora.uib.no/fedora/linux/releases
#set fedora-mirror-url https://mirror.accum.se/mirror/fedora/linux/releases
#set fedora-mirror-url https://mirrors.dotsrc.org/fedora-enchilada/linux/releases
#set fedora-mirror-url https://www.nic.funet.fi/pub/mirrors/fedora.redhat.com/pub/fedora/linux/releases

menu Cached installers
item almalinux-10 AlmaLinux 10
item almalinux-9 AlmaLinux 9
item almalinux-8 AlmaLinux 8
item fedora-42   Fedora 42
item fedora-41   Fedora 41
item gparted     GParted
choose os
goto \${os}

:almalinux-10
kernel http://\${next-server}:8000/almalinux/10/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/almalinux/10/x86_64/os inst.repo=https://almalinux.uib.no/10/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd http://\${next-server}:8000/almalinux/10/x86_64/os/images/pxeboot/initrd.img
boot

:almalinux-9
kernel http://\${next-server}:8000/almalinux/9/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/almalinux/9/x86_64/os inst.repo=https://almalinux.uib.no/9/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd http://\${next-server}:8000/almalinux/9/x86_64/os/images/pxeboot/initrd.img
boot

:almalinux-8
kernel http://\${next-server}:8000/almalinux/8/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/almalinux/8/x86_64/os inst.repo=https://almalinux.uib.no/8/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd http://\${next-server}:8000/almalinux/8/x86_64/os/images/pxeboot/initrd.img
boot

:fedora-42
set fedora-inst-repo-url \${fedora-mirror-url}/42/Everything/\${arch}/os
kernel http://\${next-server}:8000/fedora/42/x86_64/os/images/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/fedora/41/x86_64/os inst.repo=\${fedora-inst-repo-url} inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/fedora.ks
initrd http://\${next-server}:8000/fedora/42/x86_64/os/images/initrd.img
boot

:fedora-41
set fedora-inst-repo-url \${fedora-mirror-url}/41/Everything/\${arch}/os
kernel http://\${next-server}:8000/fedora/41/x86_64/os/images/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/fedora/41/x86_64/os inst.repo=\${fedora-inst-repo-url} inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/fedora.ks
initrd http://\${next-server}:8000/fedora/41/x86_64/os/images/initrd.img
boot

:gparted
kernel http://\${next-server}:8000/gparted/${gparted_version}/live/vmlinuz boot=live config components union=overlay username=user noswap noeject vga=788 fetch=http://\${next-server}:8000/gparted/${gparted_version}/live/filesystem.squashfs
initrd http://\${next-server}:8000/gparted/${gparted_version}/live/initrd.img
boot
EOF

sudo rm /etc/sudoers.d/$USER
