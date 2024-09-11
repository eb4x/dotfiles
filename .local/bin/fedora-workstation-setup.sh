#!/usr/bin/env bash

#
# This is not idempotent, and ideally runs just once after installation.
#

shopt -s nullglob; for repofile in /etc/yum.repos.d/_copr*; do
  sudo rm "${repofile}"
done; shopt -u nullglob
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo

sudo dnf erase -y firefox firefox-langpacks
sudo dnf upgrade -y
sudo dnf install -y libvirt virt-manager virt-install \
  htop \
  neovim \
  python3-pip \
  sshfs \
  vagrant

flatpak install flathub com.google.Chrome
flatpak install flathub com.mattermost.Desktop
flatpak install flathub com.slack.Slack
flatpak install flathub com.valvesoftware.Steam
flatpak install flathub org.ghidra_sre.Ghidra
flatpak install flathub org.gnome.Evolution
flatpak install flathub org.mozilla.firefox
flatpak install flathub org.videolan.VLC

flatpak install flathub com.jetbrains.CLion
flatpak install flathub com.jetbrains.GoLand
flatpak install flathub com.jetbrains.RubyMine
flatpak install flathub com.jetbrains.PyCharm-Professional
flatpak override --user --filesystem=/run/user/${UID}/podman/podman.sock com.jetbrains.PyCharm-Professional

# As long as we're administering EL8, there's no point in running newer ansible-core
pip install --upgrade --user pip
pip install --user 'ansible-core<2.17' sshuttle

# Disable touchpad
gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled

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
