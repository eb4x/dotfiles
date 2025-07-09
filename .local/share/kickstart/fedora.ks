#graphical --non-interactive
#text --non-interactive
#cmdline

# Keyboard layouts
keyboard --vckeymap=no --xlayouts='no'
# System language
lang en_US.UTF-8

# Run the Setup Agent on first boot
firstboot --disable

# System timezone
timezone Europe/Oslo --utc

#Root password
rootpw --lock

user --name=erikberg --groups=wheel --password=changeme --gecos="Erik Berg"
sshkey --username=erikberg "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBIBDkDbOgeJHXOM9PZo2Nok5MB5AoRPndSLDIbE22mb743KFJpY4WRvDLoSUc0zTXu5yLv8lQ+8301KaBatCFaHCbEG7z4AWIv4VQEao5bu/qK6xnXwEAUmwGHddZky74A== erikberg_ecdsa"

%packages
@^workstation-product-environment
#@^sway-desktop-environment
@swaywm
#@swaywm-extended
#sway-config-fedora

-libreoffice-calc
-unoconv

-nautilus
-gnome-classic-session
-gnome-classic-session-xsession

-firefox

bash-completion
bsdtar
git-core
python3-pip
Thunar

rpmfusion-free-release
rpmfusion-nonfree-release

%end

%pre --interpreter=/usr/bin/bash
source /etc/os-release
cat << EOF > /tmp/rpmfusion.repo
repo --name=rpmfusion-free            --baseurl=http://download1.rpmfusion.org/free/fedora/releases/${VERSION_ID}/Everything/x86_64/os/
repo --name=rpmfusion-free-updates    --baseurl=http://download1.rpmfusion.org/free/fedora/updates/${VERSION_ID}/x86_64/
repo --name=rpmfusion-nonfree         --baseurl=http://download1.rpmfusion.org/nonfree/fedora/releases/${VERSION_ID}/Everything/x86_64/os/
repo --name=rpmfusion-nonfree-updates --baseurl=http://download1.rpmfusion.org/nonfree/fedora/updates/${VERSION_ID}/x86_64/
EOF


declare -A uuid_host=(
  [4c4c4544-0051-3810-8036-b9c04f5a5831]="lee"
  [30be1077-acee-47dc-ba5f-785287a8684c]="lizzie"
)

declare -A host_disks=(
  [lee]="/dev/disk/by-path/00.0-sas-exp0x500056b36789abff-phy10-lun-0"
  [lizzie]="/dev/disk/by-path/pci-0000:00:0e.0-pci-10000:e1:00.0-nvme-1 /dev/disk/by-path/pci-0000:00:0e.0-pci-10000:e2:00.0-nvme-1 /dev/disk/by-path/pci-0000:00:0e.0-pci-10000:e2:00.0-nvme-1-part1"
)

host="${uuid_host[$(dmidecode -s system-uuid)]:-unknown}"
disks=(${host_disks[$host]})
disk_count=$(( ${#disks[@]} - 1))
clearpart_count=$disk_count

if grep -qw inst.keephome /proc/cmdline; then
  keephome=1
  ((clearpart_count -= 1)) # If we're keeping home, we keed the partition layout on that disk
fi

echo "bootloader --append=\"mitigations=off\"" > /tmp/partitioning.ks
case "$host" in
  lee)
    cat << EOF >> /tmp/partitioning.ks
ignoredisk --only-use=${disks[0]}
clearpart --drives=${disks[0]} --all --initlabel
autopart
EOF
  lizzie)
    (IFS=','; echo "ignoredisk --only-use=${disks[*]:0:${disk_count}}" >> /tmp/partitioning.ks)
    (IFS=','; echo "clearpart --drives=${disks[*]:0:${clearpart_count}} --all --initlabel" >> /tmp/partitioning.ks)

    if [ -d /sys/firmware/efi ]; then
      echo "part /boot/efi --ondisk=${disks[0]} --fstype=\"efi\" --size=600 --label=uefi--fsoptions=\"umask=0077,shortname=winnt\"" >> /tmp/partitioning.ks
    else
      echo "part biosboot --ondisk=${disks[0]} --fstype=\"biosboot\" --size=1" >> /tmp/partitioning.ks
    fi

    cat << EOF >> /tmp/partitioning.ks
part /boot --ondisk=${disks[0]} --fstype="ext4" --size=1024 --label=boot --fsoptions="defaults,discard"
part /     --ondisk=${disks[0]} --fstype="xfs"  --grow      --label=root --fsoptions="defaults,discard,noatime"
EOF
    if (( keephome )); then
      echo "part /home --onpart=${disks[2]} --fstype=\"xfs\" --grow --label=home --fsoptions=\"defaults,discard,noatime\" --noformat >> /tmp/partitioning.ks
    else
      echo "part /home --ondisk=${disks[1]} --fstype=\"xfs\" --grow --label=home --fsoptions=\"defaults,discard,noatime\"" >> /tmp/partitioning.ks
    fi
    ;;
  *)
    cat << EOF > /tmp/partitioning.ks
autopart
clearpart --drives=nvme0n1|sda|vda --all --initlabel
EOF
    ;;
esac

%end

%include /tmp/rpmfusion.repo
%include /tmp/partitioning.ks

%post --interpreter=/usr/bin/bash --log=/root/ks-post.log
chage -d 0 erikberg
if ! grep -qw inst.keephome /proc/cmdline; then
  su - erikberg -c 'git clone --bare https://github.com/eb4x/dotfiles.git $HOME/.dotfiles'
  su - erikberg -c 'rm $HOME/.bashrc $HOME/.bash_profile'
  su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout'
  su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME config --local status.showUntrackedFiles no'
  su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME config --local user.email github@slipsprogrammor.no'
  su - erikberg -c 'restorecon -R $HOME'
fi
%end

# Completion methods
#halt  # <- default
#poweroff
reboot
#shutdown
