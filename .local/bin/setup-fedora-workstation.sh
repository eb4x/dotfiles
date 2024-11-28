#!/usr/bin/env bash
set -euo pipefail

#
# This is not idempotent, and ideally runs just once after installation.
#

echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
sudo chmod 0440 /etc/sudoers.d/$USER

source /etc/os-release

shopt -s nullglob; for repofile in /etc/yum.repos.d/_copr*; do
  sudo rm "${repofile}"
done; shopt -u nullglob

# Needed for `dnf config-manager and versionlock`
sudo dnf install -y \
  dnf-utils \
  dnf-plugin-versionlock

if [ ! -f /etc/yum.repos.d/hashicorp.repo ]; then
  if (( VERSION_ID >= 41 )); then
    sudo dnf config-manager addrepo --from-repofile https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
  else
    sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
  fi
fi

# Install rpmfusion
if [ ! -f /etc/yum.repos.d/rpmfusion-free.repo ]; then
  sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${VERSION_ID}.noarch.rpm
fi
if [ ! -f /etc/yum.repos.d/rpmfusion-nonfree.repo ]; then
  sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${VERSION_ID}.noarch.rpm
fi

if [[ $(hostname) != "heiress" && $(hostname) != "waitress" ]]; then
  sudo dnf remove -y firefox firefox-langpacks
fi

sudo dnf upgrade -y
sudo dnf install -y \
  htop iftop iotop \
  flatpak \
  mpv \
  neovim \
  podman podman-docker skopeo \
  python3-pip \
  sshfs \
  Thunar \
  tmux \
  v4l-utils v4l2loopback \
  virt-manager virt-install

# Get the real stuff (in case ffmpeg-free is installed)
sudo dnf install -y --allowerasing \
  ffmpeg

if ! groups $USER | grep -q libvirt; then
  sudo usermod -aG libvirt $USER
fi

if [ -f /etc/yum.repos.d/hashicorp.repo ]; then
  sudo dnf install -y \
    libvirt-devel \
    packer \
    vagrant

  if [ ! -d $HOME/.vagrant.d/gems/*/gems/vagrant-libvirt-* ]; then
    vagrant plugin install vagrant-libvirt
  fi
fi

# Check for Intel VGA, and prep for vaapi
if lsmod | grep -q i915; then
  sudo dnf install -y \
    igt-gpu-tools \
    intel-media-driver \
    libva-utils
fi

sudo touch /etc/containers/nodocker

flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install -y --user flathub com.mattermost.Desktop
flatpak install -y --user flathub com.slack.Slack
flatpak install -y --user flathub org.ghidra_sre.Ghidra
flatpak install -y --user flathub org.gnome.Evolution
flatpak install -y --user flathub us.zoom.Zoom

if [[ $(hostname) != "heiress" && $(hostname) != "waitress" ]]; then
  flatpak install -y --user flathub com.google.Chrome
  flatpak install -y --user flathub com.obsproject.Studio
  flatpak install -y --user flathub com.valvesoftware.Steam
  flatpak install -y --user flathub org.mozilla.firefox
  flatpak install -y --user flathub org.videolan.VLC
fi

flatpak install -y --user flathub com.jetbrains.CLion
flatpak install -y --user flathub com.jetbrains.GoLand
flatpak install -y --user flathub com.jetbrains.RubyMine
flatpak install -y --user flathub com.jetbrains.PyCharm-Professional
flatpak override --user --filesystem=/run/user/${UID}/podman/podman.sock com.jetbrains.PyCharm-Professional

# As long as we're administering EL8, there's no point in running newer ansible-core
pip install --upgrade --user pip
pip install --user 'ansible-core<2.17' sshuttle

sshuttle --sudoers-no-modify | \
  grep -v -E '^\s*$|^#' | \
  sed -E 's/SSHUTTLE\w+/SSHUTTLE/g' | \
  sudo tee /etc/sudoers.d/sshuttle.conf > /dev/null

# Find all these gsettings by using
# `dconf watch /`
# and do the actual change you want

gsettings set org.gnome.desktop.calendar show-weekdate true               # Week numbers in calendar
gsettings set org.gnome.desktop.interface clock-show-date false           # Use the calendar if you're unsure of the date
gsettings set org.gnome.desktop.interface clock-format '24h'              # 24-hour clock
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'      # Dark desktop
gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled # Disable touchpad
gsettings set org.gnome.desktop.sound event-sounds false                  # Disable bell sounds

gsettings set org.gtk.Settings.FileChooser clock-format '24h'

# Enable fractional scaling
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"

# Set pinned apps in dash/dock
gsettings set org.gnome.shell favorite-apps "['com.google.Chrome.desktop', 'org.gnome.Evolution.desktop', 'org.gnome.Ptyxis.desktop', 'thunar.desktop']"

# Configure virt-manager
gsettings set org.virt-manager.virt-manager xmleditor-enabled true
gsettings set org.virt-manager.virt-manager.stats enable-cpu-poll true
gsettings set org.virt-manager.virt-manager.stats enable-disk-poll true
gsettings set org.virt-manager.virt-manager.stats enable-net-poll true
gsettings set org.virt-manager.virt-manager.stats enable-memory-poll true
gsettings set org.virt-manager.virt-manager.vmlist-fields cpu-usage true
gsettings set org.virt-manager.virt-manager.vmlist-fields disk-usage true
gsettings set org.virt-manager.virt-manager.vmlist-fields network-traffic true
gsettings set org.virt-manager.virt-manager.vmlist-fields memory-usage true
gsettings set org.virt-manager.virt-manager.confirm forcepoweroff false

# Disable suspend on AC
if [[ $(hostname) != "heiress" && $(hostname) != "waitress" ]]; then
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
  sudo -u gdm dbus-run-session gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
fi

# Theme gnome-terminal (Fedora 41)
if (( VERSION_ID >= 41 )); then
  dconf write "/org/gnome/Ptyxis/Profiles/$(dconf read /org/gnome/Ptyxis/default-profile-uuid | tr -d \')/palette" "'Catppuccin Mocha'"
fi

if [ ! -f $HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf ]; then
  echo "Installing nerd fonts"
  mkdir -p $HOME/.local/share/fonts
  curl -sL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.tar.xz | tar -xJC $HOME/.local/share/fonts
fi

# Add additional routes for home-networking
if nmcli connection show skynet &> /dev/null; then
  # Use predictable mac-addresses for predictable IPs.
  sudo nmcli connection modify skynet 802-11-wireless.mac-address-randomization never

  if ! ip --json route show | jq -e 'any(.[]; .dst == "192.168.3.0/24")'; then
    sudo nmcli connection modify skynet +ipv4.routes "192.168.3.0/24 192.168.140.254"
  fi

  if ! ip --json route show | jq -e 'any(.[]; .dst == "192.168.4.0/24")'; then
    sudo nmcli connection modify skynet +ipv4.routes "192.168.4.0/24 192.168.140.254"
  fi
fi

sudo systemctl enable --now sshd.service
sudo rm /etc/sudoers.d/$USER

needs-restarting -r || systemctl reboot
