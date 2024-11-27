#graphical --non-interactive
#text --non-interactive
#cmdline

eula --agreed

# Keyboard layouts
keyboard --vckeymap=no --xlayouts='no'
# System language
lang en_US.UTF-8

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
@^minimal-environment

bash-completion
git-core
python3-pip

%end

%post --interpreter=/usr/bin/bash --log=/root/ks-post.log
chage -d 0 erikberg
su - erikberg -c 'git clone --bare https://github.com/eb4x/dotfiles.git $HOME/.dotfiles'
su - erikberg -c 'rm $HOME/.bashrc $HOME/.bash_profile'
su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout'
su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME config --local status.showUntrackedFiles no'
su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME config --local user.email github@slipsprogrammor.no'
su - erikberg -c 'restorecon -R $HOME'
%end

# Completion methods
#halt  # <- default
#poweroff
reboot
#shutdown
