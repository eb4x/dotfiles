#graphical --non-interactive
#text --non-interactive
#cmdline

# Keyboard layouts
keyboard --vckeymap=no --xlayouts='no'
# System language
lang en_US.UTF-8

repo --name=rpmfusion-free --mirrorlist="https://mirrors.rpmfusion.org/mirrorlist?repo=free-fedora-40&arch=x86_64"
repo --name=rpmfusion-free-updates --mirrorlist="https://mirrors.rpmfusion.org/mirrorlist?repo=free-fedora-updates-released-40&arch=x86_64"
repo --name=rpmfusion-nonfree --mirrorlist="https://mirrors.rpmfusion.org/mirrorlist?repo=nonfree-fedora-40&arch=x86_64"
repo --name=rpmfusion-nonfree-updates --mirrorlist="https://mirrors.rpmfusion.org/mirrorlist?repo=nonfree-fedora-updates-released-40&arch=x86_64"

# Run the Setup Agent on first boot
firstboot --disable

#ignoredisk --only-use=nvme0n1
autopart

# Partition clearing information
clearpart --all --initlabel --drives=nvme0n1|sda|vda

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

-unoconv
-libreoffice-filters
-libreoffice-calc

-firefox

bash-completion
git-core
python3-pip
Thunar

%end

%post --interpreter=/usr/bin/bash --log=/root/ks-post.log
chage -d 0 erikberg
su - erikberg -c 'git clone --bare https://github.com/eb4x/dotfiles.git $HOME/.dotfiles'
su - erikberg -c 'rm $HOME/.bashrc $HOME/.bash_profile'
su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout'
su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME config --local status.showUntrackedFiles no'
%end

# Completion methods
#halt  # <- default
#poweroff
reboot
#shutdown
