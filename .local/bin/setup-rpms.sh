#!/usr/bin/env bash
set -euo pipefail

# Sets up ~/src/rpms (see CLAUDE.md there): host tooling, one bare repo per
# package with a worktree per branch, the source trees we patch in ~/src,
# the kernel tree in ~/src/linux, mock roots. Idempotent.

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
    curl \
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

# --- Helpers ---------------------------------------------------------------

# setup_bare_repo <bare> <email> <upstream-url> <origin-url>: a bare repo
# with a read-only `upstream` and our `origin` (either URL may be empty),
# fetched. origin is pruned; upstream never is: it keeps the history of
# branches deleted from origin.
setup_bare_repo() {
  local bare=$1 email=$2 upstream=$3 origin=$4
  [ -d "$bare" ] || git init -q --bare "$bare"
  git --git-dir="$bare" config user.email "$email"
  echo "Fetching ${bare%/.git}..."
  if [ -n "$upstream" ]; then
    set_remote "$bare" upstream "$upstream"
    git --git-dir="$bare" fetch upstream
  fi
  if [ -n "$origin" ]; then
    set_remote "$bare" origin "$origin"
    git --git-dir="$bare" fetch --prune origin
  fi
}

# set_remote <bare> <name> <url>: add it, or point it at <url>.
set_remote() {
  local bare=$1 name=$2 url=$3
  git --git-dir="$bare" remote set-url "$name" "$url" 2>/dev/null ||
    git --git-dir="$bare" remote add "$name" "$url"
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
  if has_ref "$bare" "refs/heads/$branch"; then
    git --git-dir="$bare" worktree add "$dir" "$branch"
  elif has_ref "$bare" "refs/remotes/origin/$branch"; then
    git --git-dir="$bare" worktree add --track -b "$branch" "$dir" "origin/$branch"
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
  local bare=$1 ref=$2
  git --git-dir="$bare" rev-parse --verify --quiet "$ref" >/dev/null
}

# --- Packages by Copr project, in build order ------------------------------
# All projects have the chroots fedora-<rel>-x86_64, <rel> = rawhide or a
# release number from release_branches.
# Entries: `name`, `name:fedora` or `name:rpmfusion`; the suffix adds that
# dist-git as a read-only `upstream` remote. Our branches sit on top of
# upstream's (rebase, never merge); the script warns when one has fallen
# behind.

# ebbex/ffmpeg: RPM Fusion rebuild; our `rawhide` is upstream's `master`.
# Mock roots: fedora-<rel>-x86_64-ffmpeg (adds RPM Fusion free for the
# build deps).
ffmpeg=(
  ffmpeg:rpmfusion
)

# ebbex/fwupd: Fedora's fwupd plus our patch series (intel-gsc Arc DG2 / A770,
# genesys), developed in ~/src/fwupd. No Copr deps: plain fedora-<rel>-x86_64
# mock roots.
fwupd=(
  fwupd:fedora
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

# ebbex/kernel: Fedora's kernel, plus igt-gpu-tools (gputop) for the Arc
# A770 / xe work, and bcachefs-tools (ngompa's) built with dkms for
# dkms-bcachefs: the Copr chroots set `--with dkms`, local builds pass it to
# fedpkg mockbuild. No Copr deps: plain fedora-<rel>-x86_64 mock roots.
kernel=(
  bcachefs-tools:fedora
  igt-gpu-tools:fedora
  kernel:fedora
)

# ebbex/lutris: Fedora's lutris, developed in ~/src/lutris. No Copr deps:
# plain fedora-<rel>-x86_64 mock roots.
lutris=(
  lutris:fedora
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

# ebbex/qemu: virtualization stack extras. No Copr deps: plain
# fedora-<rel>-x86_64 mock roots. edk2 keeps OVMF IA32 alive (revert of the
# upstream removal + CpuDxe fix, `ia32` branch of github.com/eb4x/edk2); it
# also carries an f43 branch beyond release_branches.
qemu=(
  edk2:fedora
)

RPMS_DIR="$HOME/src/rpms"

setup_package() {
  local entry=$1
  local pkg=${entry%%:*}
  local bare="$RPMS_DIR/$pkg/.git"

  # Read-only `upstream` remote. Never push to it. devel = its rawhide branch.
  local url="" devel=""
  case "$entry" in
    *:fedora)    url="https://src.fedoraproject.org/rpms/$pkg.git";  devel=rawhide ;;
    *:rpmfusion) url="https://pkgs.rpmfusion.org/git/free/$pkg.git"; devel=master ;;
    *:*) echo "error: $pkg: unknown upstream '${entry#*:}'" >&2; return 1 ;;
  esac
  setup_bare_repo "$bare" fedora@slipsprogrammor.no "$url" "https://github.com/copr-ebbex/$pkg.git"

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

  add_worktree "$bare" "$RPMS_DIR/$pkg/rawhide" rawhide "$devel"
  check_behind "$bare" "$pkg" rawhide "$devel"
  for branch in "${release_branches[@]}"; do
    add_worktree "$bare" "$RPMS_DIR/$pkg/$branch" "$branch" "${devel:+$branch}"
    check_behind "$bare" "$pkg" "$branch" "${devel:+$branch}"
  done
}

mkdir -p "$RPMS_DIR"
for entry in "${ffmpeg[@]}" "${fwupd[@]}" "${gnome[@]}" "${hyprland[@]}" "${kernel[@]}" "${lutris[@]}" "${mingw[@]}" "${mingw_ladder[@]}" "${musl[@]}" "${qemu[@]}"; do
  setup_package "$entry"
done

# --- Source trees ----------------------------------------------------------
# Upstream projects we patch, ~/src/<name>: a bare repo in .git with
# worktrees beside it, like the package repos. Entries: `name branch email
# upstream-url [origin-url]`, origin being our fork, if any. Only <branch> is
# set up and kept current (fast-forward only); topic-branch worktrees are left
# alone.
src_trees=(
  "fwupd main fwupd@slipsprogrammor.no https://github.com/fwupd/fwupd.git https://github.com/eb4x/fwupd.git"
  "glide main github@slipsprogrammor.no https://github.com/philn/glide.git https://github.com/eb4x/glide.git"
  "igt-gpu-tools master gitlab@slipsprogrammor.no https://gitlab.freedesktop.org/drm/igt-gpu-tools.git"
  "loupe main fedora@slipsprogrammor.no https://gitlab.gnome.org/GNOME/loupe.git"
  "lutris master github@slipsprogrammor.no https://github.com/lutris/lutris.git https://github.com/eb4x/lutris.git"
)

setup_src_tree() {
  local name=$1 branch=$2 email=$3 upstream=$4 origin=${5:-}
  local bare="$HOME/src/$name/.git" dir="$HOME/src/$name/$branch"
  setup_bare_repo "$bare" "$email" "$upstream" "$origin"
  add_worktree "$bare" "$dir" "$branch" "$branch"
  git --git-dir="$bare" branch -q --set-upstream-to="upstream/$branch" "$branch"
  # Refuses on local commits or changes it would overwrite.
  git -C "$dir" merge -q --ff-only "upstream/$branch" ||
    echo "warning: $name/$branch can't be fast-forwarded to upstream/$branch" >&2
}

for entry in "${src_trees[@]}"; do
  # shellcheck disable=SC2086 # word-split on purpose
  setup_src_tree $entry
done

# --- Kernel source tree ----------------------------------------------------
# ~/src/linux is laid out like the package repos: a shallow bare repo in
# .git with the worktrees beside it. Per Fedora release it holds the upstream
# commit that the spec's Source0 tarball is made from (tag
# v<tarfile_release>, fetched with --depth 1) and one commit on top with
# Fedora's patch-<x.y>-redhat.patch, tagged with the Fedora NEVR. One
# worktree per Fedora release, named like the package repos' (~/src/linux/f44
# feeds ~/src/rpms/kernel/f44); f44 and f45 can share a tarball but carry
# different redhat patches.
# Local commits go above the NEVR tag and are exported into the spec's
# linux-kernel-test.patch. See "Kernel source tree" in CLAUDE.md.
LINUX_TREES="$HOME/src/linux"
LINUX_BARE="$LINUX_TREES/.git"

# setup_kernel_tree <fedora-release>, e.g. f44 or rawhide
setup_kernel_tree() {
  local fedora_release=$1
  local spec="$RPMS_DIR/kernel/$fedora_release/kernel.spec"
  local dir="$LINUX_TREES/$fedora_release"
  # Fedora release number for the NEVR; rawhide is one past the newest branch.
  local rel=${fedora_release#f}
  [ "$fedora_release" = rawhide ] && rel=$(( ${release_branches[-1]#f} + 1 ))

  local linux_release pv nevr
  linux_release=$(awk '$1 == "%define" && $2 == "tarfile_release" {print $3}' "$spec")
  pv=$(awk '$1 == "%define" && $2 == "patchversion" {print $3}' "$spec")
  nevr=$(rpmspec -q --srpm --define "dist .fc$rel" --define "fedora $rel" \
    --qf '%{name}-%{version}-%{release}\n' "$spec")
  local base="v$linux_release"

  # Upstream base. A git snapshot (7.3-rc3-313-g5dd1818b15d9) is fetched by
  # full sha from the torvalds tree; GitHub's API expands the abbreviation.
  # Anything else is a tag; the stable tree also carries the mainline tags.
  # A commit already here (e.g. via the xe branches) is only tagged: fetching
  # it with --depth 1 would mark it shallow and cut off the history behind it.
  if ! has_ref "$LINUX_BARE" "refs/tags/$base"; then
    local url sha
    if [[ $linux_release =~ -g([0-9a-f]+)$ ]]; then
      url=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
      sha=$(curl -fsS --max-time 30 --retry 3 -H 'Accept: application/vnd.github.sha' \
        "https://api.github.com/repos/torvalds/linux/commits/${BASH_REMATCH[1]}")
    else
      url=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
      sha=$(git ls-remote --exit-code "$url" "refs/tags/$base^{}" | cut -f1)
    fi
    if ! git --git-dir="$LINUX_BARE" cat-file -e "$sha^{commit}" 2>/dev/null; then
      echo "Fetching linux $base ($sha)..."
      git --git-dir="$LINUX_BARE" fetch -q --depth 1 "$url" "$sha"
    fi
    git --git-dir="$LINUX_BARE" tag "$base" "$sha"
  fi

  # Fedora commit: the redhat patch applied to the base in a scratch index,
  # as kernel.spec's %prep does, so no worktree is needed.
  if ! has_ref "$LINUX_BARE" "refs/tags/$nevr"; then
    echo "Committing $nevr (patch-$pv-redhat.patch on $base)..."
    local idx="$LINUX_BARE/nevr-index" tree
    GIT_INDEX_FILE=$idx git --git-dir="$LINUX_BARE" read-tree "$base^{tree}"
    GIT_INDEX_FILE=$idx git --git-dir="$LINUX_BARE" apply --cached --whitespace=nowarn \
      "$RPMS_DIR/kernel/$fedora_release/patch-$pv-redhat.patch"
    tree=$(GIT_INDEX_FILE=$idx git --git-dir="$LINUX_BARE" write-tree)
    rm "$idx"
    git --git-dir="$LINUX_BARE" tag "$nevr" "$(git --git-dir="$LINUX_BARE" commit-tree \
      --no-gpg-sign -p "$base^{commit}" -m "Fedora $nevr: patch-$pv-redhat.patch" "$tree")"
  fi

  has_ref "$LINUX_BARE" "refs/heads/$fedora_release" ||
    git --git-dir="$LINUX_BARE" branch "$fedora_release" "$nevr"
  add_worktree "$LINUX_BARE" "$dir" "$fedora_release"

  # Fedora moved to a new NEVR (new tarball or not): move our commits by hand.
  git --git-dir="$LINUX_BARE" merge-base --is-ancestor "$nevr" "$fedora_release" ||
    echo "warning: linux/$fedora_release is not on $nevr -- cd $dir && git rebase --onto $nevr" \
      "$(git --git-dir="$LINUX_BARE" describe --tags --abbrev=0 --match 'kernel-*' "$fedora_release") $fedora_release" >&2
}

# Development trees added as remotes of ~/src/linux/.git: name, URL, branches.
# No tags. Every fetch is cut off at --shallow-since: a plain fetch into the
# shallow repo is not bounded by what is already here, and the first
# backmerge of an older branch would pull in all of mainline history. xe:
# Intel Xe driver (Arc A770 / DG2 work).
LINUX_REMOTES=(
  "xe https://gitlab.freedesktop.org/drm/xe/kernel.git drm-xe-next drm-xe-fixes drm-xe-next-fixes"
)
LINUX_SHALLOW_SINCE="6 months ago"

setup_linux_remote() {
  local name=$1 url=$2; shift 2
  set_remote "$LINUX_BARE" "$name" "$url"
  git --git-dir="$LINUX_BARE" remote set-branches "$name" "$@"
  git --git-dir="$LINUX_BARE" config "remote.$name.tagOpt" --no-tags
  echo "Fetching linux remote $name..."
  # Fails with "no commits selected for shallow requests" when every updated
  # branch tip is older than the cutoff.
  if ! git --git-dir="$LINUX_BARE" fetch -q --shallow-since="$LINUX_SHALLOW_SINCE" "$name"; then
    echo "warning: fetching linux remote $name failed -- a branch older than $LINUX_SHALLOW_SINCE?" >&2
  fi
}

[ -d "$LINUX_BARE" ] || git init -q --bare "$LINUX_BARE"
git --git-dir="$LINUX_BARE" config user.email "fedora@slipsprogrammor.no"
for remote in "${LINUX_REMOTES[@]}"; do
  # shellcheck disable=SC2086 # word-split on purpose
  setup_linux_remote $remote
done
for fedora_release in rawhide "${release_branches[@]}"; do
  setup_kernel_tree "$fedora_release"
done

# Upstream Hyprland checkout, for reading the build system when bumping specs.
if [ ! -d "$HOME/src/Hyprland" ]; then
  git clone --recursive https://github.com/hyprwm/Hyprland.git "$HOME/src/Hyprland"
fi

# --- Mock roots ------------------------------------------------------------
# One tracked template per stack (~/.config/mock/templates/<stack>.tpl) reads
# the release from the root name; each root is a symlink to it. See MOCK.md.
for tpl in "$HOME"/.config/mock/templates/*.tpl; do
  [ -f "$tpl" ] || continue
  stack=$(basename "$tpl" .tpl)
  for rel in rawhide "${release_branches[@]#f}"; do
    ln -sfn "templates/$stack.tpl" "$HOME/.config/mock/fedora-$rel-x86_64-$stack.cfg"
  done
done

echo "Done."

# Using the Coprs:
#   sudo dnf copr enable ebbex/ffmpeg   && sudo dnf install --allowerasing ffmpeg
#   sudo dnf copr enable ebbex/fwupd    && sudo dnf upgrade fwupd
#   sudo dnf copr enable ebbex/gnome    && sudo dnf install loupe glide-rs
#   sudo dnf copr enable ebbex/hyprland && sudo dnf install hyprland
#   sudo dnf copr enable ebbex/kernel   && sudo dnf upgrade kernel igt-gpu-tools
#   sudo dnf copr enable ebbex/mingw    && sudo dnf install ucrtarm64-probe   # whole stack
#   sudo dnf copr enable ebbex/musl     && sudo dnf install musl-libcxx musl-llvm
#   sudo dnf copr enable ebbex/qemu     && sudo dnf install edk2-ovmf-ia32
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
