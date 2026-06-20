#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/src"
if [ ! -d "$HOME/src/Hyprland" ]; then
  git clone --recursive https://github.com/hyprwm/Hyprland.git "$HOME/src/Hyprland"
fi

RPMS_DIR="$HOME/src/rpms"
CODEBERG_BASE="ssh://git@codeberg.org/ebbex"

packages=(
  hyprutils
  hyprlang
  hyprgraphics
  hyprcursor
  hyprland-protocols
  hyprwayland-scanner
  aquamarine
  hyprwire
  xdg-desktop-portal-hyprland
  hyprpaper
  hyprpicker
  hyprtoolkit
  hyprland
)

release_branches=(f43 f44)

mkdir -p "$RPMS_DIR"
for pkg in "${packages[@]}"; do
  bare="$RPMS_DIR/$pkg/.git"

  if [ ! -d "$bare" ]; then
    echo "Cloning $pkg..."
    git clone --bare "$CODEBERG_BASE/rpms-$pkg.git" "$bare"
    git --git-dir="$bare" config user.email "fedora@slipsprogrammor.no"
  else
    echo "Fetching $pkg..."
    git --git-dir="$bare" fetch origin
  fi

  if [ ! -d "$RPMS_DIR/$pkg/rawhide" ]; then
    git --git-dir="$bare" worktree add "$RPMS_DIR/$pkg/rawhide" rawhide
  fi

  for branch in "${release_branches[@]}"; do
    if [ ! -d "$RPMS_DIR/$pkg/$branch" ] && git --git-dir="$bare" rev-parse --verify "origin/$branch" &>/dev/null; then
      git --git-dir="$bare" worktree add "$RPMS_DIR/$pkg/$branch" "$branch"
    fi
  done
done

declare -A mock_includes=(
  [rawhide]="templates/fedora-rawhide.tpl"
  [44]="fedora-44-x86_64.cfg"
  [43]="fedora-43-x86_64.cfg"
)

for ver in "${!mock_includes[@]}"; do
  include="${mock_includes[$ver]}"
  if [[ "$ver" == "rawhide" ]]; then
    name="fedora-rawhide-x86_64-hyprland"
    baseurl_ver="fedora-rawhide"
  else
    name="fedora-${ver}-x86_64-hyprland"
    baseurl_ver="fedora-${ver}"
  fi

  sudo install -m 0644 /dev/stdin "/etc/mock/${name}.cfg" <<MOCK
config_opts['target_arch'] = 'x86_64'
config_opts['legal_host_arches'] = ('x86_64',)

include('${include}')

config_opts['dnf.conf'] += """
[copr:copr.fedorainfracloud.org:ebbex:hyprland]
name=Copr repo for hyprland owned by ebbex
baseurl=https://download.copr.fedorainfracloud.org/results/ebbex/hyprland/${baseurl_ver}-\$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/ebbex/hyprland/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
"""
MOCK
done

echo "Done."

# Usage:
#   sudo dnf copr enable ebbex/hyprland
#   sudo dnf install hyprland
#
# Building packages:
#   cd ~/src/rpms/<pkg>/rawhide
#   spectool -g -S <pkg>.spec                              # download sources
#   sha512sum *.tar.gz | awk '{print "SHA512 (" $2 ") = " $1}' > sources
#   fedpkg srpm                                            # build SRPM
#   fedpkg mockbuild --root fedora-rawhide-x86_64-hyprland # local build
#   fedpkg lint                                            # lint the spec
#   fedora-review -n <pkg> -m fedora-rawhide-x86_64-hyprland # full guidelines check
#
# Submitting to Copr:
#   copr-cli build ebbex/hyprland *.src.rpm --chroot fedora-rawhide-x86_64 --nowait
