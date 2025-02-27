#!/usr/bin/env bash
# https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/Cloud/setup_apptainer_colab.sh

#-------------------------------------------------------#
#Install
export DEBIAN_FRONTEND="noninteractive"
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
command -v apt-fast &>/dev/null || echo -e "\[X] FATAL: apt-fast is NOT Installed\n$(exit 1)"
BASE_PKGS=(bash binutils coreutils cryptsetup curl fakeroot findutils file g++ git grep jq libc-dev libseccomp-dev moreutils patchelf rsync sed strace tar tree tzdata xz-utils zstd)
for pkg in "${BASE_PKGS[@]}"; do DEBIAN_FRONTEND="noninteractive" sudo apt-fast install "${pkg}" -y --ignore-missing 2>/dev/null; done
sudo apt --fix-broken install
sudo apt autoremove -y -qq
sudo apt autoclean -y -qq
pushd &>/dev/null &&\
 curl -qfsSL "https://api.gh.pkgforge.dev/repos/apptainer/apptainer/releases/latest?per_page=100" | jq -r ".. | objects | .browser_download_url? // empty" | grep -Ei "amd64" |\
 grep -Eiv "tar\.gz|\.b3sum" | grep -Eiv "dbg|debug|suid" | grep -Ei "deb" | sort --version-sort | tail -n 1 | tr -d "[:space:]" | xargs -I "{}" curl -qfsSL "{}" -o "./apptainer.deb"
 sudo chmod -v "a+x" "./apptainer.deb"
 sudo dpkg -i "./apptainer.deb" || sudo apt --fix-broken install && sudo dpkg -i "./apptainer.deb"
 command -v apptainer &>/dev/null || echo -e "\[X] FATAL: apptainer is NOT Installed\n$(exit 1)"
 sudo apt autoremove -y -qq
 sudo apt autoclean -y -qq
popd &>/dev/null
#-------------------------------------------------------#

#-------------------------------------------------------#
#Pull & Prep Containers
sudo rm -rf "/containers" 2>/dev/null
sudo mkdir -pv "/containers" && sudo chown -R "colab:colab" "/containers"
sudo chmod -R 755 "/containers"
sudo -u "colab" apptainer build --disable-cache --fix-perms --force --sandbox "/containers/alpine.sif" "docker://docker.io/alpine:edge"
du -sh "/containers/alpine.sif"
sudo -u "colab" apptainer build --disable-cache --fix-perms --force --sandbox "/containers/alpine-builder.sif" "docker://ghcr.io/pkgforge/devscripts/alpine-builder:latest"
du -sh "/containers/alpine-builder.sif"
sudo -u "colab" apptainer build --disable-cache --fix-perms --force --sandbox "/containers/debian.sif" "docker://docker.io/debian:latest"
du -sh "/containers/debian.sif"
sudo -u "colab" apptainer build --disable-cache --fix-perms --force --sandbox "/containers/debian-builder-unstable.sif" "docker://ghcr.io/pkgforge/devscripts/debian-builder-unstable:$(uname -m)"
du -sh "/containers/debian-builder-unstable.sif"
ls -lah "/containers"
#-------------------------------------------------------#
