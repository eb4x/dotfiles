#!/usr/bin/env bash
set -euo pipefail

# Sets up ~/src/rpms (see CLAUDE.md there): host tooling, one bare repo per
# package with a worktree per branch, mock roots. Idempotent.
#
# Package entries: `name`, `name:fedora` or `name:rpmfusion`; the suffix adds
# that dist-git as a read-only `upstream` remote. Our branches sit on top of
# upstream's (rebase, never merge); the script warns when one has fallen
# behind.
#
# Not handled: bcachefs-tools (plain Fedora dist-git clone, no Copr).

RPMS_DIR="$HOME/src/rpms"
GITHUB_BASE="ssh://git@github.com/copr-ebbex"
FEDORA_BASE="https://src.fedoraproject.org/rpms"
RPMFUSION_BASE="https://pkgs.rpmfusion.org/git/free"

# Every package gets rawhide plus these. Missing on origin -> created from
# upstream's branch of the same name, else from rawhide.
release_branches=(f44 f45)

# --- Host tooling (SKIP_DEPS=1 to skip) ------------------------------------
if [ "${SKIP_DEPS:-}" != 1 ]; then
  sudo dnf install -y \
    copr-cli \
    fedora-review \
    fedpkg \
    git \
    jq curl \
    llvm lld \
    mock \
    rpmdevtools \
    rpmlint

  if ! groups "$USER" | grep -qw mock; then
    sudo usermod -aG mock "$USER"
    echo "warning: added $USER to the mock group -- log out and in again before building" >&2
  fi

  # overlayfs base dir for mock, see ~/.config/mock.cfg
  sudo install -d -o root -g mock -m 2775 /var/lib/mock/overlayfs
fi

# --- Packages by Copr project, in build order ------------------------------
# All projects have the chroots fedora-<rel>-x86_64, <rel> = rawhide or a
# release number from release_branches.

# ebbex/ffmpeg: RPM Fusion rebuild; our `rawhide` is upstream's `master`.
# Mock roots: fedora-<rel>-x86_64-ffmpeg (adds RPM Fusion free for the
# build deps).
ffmpeg=(
  ffmpeg:rpmfusion
)

# ebbex/gnome. No Copr deps: plain fedora-<rel>-x86_64 mock roots.
gnome=(
  loupe:fedora
  glide-rs
)

# ebbex/hyprland. Mock roots: fedora-<rel>-x86_64-hyprland.
hyprland=(
  hyprutils:fedora
  hyprlang:fedora
  hyprgraphics:fedora
  hyprcursor:fedora
  hyprland-protocols:fedora
  hyprwayland-scanner:fedora
  aquamarine:fedora
  hyprwire
  xdg-desktop-portal-hyprland:fedora
  hyprpaper:fedora
  hyprpicker:fedora
  hyprtoolkit
  hyprland:fedora
)

# ebbex/mingw: the ucrtarm64 (aarch64-w64-mingw32) clang/lld cross toolchain.
# Mock roots: fedora-<rel>-x86_64-mingw. Each level must be published in the
# Copr before the next builds:
#   filesystem -> llvm(bootstrap) -> headers(bootstrap) -> crt -> compiler-rt
#   -> {libcxx, winpthreads} -> llvm(full) + headers(full) -> probe
# Bootstrap passes: `fedpkg mockbuild --with bootstrap`. :fedora entries are
# forks of Fedora's packages; see CLAUDE.md for their release-branch policy.
mingw=(
  mingw-filesystem:fedora
  mingw-llvm
  mingw-headers:fedora
  mingw-crt:fedora
  mingw-compiler-rt
  mingw-libcxx
  mingw-winpthreads:fedora
  mingw-ucrtarm64-probe
)

# The qemu-ga ladder on top, in dependency order. Same fork rules.
mingw_ladder=(
  mingw-zlib:fedora
  mingw-libffi:fedora
  mingw-win-iconv:fedora
  mingw-pcre2:fedora
  mingw-gettext:fedora
  mingw-glib2:fedora
)

# ebbex/musl: LLVM runtimes against musl + musl-clang++ drivers. Mock roots:
# fedora-<rel>-x86_64-musl. musl-llvm needs musl-libcxx published first.
musl=(
  musl-aarch64
  musl-libcxx
  musl-llvm
)

# --- Repo setup ------------------------------------------------------------

setup_repo() {
  local entry=$1
  local pkg=${entry%%:*}
  local upstream=""
  [ "$entry" != "$pkg" ] && upstream=${entry#*:}

  local bare="$RPMS_DIR/$pkg/.git"

  if [ ! -d "$bare" ]; then
    echo "Cloning $pkg..."
    git clone --bare "$GITHUB_BASE/$pkg.git" "$bare"
  else
    echo "Fetching $pkg..."
    git --git-dir="$bare" fetch origin
  fi

  git --git-dir="$bare" config user.email "fedora@slipsprogrammor.no"
  # `clone --bare` sets no fetch refspec, so origin/* would never appear.
  git --git-dir="$bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

  # Build output out of git status; local-only so it can't conflict on rebase.
  for pattern in '*.src.rpm' '*.rpm' 'results_*/'; do
    grep -qxF "$pattern" "$bare/info/exclude" 2>/dev/null || echo "$pattern" >> "$bare/info/exclude"
  done

  # GitPython >= 3.1.47 (fedpkg's git backend) reads core.bare from the shared
  # config and then refuses `git status` in linked worktrees ("must be run in
  # a work tree"). Git's documented fix: keep core.bare in the bare repo's own
  # per-worktree config instead of the shared one.
  if [ "$(git --git-dir="$bare" config --get extensions.worktreeConfig || true)" != true ]; then
    git --git-dir="$bare" config extensions.worktreeConfig true
    git --git-dir="$bare" config --unset core.bare || true
    git --git-dir="$bare" config --worktree core.bare true
  fi

  # Read-only `upstream` remote. Never push to it. devel = its rawhide branch.
  local devel=""
  if [ -n "$upstream" ]; then
    local url
    case "$upstream" in
      fedora)    url="$FEDORA_BASE/$pkg.git";    devel=rawhide ;;
      rpmfusion) url="$RPMFUSION_BASE/$pkg.git"; devel=master ;;
      *) echo "error: $pkg: unknown upstream '$upstream'" >&2; return 1 ;;
    esac
    if ! git --git-dir="$bare" remote get-url upstream &>/dev/null; then
      # TODO: drop the rename once every checkout has run this (2026-09).
      if git --git-dir="$bare" remote get-url "$upstream" &>/dev/null; then
        git --git-dir="$bare" remote rename "$upstream" upstream
      else
        git --git-dir="$bare" remote add upstream "$url"
      fi
    fi
    git --git-dir="$bare" fetch upstream
  fi

  add_worktree "$bare" "$RPMS_DIR/$pkg/rawhide" rawhide "$devel"
  check_behind "$bare" "$pkg" rawhide "$devel"
  for branch in "${release_branches[@]}"; do
    add_worktree "$bare" "$RPMS_DIR/$pkg/$branch" "$branch" "${devel:+$branch}"
    check_behind "$bare" "$pkg" "$branch" "${devel:+$branch}"
  done
}

# add_worktree <bare> <dir> <branch> [<upstream-branch>]: local branch, else
# origin/<branch>, else a new branch from upstream/<upstream-branch>, else
# from rawhide.
add_worktree() {
  local bare=$1 dir=$2 branch=$3 ub=${4:-}
  if [ -d "$dir" ]; then
    if ! git --git-dir="$bare" worktree list --porcelain | grep -qxF "worktree $dir"; then
      echo "warning: $dir exists but is not a registered worktree -- move it aside and re-run" >&2
    fi
    return
  fi
  if has_ref "$bare" "refs/heads/$branch" || has_ref "$bare" "refs/remotes/origin/$branch"; then
    git --git-dir="$bare" worktree add "$dir" "$branch"
  elif [ -n "$ub" ] && has_ref "$bare" "refs/remotes/upstream/$ub"; then
    echo "Creating $branch from upstream/$ub in $dir (not on origin yet)"
    git --git-dir="$bare" worktree add --no-track -b "$branch" "$dir" "upstream/$ub"
  else
    echo "Creating $branch from rawhide in $dir (not on origin yet)"
    git --git-dir="$bare" worktree add --no-track -b "$branch" "$dir" rawhide
  fi
}

# check_behind <bare> <pkg> <branch> [<upstream-branch>]: warn when upstream
# has commits our branch lacks (time to rebase).
check_behind() {
  local bare=$1 pkg=$2 branch=$3 ub=${4:-}
  [ -n "$ub" ] && has_ref "$bare" "refs/remotes/upstream/$ub" || return 0
  local n
  n=$(git --git-dir="$bare" rev-list --count "$branch..upstream/$ub")
  if [ "$n" != 0 ]; then
    echo "warning: $pkg/$branch is $n commit(s) behind upstream/$ub -- rebase it" >&2
  fi
}

has_ref() {
  git --git-dir="$1" rev-parse --verify --quiet "$2" >/dev/null
}

mkdir -p "$RPMS_DIR"
for entry in "${ffmpeg[@]}" "${gnome[@]}" "${hyprland[@]}" "${mingw[@]}" "${mingw_ladder[@]}" "${musl[@]}"; do
  setup_repo "$entry"
done

# Upstream Hyprland checkout, for reading the build system when bumping specs.
if [ ! -d "$HOME/src/Hyprland" ]; then
  git clone --recursive https://github.com/hyprwm/Hyprland.git "$HOME/src/Hyprland"
fi

# --- Mock roots ------------------------------------------------------------
# One tracked template per stack (~/.config/mock/templates/<stack>.tpl) reads
# the release from the root name; each root is a symlink to it. See MOCK.md.
for stack in ffmpeg hyprland mingw musl; do
  tpl="$HOME/.config/mock/templates/$stack.tpl"
  if [ ! -f "$tpl" ]; then
    echo "warning: $tpl missing -- check out the dotfiles repo" >&2
    continue
  fi
  for rel in rawhide "${release_branches[@]#f}"; do
    ln -sfn "templates/$stack.tpl" "$HOME/.config/mock/fedora-$rel-x86_64-$stack.cfg"
  done
done

echo "Done."

# Using the Coprs:
#   sudo dnf copr enable ebbex/ffmpeg   && sudo dnf install --allowerasing ffmpeg
#   sudo dnf copr enable ebbex/gnome    && sudo dnf install loupe glide-rs
#   sudo dnf copr enable ebbex/hyprland && sudo dnf install hyprland
#   sudo dnf copr enable ebbex/mingw    && sudo dnf install ucrtarm64-probe   # whole stack
#   sudo dnf copr enable ebbex/musl     && sudo dnf install musl-libcxx musl-llvm
#
# Cross-compiling for Windows ARM64:
#   aarch64-w64-mingw32-clang   hello.c   -o hello.exe
#   aarch64-w64-mingw32-clang++ thing.cpp -o thing.exe
#
# Building (cd into the right worktree first):
#   cd ~/src/rpms/<pkg>/rawhide
#   spectool -g -S <pkg>.spec
#   sha512sum *.tar.gz | awk '{print "SHA512 (" $2 ") = " $1}' > sources
#   fedpkg srpm
#   fedpkg mockbuild --root fedora-<rel>-x86_64-<stack>
#   fedpkg lint
#   fedora-review -n <pkg> -m fedora-<rel>-x86_64-<stack>
#
# Submitting (exact SRPM name, not a glob):
#   copr-cli build ebbex/<project> <exact>.src.rpm --chroot <chroot> --nowait
#
#   branch    SRPM suffix   --chroot
#   rawhide   .fc<N+1>      fedora-rawhide-x86_64
#   f<N>      .fc<N>        fedora-<N>-x86_64
