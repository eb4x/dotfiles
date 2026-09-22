#!/usr/bin/env bash
set -euo pipefail

# latest stable go -> ~/.local/share/go/toolchains/go<version>, `current` -> it.
# rollback: ln -sfn ~/.local/share/go/toolchains/{go1.25.5,current}

GO_VERSIONS_DIR="$HOME/.local/share/go/toolchains"

eval "$(
  curl -fsS 'https://go.dev/dl/?mode=json' | jq -r '
    .[0] | .version as $version
    | .files[]
    | select(.os == "linux" and .arch == "amd64" and .kind == "archive")
    | @sh "version=\($version) tarball=\(.filename) sha256=\(.sha256)"
  '
)"
: "${version:?no linux/amd64 archive at go.dev/dl}"

goroot="$GO_VERSIONS_DIR/$version"

if [ ! -x "$goroot/bin/go" ]; then
  mkdir -p "$GO_VERSIONS_DIR"
  # staged alongside so the mv below is a same-fs rename, not a tmpfs copy
  stage="$(mktemp -d -p "$GO_VERSIONS_DIR")"
  trap 'rm -rf "$stage"' EXIT

  echo "setup-go: downloading $tarball"
  curl -fL --progress-bar -o "$stage/$tarball" "https://go.dev/dl/$tarball"
  echo "$sha256  $stage/$tarball" | sha256sum -c -

  # unpacks as "go/"; rm first or mv would nest inside a partial install
  tar -C "$stage" -xzf "$stage/$tarball"
  rm -rf "$goroot"
  mv "$stage/go" "$goroot"
fi

ln -sfn "$goroot" "$GO_VERSIONS_DIR/current"
echo "setup-go: current -> $version"

GOTOOLCHAIN=local "$GO_VERSIONS_DIR/current/bin/go" version
