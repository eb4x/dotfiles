#!/usr/bin/env bash
set -euo pipefail

RPMS_DIR="$HOME/src/rpms"
GITHUB_BASE="ssh://git@github.com/copr-ebbex"
RPMFUSION_BASE="https://pkgs.rpmfusion.org/git/free"

# ffmpeg comes from RPM Fusion, not Fedora. Its dist-git uses `master` as the
# devel branch; our local branch is `rawhide` (so fedpkg infers the right
# %dist and the worktree layout matches every other package here). Watch
# upstream with `git fetch rpmfusion` + `git log rawhide..rpmfusion/master`,
# then `git rebase rpmfusion/master` in the rawhide worktree.
packages=(ffmpeg)
release_branches=(f44 f45)

mkdir -p "$RPMS_DIR"
for pkg in "${packages[@]}"; do
  bare="$RPMS_DIR/$pkg/.git"

  if [ ! -d "$bare" ]; then
    echo "Cloning $pkg..."
    git clone --bare "$GITHUB_BASE/$pkg.git" "$bare"
    git --git-dir="$bare" config user.email "fedora@slipsprogrammor.no"
    git --git-dir="$bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    printf '*.src.rpm\n*.rpm\nresults_*/\n' >> "$bare/info/exclude"
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

  if ! git --git-dir="$bare" remote get-url rpmfusion &>/dev/null; then
    git --git-dir="$bare" remote add rpmfusion "$RPMFUSION_BASE/$pkg.git"
    git --git-dir="$bare" config remote.rpmfusion.fetch '+refs/heads/*:refs/remotes/rpmfusion/*'
  fi
  git --git-dir="$bare" fetch rpmfusion

  if [ ! -d "$RPMS_DIR/$pkg/rawhide" ]; then
    git --git-dir="$bare" worktree add "$RPMS_DIR/$pkg/rawhide" rawhide
  fi

  for branch in "${release_branches[@]}"; do
    if [ ! -d "$RPMS_DIR/$pkg/$branch" ] && git --git-dir="$bare" rev-parse --verify "$branch" &>/dev/null; then
      git --git-dir="$bare" worktree add "$RPMS_DIR/$pkg/$branch" "$branch"
    fi
  done
done

# The mock configs that add the RPM Fusion free/nonfree repos and the Copr
# repo are dotfiles, not generated here:
#   ~/.config/mock/fedora-{rawhide,45,44}-x86_64-rpmfusion.cfg
for name in fedora-rawhide-x86_64-rpmfusion fedora-45-x86_64-rpmfusion fedora-44-x86_64-rpmfusion; do
  if [ ! -f "$HOME/.config/mock/$name.cfg" ]; then
    echo "warning: ~/.config/mock/$name.cfg missing -- check out the dotfiles repo" >&2
  fi
done

echo "Done."

# Building (Source URLs are direct ffmpeg.org URLs, so no rfpkg/lookaside needed):
#   cd ~/src/rpms/ffmpeg/rawhide
#   spectool -g -S ffmpeg.spec
#   fedpkg srpm
#   fedpkg mockbuild --root fedora-rawhide-x86_64-rpmfusion
#   copr-cli build ebbex/ffmpeg <exact>.src.rpm --chroot fedora-rawhide-x86_64 --nowait
