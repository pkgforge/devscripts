# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
#https://hub.docker.com/r/pkgforge/debian-guix
ARG ARCH
FROM "pkgforge/debian-builder-unstable:${ARCH}"
#------------------------------------------------------------------------------------#
##Install
RUN <<EOS
  #----------------------# 
  #Env
  set +e
  export DEBIAN_FRONTEND="noninteractive"
  echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
  #----------------------#   
  #https://github.com/pkgforge/devscripts/blob/main/Github/Runners/bootstrap/debian_guix.sh
  curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Github/Runners/bootstrap/debian_guix.sh" -o "./debian_guix.sh"
  dos2unix --quiet "./debian_guix.sh" && chmod +x "./debian_guix.sh"
  bash "./debian_guix.sh" 2>/dev/null || true ; rm -rvf "./debian_guix.sh"
EOS
#------------------------------------------------------------------------------------#