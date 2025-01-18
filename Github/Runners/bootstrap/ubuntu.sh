#!/usr/bin/env bash
#
##DO NOT RUN DIRECTLY
##Self: bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Github/Runners/bootstrap/ubuntu.sh")
#-------------------------------------------------------#

#-------------------------------------------------------#
## https://github.com/phusion/baseimage-docker
# https://hub.docker.com/r/phusion/baseimage/tags
set -x
#-------------------------------------------------------#

#-------------------------------------------------------#
##Bootstrap
 pushd "$(mktemp -d)" >/dev/null 2>&1
  docker stop "ubuntu-base" 2>/dev/null ; docker rm "ubuntu-base" 2>/dev/null
  docker run --name "ubuntu-base" --privileged "phusion/baseimage:noble-1.0.0" sh -l -c '
  #Bootstrap
   #echo -e "nameserver 8.8.8.8\nnameserver 2620:0:ccc::2" | tee "/etc/resolv.conf"
   #echo -e "nameserver 1.1.1.1\nnameserver 2606:4700:4700::1111" | tee -a "/etc/resolv.conf"
   unlink "/var/lib/dbus/machine-id" 2>/dev/null
   unlink "/etc/machine-id" 2>/dev/null
   rm -rvf "/etc/machine-id"
   systemd-machine-id-setup --print 2>/dev/null | tee "/var/lib/dbus/machine-id"
   ln --symbolic --force --relative "/var/lib/dbus/machine-id" "/etc/machine-id"
   echo "LANG=en_US.UTF-8" | tee "/etc/locale.conf"
   echo "LANG=en_US.UTF-8" | tee -a "/etc/locale.conf"
   echo "LANGUAGE=en_US:en" | tee -a "/etc/locale.conf"
   echo "LC_ALL=en_US.UTF-8" | tee -a "/etc/locale.conf"
   echo "en_US.UTF-8 UTF-8" | tee -a "/etc/locale.gen"
   echo "LC_ALL=en_US.UTF-8" | tee -a "/etc/environment"
   chown -R _apt:root /var/cache/apt/archives/partial/
   dpkg-statoverride --remove /usr/bin/crontab
   ubuntu_FRONTEND="noninteractive" apt update -y
   ubuntu_FRONTEND="noninteractive" apt install bash binutils coreutils curl fakechroot fakeroot gawk git locales sed wget -y --no-install-recommends --ignore-missing
   locale-gen "en_US.UTF-8"
   echo "debconf debconf/frontend select Noninteractive" | debconf-set-selections
   apt purge locales perl -y ; apt autoremove -y ; apt autoclean -y
   curl -qfsSL "https://raw.githubusercontent.com/VHSgunzo/runimage-fake-sudo-pkexec/refs/heads/main/usr/bin/sudo" -o "/usr/bin/sudo" && chmod -v "a+x" "/usr/bin/sudo"
   apt list --installed
   apt clean -y
   find "/boot" -mindepth 1 -delete 2>/dev/null
   find "/dev" -mindepth 1 -delete 2>/dev/null
   find "/proc" -mindepth 1 -delete 2>/dev/null
   find "/run" -mindepth 1 -delete 2>/dev/null
   find "/sys" -mindepth 1 -delete 2>/dev/null
   find "/tmp" -mindepth 1 -delete 2>/dev/null
   find "/usr/include" -mindepth 1 -delete 2>/dev/null
   find "/usr/lib" -type f -name "*.a" -print -exec rm -rfv "{}" 2>/dev/null \; 2>/dev/null
   find "/usr/lib32" -type f -name "*.a" -print -exec rm -rfv "{}" 2>/dev/null \; 2>/dev/null
   find "/usr/share/locale" -mindepth 1 -maxdepth 1 ! -regex '\''.*/\(locale.alias\|en\|en_US\)$'\'' -exec rm -rfv "{}" + 2>/dev/null
   find "/usr/share/doc" -mindepth 1 -delete 2>/dev/null
   find "/usr/share/gtk-doc" -mindepth 1 -delete 2>/dev/null
   find "/usr/share/help" -mindepth 1 -delete 2>/dev/null
   find "/usr/share/info" -mindepth 1 -delete 2>/dev/null
   find "/usr/share/man" -mindepth 1 -delete 2>/dev/null
   find "/" -type d -name "__pycache__" -exec rm -rfv "{}" \; 2>/dev/null
   find "/" -type f -name "*.pacnew" -exec rm -rfv "{}" \; 2>/dev/null
   find "/" -type f -name "*.pacsave" -exec rm -rfv "{}" \; 2>/dev/null
   find "/var/log" -type f -name "*.log" -exec rm -rfv "{}" \; 2>/dev/null
   rm -rfv "/var/lib/apt/lists/"*
   rm -rfv "/var/cache/apt/"*
   bash -c "rm -rfv /{tmp,proc,sys,dev,run}"
   bash -c "mkdir -pv /{tmp,proc,sys,dev,run/media,mnt,media,home}"
   bash -c "rm -fv /etc/{host.conf,hosts,passwd,group,nsswitch.conf}"
   bash -c "touch /etc/{host.conf,hosts,passwd,group,nsswitch.conf}"
   '
##Export
  docker export "$(docker ps -aqf 'name=ubuntu-base')" --output "rootfs.tar"
  if [[ -f "./rootfs.tar" ]] && [[ $(stat -c%s "./rootfs.tar") -gt 10000 ]]; then
    rsync -achLv --mkpath "./rootfs.tar" "/tmp/rootfs.tar"
  else
    echo "\n[-] FATAL: Failed to export ROOTFS\n"
   exit 1
  fi
popd "$(mktemp -d)" >/dev/null 2>&1
#-------------------------------------------------------#


#-------------------------------------------------------#
##Push
#ENV
D_ID="$(docker ps -aqf 'name=ubuntu-base' | tr -d '[:space:]')"
D_TAG="v$(date +'%Y.%m.%d' | tr -d '[:space:]')"
export D_ID D_TAG
#Export & Import
docker export "${D_ID}" | docker import - "pkgforge/ubuntu-base:temp"
#Tags
docker tag "pkgforge/ubuntu-base:temp" "pkgforge/ubuntu-base:latest"
docker tag "pkgforge/ubuntu-base:temp" "ghcr.io/pkgforge/devscripts/ubuntu-base:latest"
docker tag "pkgforge/ubuntu-base:temp" "pkgforge/ubuntu-base:${D_TAG}"
docker tag "pkgforge/ubuntu-base:temp" "ghcr.io/pkgforge/devscripts/ubuntu-base:${D_TAG}"
docker tag "pkgforge/ubuntu-base:temp" "pkgforge/ubuntu-base:$(uname -m)"
docker tag "pkgforge/ubuntu-base:temp" "ghcr.io/pkgforge/devscripts/ubuntu-base:$(uname -m)"
#Push
docker push "pkgforge/ubuntu-base:latest"
docker push "ghcr.io/pkgforge/devscripts/ubuntu-base:latest"
docker push "pkgforge/ubuntu-base:${D_TAG}"
docker push "ghcr.io/pkgforge/devscripts/ubuntu-base:${D_TAG}"
docker push "pkgforge/ubuntu-base:$(uname -m)"
docker push "ghcr.io/pkgforge/devscripts/ubuntu-base:$(uname -m)"
#-------------------------------------------------------#