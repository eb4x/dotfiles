#!/usr/bin/env bash
set -euo pipefail

tftp_root=/var/lib/tftp
sudo mkdir -p $tftp_root
sudo chown -R $USER:$USER $tftp_root

alma_releases=(8 9 10)
fedora_releases=(43 44)

# The selinux fcontext rule and the nginx config are owned by
# setup-dnsmasq-ipxe.sh; a bare restorecon here is just insurance.
sudo restorecon -R $tftp_root

# .treeinfo is fetched alongside the images it describes. anaconda reads it to
# find stage2 and identify the release; without it the install still works
# (it falls back to the conventional images/install.img layout) but every boot
# logs a 404 for it. More usefully, it is the only thing on this path carrying
# sha256 sums for install.img and the initrd -- we serve these over plain http
# on the LAN, so it is the one integrity check available to the installer.
#
# It must come from the SAME tree as the images: the [ ! -f ] guards below mean
# an existing cache is never refreshed, so after an upstream respin delete the
# release directory rather than letting a new .treeinfo describe old images.
#
# AlmaLinux's copy declares [variant-AppStream] with a relative repository path
# (../../../AppStream/x86_64/os) that does not resolve in our flattened local
# layout. Harmless, because the menus always point inst.repo at the upstream
# mirror and only take stage2 from here.
download_file() {
  local url=$1
  local dest=$2

  local http_code
  http_code=$(curl --silent -L "$url" --output "$dest" --write-out "%{http_code}")

  if [[ "$http_code" != 2* ]]; then
    echo "ERROR: Got HTTP $http_code for $url" >&2
    rm -f "$dest"  # Don't leave a junk HTML file behind
    return 1
  fi
}

for releasever in "${alma_releases[@]}"; do
  work_dir=$tftp_root/almalinux/$releasever/x86_64/os
  mkdir -p $work_dir/images/pxeboot

  http_root=https://almalinux.uib.no/$releasever/BaseOS/x86_64/os
  for pxe_file in .treeinfo images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      download_file "$http_root/$pxe_file" "$work_dir/$pxe_file" || echo "WARN: skipped $http_root/$pxe_file" >&2
    fi
  done
done

for releasever in 10; do
  work_dir=$tftp_root/almalinux/$releasever/x86_64_v2/os
  mkdir -p $work_dir/images/pxeboot

  http_root=https://almalinux.uib.no/$releasever/BaseOS/x86_64_v2/os
  for pxe_file in .treeinfo images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      download_file "$http_root/$pxe_file" "$work_dir/$pxe_file" || echo "WARN: skipped $http_root/$pxe_file" >&2
    fi
  done
done

declare -A fedora_release_paths=(
  # Betas live under releases/test/ and exist on mirrors only until GA, e.g.:
  # [45_Beta]="test/45_Beta"
)

for releasever in "${fedora_releases[@]}"; do
  work_dir=$tftp_root/fedora/$releasever/x86_64/os
  mkdir -p $work_dir/images/pxeboot

  release_path="${fedora_release_paths[$releasever]:-$releasever}"
  http_root=https://mirror.accum.se/mirror/fedora/linux/releases/${release_path}/Everything/x86_64/os
  #http_root=https://download.fedoraproject.org/pub/fedora/linux/releases/${release_path}/Everything/x86_64/os
  for pxe_file in .treeinfo images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      download_file "$http_root/$pxe_file" "$work_dir/$pxe_file" || echo "WARN: skipped $http_root/$pxe_file" >&2
    fi
  done
done

# Fedora 30 is the last i386 release (for the old i686 box); it only exists on
# the archive server. NOTE: the local fedora.ks targets modern anaconda and may
# not parse on F30 -- booting works either way, adapt the ks before installing.
for releasever in 30; do
  work_dir=$tftp_root/fedora/$releasever/i386/os
  mkdir -p $work_dir/images/pxeboot

  http_root=https://archives.fedoraproject.org/pub/archive/fedora-secondary/releases/$releasever/Everything/i386/os
  for pxe_file in .treeinfo images/install.img images/pxeboot/initrd.img images/pxeboot/vmlinuz; do
    if [ ! -f $work_dir/$pxe_file ]; then
      download_file "$http_root/$pxe_file" "$work_dir/$pxe_file" || echo "WARN: skipped $http_root/$pxe_file" >&2
    fi
  done
done

# Check for live/vmlinuz rather than the directory: a failed extraction must
# not satisfy the guard, or reruns could never repair it.
gparted_version="1.7.0-1"
if [ ! -f "${tftp_root}/gparted/${gparted_version}/live/vmlinuz" ]; then
  mkdir -p "${tftp_root}/gparted/${gparted_version}"
  curl -fL https://sourceforge.net/projects/gparted/files/gparted-live-stable/${gparted_version}/gparted-live-${gparted_version}-amd64.zip/download | bsdtar --extract --file - --directory $tftp_root/gparted/${gparted_version}
fi
