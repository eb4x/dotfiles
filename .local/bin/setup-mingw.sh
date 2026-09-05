#!/usr/bin/env bash
set -euo pipefail

RPMS_DIR="$HOME/src/rpms"
GITHUB_BASE="ssh://git@github.com/copr-ebbex"
FEDORA_BASE="https://src.fedoraproject.org/rpms"

# Forks of Fedora's own packages, with a read-only dist-git remote to watch
# for upstream changes. Their f44 branches sit on Fedora 44's dist-git
# history with our changes re-applied, never merged from rawhide, so the
# Copr can't shadow a real Fedora 44 update.
fedora_forks=(
  mingw-filesystem
  mingw-headers
  mingw-crt
  mingw-winpthreads
)

# LLVM based MinGW cross toolchain: clang drivers for win32/win64/ARM64, plus
# the full ucrtarm64 stack (tools, CRT, runtimes) for aarch64-w64-mingw32,
# where GNU binutils can't do PE/COFF. Build order: filesystem
# -> llvm(bootstrap) -> headers(bootstrap) -> crt -> compiler-rt
# -> {libcxx, winpthreads} -> llvm(full)+headers(full) -> probe. Each package
# must be published to Copr before proceeding with the next package(s) in the
# chain.
packages=(
  "${fedora_forks[@]}"
  mingw-llvm
  mingw-compiler-rt
  mingw-libcxx
  mingw-ucrtarm64-probe
)

release_branches=(f44)

mkdir -p "$RPMS_DIR"
for pkg in "${packages[@]}"; do
  bare="$RPMS_DIR/$pkg/.git"

  if [ ! -d "$bare" ]; then
    echo "Cloning $pkg..."
    git clone --bare "$GITHUB_BASE/$pkg.git" "$bare"
    git --git-dir="$bare" config user.email "fedora@slipsprogrammor.no"
    git --git-dir="$bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
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
    if [ ! -d "$RPMS_DIR/$pkg/$branch" ] && git --git-dir="$bare" rev-parse --verify "$branch" &>/dev/null; then
      git --git-dir="$bare" worktree add "$RPMS_DIR/$pkg/$branch" "$branch"
    fi
  done
done

for pkg in "${fedora_forks[@]}"; do
  bare="$RPMS_DIR/$pkg/.git"

  if ! git --git-dir="$bare" remote get-url fedora &>/dev/null; then
    git --git-dir="$bare" remote add fedora "$FEDORA_BASE/$pkg.git"
  fi
  git --git-dir="$bare" fetch fedora
done

# The mock configs that add the Copr repo are dotfiles, not generated here:
#   ~/.config/mock/{fedora-rawhide,fedora-44}-x86_64-mingw.cfg
# mock checks ~/.config/mock/ before /etc/mock/ for --root NAME; a relative
# include() inside still resolves against /etc/mock/. Site-wide tunings are
# in ~/.config/mock.cfg.
for name in fedora-rawhide-x86_64-mingw fedora-44-x86_64-mingw; do
  if [ ! -f "$HOME/.config/mock/$name.cfg" ]; then
    echo "warning: ~/.config/mock/$name.cfg missing -- check out the dotfiles repo" >&2
  fi
done

echo "Done."

# Usage:
#   sudo dnf copr enable ebbex/mingw
#   sudo dnf install ucrtarm64-clang ucrtarm64-libcxx ucrtarm64-winpthreads
#   # or the one-command install-test of the whole stack:
#   sudo dnf install ucrtarm64-probe
#
# Cross-compiling (drivers carry all runtime flags; no extra options needed):
#   aarch64-w64-mingw32-clang   hello.c   -o hello.exe
#   aarch64-w64-mingw32-clang++ thing.cpp -o thing.exe
#
# Building packages (in build order, see above):
#   cd ~/src/rpms/<pkg>/rawhide
#   fedpkg srpm
#   fedpkg mockbuild --root fedora-rawhide-x86_64-mingw
#   fedpkg lint
#   copr-cli build ebbex/mingw <exact>.src.rpm --chroot fedora-rawhide-x86_64
