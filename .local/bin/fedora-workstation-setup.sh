#!/usr/bin/env bash
set -euo pipefail

#
# This is not idempotent, and ideally runs just once after installation.
#

source /etc/os-release

shopt -s nullglob; for repofile in /etc/yum.repos.d/_copr*; do
  sudo rm "${repofile}"
done; shopt -u nullglob

# Needed for `dnf config-manager`
sudo dnf install -y dnf-utils

if [ ! -f /etc/yum.repos.d/hashicorp.repo ] && (( VERSION_ID < 41 )); then
  sudo dnf config-manager addrepo --from-repofile https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
fi

# Install rpmfusion
if [ ! -f /etc/yum.repos.d/rpmfusion-free.repo ]; then
  sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${VERSION_ID}.noarch.rpm
fi
if [ ! -f /etc/yum.repos.d/rpmfusion-nonfree.repo ]; then
  sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${VERSION_ID}.noarch.rpm
fi

sudo dnf remove -y firefox firefox-langpacks
sudo dnf upgrade -y
sudo dnf install -y \
  htop \
  mpv \
  neovim \
  podman podman-docker skopeo \
  python3-pip \
  sshfs \
  tmux \
  virt-manager virt-install

if [ -f /etc/yum.repos.d/hashicorp.repo ]; then
  sudo dnf install -y vagrant
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

flatpak install -y --user flathub com.google.Chrome
flatpak install -y --user flathub com.mattermost.Desktop
flatpak install -y --user flathub com.slack.Slack
flatpak install -y --user flathub com.valvesoftware.Steam
flatpak install -y --user flathub org.ghidra_sre.Ghidra
flatpak install -y --user flathub org.gnome.Evolution
flatpak install -y --user flathub org.mozilla.firefox
flatpak install -y --user flathub org.videolan.VLC

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

# Disable touchpad
gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled

# Disable suspend on AC
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
sudo -u gdm dbus-run-session gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'

# Theme gnome-terminal (Fedora 41)
if (( VERSION_ID >= 41 )); then
  dconf write "/org/gnome/Ptyxis/Profiles/$(dconf list /org/gnome/Ptyxis/Profiles/)palette" "'Catppuccin Mocha'"
fi

# Add additional routes for home-networking
if nmcli connection show skynet &> /dev/null; then
  if ! ip --json route show | jq -e 'any(.[]; .dst == "192.168.3.0/24")'; then
    sudo nmcli connection modify skynet +ipv4.routes "192.168.3.0/24 192.168.140.254"
  fi

  if ! ip --json route show | jq -e 'any(.[]; .dst == "192.168.4.0/24")'; then
    sudo nmcli connection modify skynet +ipv4.routes "192.168.4.0/24 192.168.140.254"
  fi
fi

sudo systemctl enable --now sshd.service

if needs-restarting -r; then
  sudo systemctl reboot
fi
