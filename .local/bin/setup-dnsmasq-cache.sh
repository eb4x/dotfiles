#!/usr/bin/env bash
set -euo pipefail

echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
sudo chmod 0440 /etc/sudoers.d/$USER

tftp_root=/var/lib/tftp
sudo mkdir -p $tftp_root
sudo chown -R $USER:$USER $tftp_root

alma_releases=(8 9 10)
fedora_releases=(42 43 44_Beta 44)

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

download_file() {
  local url=$1
  local dest=$2

  local http_code
  http_code=$(curl --silent -L "$url" --output "$dest" --write-out "%{http_code}")

  if [[ "$http_code" != 2* ]]; then
    echo "ERROR: Got HTTP $http_code for $url" >&2
    rm -f "$dest"  # Don't leave a junk HTML file behind
    return 1
  fi
}

for releasever in "${alma_releases[@]}"; do
  work_dir=$tftp_root/almalinux/$releasever/x86_64/os
  mkdir -p $work_dir/images/pxeboot

  http_root=https://almalinux.uib.no/$releasever/BaseOS/x86_64/os
  for pxe_file in images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      download_file "$http_root/$pxe_file" "$work_dir/$pxe_file"
    fi
  done
done

for releasever in 10; do
  work_dir=$tftp_root/almalinux/$releasever/x86_64_v2/os
  mkdir -p $work_dir/images/pxeboot

  http_root=https://almalinux.uib.no/$releasever/BaseOS/x86_64_v2/os
  for pxe_file in images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      download_file "$http_root/$pxe_file" "$work_dir/$pxe_file"
    fi
  done
done

declare -A fedora_release_paths=(
  [44_Beta]="test/44_Beta"
)

for releasever in "${fedora_releases[@]}"; do
  work_dir=$tftp_root/fedora/$releasever/x86_64/os
  mkdir -p $work_dir/images/pxeboot

  release_path="${fedora_release_paths[$releasever]:-$releasever}"
  http_root=https://fedora.uib.no/fedora/linux/releases/${release_path}/Everything/x86_64/os
  #http_root=https://download.fedoraproject.org/pub/fedora/linux/releases/${release_path}/Everything/x86_64/os
  for pxe_file in images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      download_file "$http_root/$pxe_file" "$work_dir/$pxe_file"
    fi
  done
done

gparted_version="1.7.0-1"
if [ ! -d "${tftp_root}/gparted/${gparted_version}" ]; then
  mkdir -p "${tftp_root}/gparted/${gparted_version}"
  curl -L https://sourceforge.net/projects/gparted/files/gparted-live-stable/${gparted_version}/gparted-live-${gparted_version}-amd64.zip/download | sudo bsdtar --extract --file - --directory $tftp_root/gparted/${gparted_version}
fi

tee /var/lib/tftp/cached.ipxe > /dev/null << EOF
#!ipxe

set fedora-mirror-url https://fedora.uib.no/fedora/linux/releases
#set fedora-mirror-url https://download.fedoraproject.org/pub/fedora/linux/releases

menu Cached installers
EOF

# menu items
for releasever in "${alma_releases[@]}"; do
  echo "item almalinux-${releasever,,} AlmaLinux ${releasever}" >> /var/lib/tftp/cached.ipxe
done
for releasever in "${fedora_releases[@]}"; do
  echo "item fedora-${releasever,,} Fedora ${releasever}" >> /var/lib/tftp/cached.ipxe
done
echo "item gparted GParted" >> /var/lib/tftp/cached.ipxe

tee -a /var/lib/tftp/cached.ipxe > /dev/null << EOF
choose os
goto \${os}
EOF

append_alma_stanza() {
  local releasever=$1
  cat >> /var/lib/tftp/cached.ipxe << EOF

:almalinux-${releasever}
kernel http://\${next-server}:8000/almalinux/${releasever}/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/almalinux/${releasever}/x86_64/os inst.repo=https://almalinux.uib.no/${releasever}/BaseOS/x86_64/os inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/almalinux-9.ks
initrd http://\${next-server}:8000/almalinux/${releasever}/x86_64/os/images/pxeboot/initrd.img
boot
EOF
}
append_fedora_stanza() {
  local releasever=$1
  local release_path="${fedora_release_paths[$releasever]:-$releasever}"
  cat >> /var/lib/tftp/cached.ipxe << EOF

:fedora-${releasever,,}
set fedora-inst-repo-url \${fedora-mirror-url}/${release_path}/Everything/\${arch}/os
kernel http://\${next-server}:8000/fedora/${releasever}/x86_64/os/images/pxeboot/vmlinuz ip=dhcp inst.stage2=http://\${next-server}:8000/fedora/${releasever}/x86_64/os inst.repo=\${fedora-inst-repo-url} inst.ks=https://raw.githubusercontent.com/eb4x/dotfiles/refs/heads/main/.local/share/kickstart/fedora.ks
initrd http://\${next-server}:8000/fedora/${releasever}/x86_64/os/images/pxeboot/initrd.img
boot
EOF
}

for releasever in "${alma_releases[@]}"; do append_alma_stanza "$releasever"; done
for releasever in "${fedora_releases[@]}"; do append_fedora_stanza "$releasever"; done

tee -a /var/lib/tftp/cached.ipxe > /dev/null << EOF

:gparted
kernel http://\${next-server}:8000/gparted/${gparted_version}/live/vmlinuz boot=live config components union=overlay username=user noswap noeject vga=788 fetch=http://\${next-server}:8000/gparted/${gparted_version}/live/filesystem.squashfs
initrd http://\${next-server}:8000/gparted/${gparted_version}/live/initrd.img
boot
EOF

sudo rm /etc/sudoers.d/$USER
