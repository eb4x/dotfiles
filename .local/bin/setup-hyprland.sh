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

  # GitPython >= 3.1.47 (fedpkg's git backend) reads core.bare from the shared
  # config and then refuses `git status` in linked worktrees ("must be run in
  # a work tree"). Git's documented fix: keep core.bare in the bare repo's own
  # per-worktree config instead of the shared one.
  if [ "$(git --git-dir="$bare" config --get extensions.worktreeConfig || true)" != true ]; then
    git --git-dir="$bare" config extensions.worktreeConfig true
    git --git-dir="$bare" config --unset core.bare || true
    git --git-dir="$bare" config --worktree core.bare true
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

# The mock configs that add the Copr repo are dotfiles, not generated here:
#   ~/.config/mock/{fedora-rawhide,fedora-44}-x86_64-hyprland.cfg
# mock checks ~/.config/mock/ before /etc/mock/ for --root NAME; a relative
# include() inside still resolves against /etc/mock/. Site-wide tunings are
# in ~/.config/mock.cfg.
for name in fedora-rawhide-x86_64-hyprland fedora-44-x86_64-hyprland; do
  if [ ! -f "$HOME/.config/mock/$name.cfg" ]; then
    echo "warning: ~/.config/mock/$name.cfg missing -- check out the dotfiles repo" >&2
  fi
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
#   sudo dnf install copr-cli
#   copr-cli build ebbex/hyprland *.src.rpm --chroot fedora-rawhide-x86_64 --nowait
