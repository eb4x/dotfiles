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
bsdtar
git-core
python3-pip

%end

%post --interpreter=/usr/bin/bash --log=/root/ks-post.log
# The GitHub CLI doubles as git's credential helper (see ~/.gitconfig).
cat << 'EOF' > /etc/yum.repos.d/gh-cli.repo
[gh-cli]
name=packages for the GitHub CLI
baseurl=https://cli.github.com/packages/rpm
enabled=1
gpgcheck=1
gpgkey=https://cli.github.com/packages/githubcli-archive-keyring.asc
EOF
rpm --import https://cli.github.com/packages/githubcli-archive-keyring.asc
dnf install -y gh

chage -d 0 erikberg
# A bare clone sets no fetch refspec, so there are no remote-tracking refs;
# without them status never shows ahead/behind, and push needs explicit args.
su - erikberg -c 'git clone --bare \
  -c remote.origin.fetch="+refs/heads/*:refs/remotes/origin/*" \
  -c branch.main.remote=origin \
  -c branch.main.merge=refs/heads/main \
  -c status.showUntrackedFiles=no \
  -c user.email=github@slipsprogrammor.no \
  https://github.com/eb4x/dotfiles.git $HOME/.dotfiles'
su - erikberg -c 'rm $HOME/.bashrc $HOME/.bash_profile'
su - erikberg -c 'git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout'
su - erikberg -c 'restorecon -R $HOME'
%end

# Completion methods
#halt  # <- default
#poweroff
reboot
#shutdown
