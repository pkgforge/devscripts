#!/usr/bin/env bash
#
##DO NOT RUN DIRECTLY
##Self: bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Github/Runners/bootstrap/debian.sh")
#-------------------------------------------------------#

#-------------------------------------------------------#
set -x
#-------------------------------------------------------#

#-------------------------------------------------------#
##Bootstrap
 pushd "$(mktemp -d)" >/dev/null 2>&1
  docker stop "debian-base" 2>/dev/null ; docker rm "debian-base" 2>/dev/null
  docker run --name "debian-base" --privileged "debian:stable-slim" sh -l -c '
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
   DEBIAN_FRONTEND="noninteractive" apt update -y
   DEBIAN_FRONTEND="noninteractive" apt install bash binutils coreutils curl fakeroot git locales sudo wget -y --no-install-recommends --ignore-missing
   locale-gen "en_US.UTF-8"
   echo "debconf debconf/frontend select Noninteractive" | debconf-set-selections
   apt purge locales perl -y ; apt autoremove -y ; apt autoclean -y
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
  docker export "$(docker ps -aqf 'name=debian-base')" --output "rootfs.tar"
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
D_ID="$(docker ps -aqf 'name=debian-base' | tr -d '[:space:]')"
D_TAG="v$(date +'%Y.%m.%d' | tr -d '[:space:]')"
export D_ID D_TAG
#Tags
docker commit "${D_ID}" "pkgforge/debian-base:latest"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/debian-base:latest"
docker commit "${D_ID}" "pkgforge/debian-base:${D_TAG}"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/debian-base:${D_TAG}"
docker commit "${D_ID}" "pkgforge/debian-base:$(uname -m)"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/debian-base:$(uname -m)"
#Push
docker push "pkgforge/debian-base:latest"
docker push "ghcr.io/pkgforge/devscripts/debian-base:latest"
docker push "pkgforge/debian-base:${D_TAG}"
docker push "ghcr.io/pkgforge/devscripts/debian-base:${D_TAG}"
docker push "pkgforge/debian-base:$(uname -m)"
docker push "ghcr.io/pkgforge/devscripts/debian-base:$(uname -m)"
#-------------------------------------------------------#