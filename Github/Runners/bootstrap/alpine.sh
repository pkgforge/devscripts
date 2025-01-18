#!/usr/bin/env bash
#
##DO NOT RUN DIRECTLY
##Self: bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Github/Runners/bootstrap/alpine.sh")
#-------------------------------------------------------#

#-------------------------------------------------------#
set -x
#-------------------------------------------------------#

#-------------------------------------------------------#
##Bootstrap
 pushd "$(mktemp -d)" >/dev/null 2>&1
  docker stop "alpine-base" 2>/dev/null ; docker rm "alpine-base" 2>/dev/null
  docker run --name "alpine-base" --privileged "alpine:edge" sh -l -c '
  #Bootstrap
   apk update --no-interactive
   apk upgrade --no-interactive
   apk add bash binutils curl fakeroot gawk musl-locales-lang sed wget --latest --upgrade --no-interactive
   #apk add bash alsa-utils alsa-utils-doc alsa-lib alsaconf alsa-ucm-conf pulseaudio pulseaudio-alsa --latest --upgrade --no-interactive
  #Fix & Patches
   chmod 755 "/bin/bbsuid" 2>/dev/null
   echo -e "nameserver 8.8.8.8\nnameserver 2620:0:ccc::2" | tee "/etc/resolv.conf"
   echo -e "nameserver 1.1.1.1\nnameserver 2606:4700:4700::1111" | tee -a "/etc/resolv.conf"
   mkdir -pv "/etc/apk"
   echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" | tee "/etc/apk/repositories"
   echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" | tee -a "/etc/apk/repositories"
   echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" | tee -a "/etc/apk/repositories"
   echo "LANG=en_US.UTF-8" | tee "/etc/locale.conf"
   echo "LANG=en_US.UTF-8" | tee -a "/etc/locale.conf"
   echo "LANGUAGE=en_US:en" | tee -a "/etc/locale.conf"
   echo "LC_ALL=en_US.UTF-8" | tee -a "/etc/locale.conf"
   locale-gen
   locale-gen "en_US.UTF-8"
  #Cleanup
   bash -c "rm -rfv /{tmp,proc,sys,dev,run}"
   bash -c "mkdir -pv /{tmp,proc,sys,dev,run/media,mnt,media,home}"
   bash -c "rm -fv /etc/{host.conf,hosts,passwd,group,nsswitch.conf}"
   bash -c "touch /etc/{host.conf,hosts,passwd,group,nsswitch.conf}"
   apk info -L
   rm -rfv "/var/cache/apk/"*
   '
##Export   
  docker export "$(docker ps -aqf 'name=alpine-base')" --output "rootfs.tar"
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
D_ID="$(docker ps -aqf 'name=alpine-base' | tr -d '[:space:]')"
D_TAG="v$(date +'%Y.%m.%d' | tr -d '[:space:]')"
export D_ID D_TAG
#Tags
docker commit "${D_ID}" "pkgforge/alpine-base:latest"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/alpine-base:latest"
docker commit "${D_ID}" "pkgforge/alpine-base:${D_TAG}"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/alpine-base:${D_TAG}"
docker commit "${D_ID}" "pkgforge/alpine-base:$(uname -m)"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/alpine-base:$(uname -m)"
#Push
docker push "pkgforge/alpine-base:latest"
docker push "ghcr.io/pkgforge/devscripts/alpine-base:latest"
docker push "pkgforge/alpine-base:${D_TAG}"
docker push "ghcr.io/pkgforge/devscripts/alpine-base:${D_TAG}"
docker push "pkgforge/alpine-base:$(uname -m)"
docker push "ghcr.io/pkgforge/devscripts/alpine-base:$(uname -m)"
#-------------------------------------------------------#