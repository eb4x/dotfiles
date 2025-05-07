#!/usr/bin/env bash
set -euo pipefail

echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
sudo chmod 0440 /etc/sudoers.d/$USER

mkdir -p $HOME/src
if [ ! -d $HOME/src/Hyprland ]; then
  git clone --recursive https://github.com/hyprwm/Hyprland.git $HOME/src/Hyprland
fi

rpmbuild_topdir=$(rpm --eval '%{_topdir}')
mkdir -p $rpmbuild_topdir/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

declare -A repos=(
  [hyprutils]="https://src.fedoraproject.org/rpms/hyprutils.git"
  [aquamarine]="https://src.fedoraproject.org/rpms/aquamarine.git"
  [hyprland]="https://src.fedoraproject.org/rpms/hyprland.git"
  [hyprlock]="https://src.fedoraproject.org/rpms/hyprlock.git"
)

build_order=(
  hyprutils
  aquamarine
  hyprland
  hyprlock
)

mkdir -p $HOME/src/rpms
for package in "${build_order[@]}"; do
  if [ ! -d "$HOME/src/rpms/$package" ]; then
    git clone "${repos[$package]}" "$HOME/src/rpms/$package"
  fi

  cp "$HOME/src/rpms/${package}/${package}.spec" "$rpmbuild_topdir/SPECS/"
  cp "$HOME/src/rpms/${package}/sources" "$rpmbuild_topdir/SOURCES/${package}_sources"

  spectool -g -R $rpmbuild_topdir/SPECS/${package}.spec

  sudo dnf builddep -y $rpmbuild_topdir/SPECS/${package}.spec

  rpmbuild -ba $rpmbuild_topdir/SPECS/${package}.spec

  for package_rpm in $(rpmspec --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm\n' --query ${rpmbuild_topdir}/SPECS/${package}.spec); do
    sudo dnf install --allowerasing -y $rpmbuild_topdir/RPMS/x86_64/${package_rpm}
  done
done

sudo rm /etc/sudoers.d/$USER
