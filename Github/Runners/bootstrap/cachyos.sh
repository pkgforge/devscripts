#!/usr/bin/env bash
#
##DO NOT RUN DIRECTLY
##Self: bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Github/Runners/bootstrap/cachyos.sh")
#-------------------------------------------------------#

#-------------------------------------------------------#
set -x
## No aarch64 docker yet: https://hub.docker.com/r/cachyos/cachyos/tags
## Official Response: https://discuss.cachyos.org/t/arm-future-for-cachyos/727/2
## https://github.com/CachyOS/docker
if [ "$(uname  -m)" == "aarch64" ]; then
   exit 0
fi
#-------------------------------------------------------#

#-------------------------------------------------------#
##Bootstrap
 pushd "$(mktemp -d)" >/dev/null 2>&1
  docker stop "cachyos-base" 2>/dev/null ; docker rm "cachyos-base" 2>/dev/null
  docker run --name "cachyos-base" --privileged "cachyos/cachyos-v3:latest" bash -l -c '
  #Bootstrap
   pacman -y --sync --refresh --refresh --sysupgrade --noconfirm --debug
   packages="bash binutils curl fakechroot fakeroot git wget"
   for pkg in $packages; do pacman -Sy "${pkg}" --noconfirm ; done
   for pkg in $packages; do pacman -Sy "${pkg}" --needed --noconfirm ; done
  #Fix & Patches 
   sed '\''/DownloadUser/d'\'' -i "/etc/pacman.conf"
   #sed '\''s/^.*Architecture\s*=.*$/Architecture = auto/'\'' -i "/etc/pacman.conf"
   sed '\''0,/^.*SigLevel\s*=.*/s//SigLevel = Never/'\'' -i "/etc/pacman.conf"
   #sed '\''s/^.*SigLevel\s*=.*$/SigLevel = Never/'\'' -i "/etc/pacman.conf"
   sed '\''/#\[multilib\]/,/#Include = .*/s/^#//'\'' -i "/etc/pacman.conf"
   echo -e "nameserver 8.8.8.8\nnameserver 2620:0:ccc::2" | tee "/etc/resolv.conf"
   echo -e "nameserver 1.1.1.1\nnameserver 2606:4700:4700::1111" | tee -a "/etc/resolv.conf"
   unlink "/var/lib/dbus/machine-id" 2>/dev/null
   unlink "/etc/machine-id" 2>/dev/null
   rm -rvf "/etc/machine-id"
   systemd-machine-id-setup --print 2>/dev/null | tee "/var/lib/dbus/machine-id"
   cat "/var/lib/dbus/machine-id" | tee "/etc/machine-id"
   pacman -Scc --noconfirm
   echo "disable-scdaemon" | tee "/etc/pacman.d/gnupg/gpg-agent.conf"
   curl -qfsSL "https://raw.githubusercontent.com/pkgforge/flatimage-base/refs/heads/main/archlinux_hooks.sh" -o "/arch_hooks.sh"
   chmod +x "/arch_hooks.sh" ; "/arch_hooks.sh"
   rm -rfv "/arch_hooks.sh"
   echo "LANG=en_US.UTF-8" | tee "/etc/locale.conf"
   echo "LANG=en_US.UTF-8" | tee -a "/etc/locale.conf"
   echo "LANGUAGE=en_US:en" | tee -a "/etc/locale.conf"
   echo "LC_ALL=en_US.UTF-8" | tee -a "/etc/locale.conf"
   echo "en_US.UTF-8 UTF-8" | tee -a "/etc/locale.gen"
   echo "LC_ALL=en_US.UTF-8" | tee -a "/etc/environment"
   locale-gen ; locale-gen "en_US.UTF-8"
  #Cleanup
   pacman -y --sync --refresh --refresh --sysupgrade --noconfirm
   pacman -Rsn base-devel --noconfirm
   pacman -Rsn perl --noconfirm
   pacman -Rsn python --noconfirm
   pacman -Scc --noconfirm
  #Fake-Sudo
   pacman -Rsndd sudo 2>/dev/null
   rm -rvf "/usr/bin/sudo" 2>/dev/null
   curl -qfsSL "https://github.com/pkgforge/devscripts/releases/download/common-utils/fake-sudo-pkexec.tar.zst" -o "./fake-sudo-pkexec.tar.zst" && chmod +x "./fake-sudo-pkexec.tar.zst"
   pacman -Uddd "./fake-sudo-pkexec.tar.zst" --noconfirm
   pacman -Syy fakeroot --needed --noconfirm
   rm -rvf "./fake-sudo-pkexec.tar.zst"
  #Yay
   curl -qfsSL "https://github.com/pkgforge/devscripts/releases/download/common-utils/yay-$(uname -m)" -o "/usr/bin/yay" && chmod +x "/usr/bin/yay"
   yay --version ; which fakeroot yay sudo
  #More cleanup
   rm -rfv "/usr/share/gtk-doc/"* 2>/dev/null
   rm -rfv "/usr/share/man/"* 2>/dev/null
   rm -rfv "/usr/share/help/"* 2>/dev/null
   rm -rfv "/usr/share/info/"* 2>/dev/null
   rm -rfv "/usr/share/doc/"* 2>/dev/null
   rm -rfv "/var/tmp/"* 2>/dev/null
   rm -rfv "/var/lib/pacman/sync/"* 2>/dev/null
   rm -rfv "/var/cache/pacman/pkg/"* 2>/dev/null
   find "/boot" -mindepth 1 -delete 2>/dev/null
   find "/dev" -mindepth 1 -delete 2>/dev/null
   find "/proc" -mindepth 1 -delete 2>/dev/null
   find "/run" -mindepth 1 -delete 2>/dev/null
   find "/sys" -mindepth 1 -delete 2>/dev/null
   find "/tmp" -mindepth 1 -delete 2>/dev/null
   find "/usr/include" -mindepth 1 -delete 2>/dev/null
   find "/usr/lib" -type f -name "*.a" -print -exec rm -rfv "{}" 2>/dev/null \; 2>/dev/null
   find "/usr/lib32" -type f -name "*.a" -print -exec rm -rfv "{}" 2>/dev/null \; 2>/dev/null
   find "/etc/pacman.d/gnupg" -type f -name "S.*" -print -exec rm -rfv "{}" 2>/dev/null \; 2>/dev/null
   find "/usr/share/locale" -mindepth 1 -maxdepth 1 ! -regex ".*/\(locale.alias\|en\|en_US\)$" -exec rm -rfv "{}" + 2>/dev/null
   find "/usr/share/doc" -mindepth 1 -delete 2>/dev/null
   find "/usr/share/gtk-doc" -mindepth 1 -delete 2>/dev/null
   find "/usr/share/help" -mindepth 1 -delete 2>/dev/null
   find "/usr/share/info" -mindepth 1 -delete 2>/dev/null
   find "/usr/share/man" -mindepth 1 -delete 2>/dev/null
   find "." -type d -name "__pycache__" -exec rm -rfv "{}" \; 2>/dev/null
   find "." -type f -name "*.pacnew" -exec rm -rfv "{}" \; 2>/dev/null
   find "." -type f -name "*.pacsave" -exec rm -rfv "{}" \; 2>/dev/null
   find "/var/log" -type f -name "*.log" -exec rm -rfv "{}" \; 2>/dev/null
   rm -rfv "/"{tmp,proc,sys,dev,run} 2>/dev/null
   mkdir -pv "/"{tmp,proc,sys,dev,run/media,mnt,media,home}  2>/dev/null
   rm -fv ""/etc/{host.conf,hosts,nsswitch.conf}  2>/dev/null
   touch ""/etc/{host.conf,hosts,nsswitch.conf}  2>/dev/null
   hostname 2>/dev/null; cat "/etc/os-release" 2>/dev/null'
##Export   
  docker export "$(docker ps -aqf 'name=cachyos-base')" --output "rootfs.tar"
  if [[ -f "./rootfs.tar" ]] && [[ $(stat -c%s "./rootfs.tar") -gt 10000 ]]; then
    mkdir -pv "./rootfs" && export ROOTFS_DIR="$(realpath "./rootfs")"
    rsync -achLv --mkpath "./rootfs.tar" "/tmp/cachyos-base.tar"
  else
    echo "\n[-] FATAL: Failed to export ROOTFS\n"
   exit 1
  fi
popd "$(mktemp -d)" >/dev/null 2>&1
#-------------------------------------------------------#


#-------------------------------------------------------#
##Push
#ENV
D_ID="$(docker ps -aqf 'name=cachyos-base' | tr -d '[:space:]')"
D_TAG="v$(date +'%Y.%m.%d' | tr -d '[:space:]')"
export D_ID D_TAG
#Tags
docker commit "${D_ID}" "pkgforge/cachyos-base:latest"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/cachyos-base:latest"
docker commit "${D_ID}" "pkgforge/cachyos-base:${DOCKER_TAG}"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/cachyos-base:${DOCKER_TAG}"
docker commit "${D_ID}" "pkgforge/cachyos-base:$(uname -m)"
docker commit "${D_ID}" "ghcr.io/pkgforge/devscripts/cachyos-base:$(uname -m)"
#Push
docker push "pkgforge/cachyos-base:latest"
docker push "ghcr.io/pkgforge/devscripts/cachyos-base:latest"
docker push "pkgforge/cachyos-base:${DOCKER_TAG}"
docker push "ghcr.io/pkgforge/devscripts/cachyos-base:${DOCKER_TAG}"
docker push "pkgforge/cachyos-base:$(uname -m)"
docker push "ghcr.io/pkgforge/devscripts/cachyos-base:$(uname -m)"
#-------------------------------------------------------#