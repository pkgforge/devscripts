# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
#https://hub.docker.com/r/pkgforge/debian-ix
FROM debian:unstable
ENV GIT_REPO="https://github.com/pg83/ix"
#ENV GIT_REPO="https://github.com/stal-ix/ix"
#------------------------------------------------------------------------------------#
##Base Deps
ENV DEBIAN_FRONTEND="noninteractive"
RUN <<EOS
  #Base
  set +e
  export DEBIAN_FRONTEND="noninteractive"
  echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
  packages="apt-transport-https apt-utils autopoint bash bison ca-certificates coreutils curl dos2unix fdupes file findutils gettext git gnupg2 gperf jq locales locate moreutils nano ncdu p7zip-full rename rsync software-properties-common texinfo sudo tmux unzip util-linux xz-utils wget zip"
  #Install
  apt update -y -qq
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #Install_Re
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #Install Actual Deps
  packages="bash binutils build-essential coreutils curl findutils file g++ git grep jq libc-dev moreutils patchelf python3 rsync sed sudo strace tar tree wget xz-utils zstd"
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  hash -r 2>/dev/null || true
 #Checks
  command -v bash || exit 1
  command -v curl || exit 1
  command -v find || exit 1
  command -v rsync || exit 1
  command -v sudo || exit 1
  command -v tar || exit 1
  command -v wget || exit 1
 #Stats
  dpkg -l || true
EOS
#------------------------------------------------------------------------------------#
##Addons
RUN <<EOS
  set +e
 #askalono for Licenses
  wget --quiet --show-progress "https://bin.pkgforge.dev/$(uname -m)/askalono" -O "/usr/bin/askalono"
  chmod "a+x" "/usr/bin/askalono"
 #Eget for simplified releases
  wget --quiet --show-progress "https://bin.pkgforge.dev/$(uname -m)/eget" -O "/usr/bin/eget"
  chmod "a+x" "/usr/bin/eget"
 #Micro
  wget --quiet --show-progress "https://bin.pkgforge.dev/$(uname -m)/micro" -O "/usr/bin/micro"
  chmod "a+x" "/usr/bin/micro"
 #Soar
  wget --quiet --show-progress "https://bin.pkgforge.dev/$(uname -m)/soar" -O "/usr/bin/soar"
  chmod "a+x" "/usr/bin/soar"
EOS
#------------------------------------------------------------------------------------#
##Stal/IX: https://github.com/pkgforge/devscripts/blob/main/Linux/install_ix.sh
RUN <<EOS
 #Install
  cd "$(mktemp -d)" >/dev/null 2>&1
  curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/install_ix.sh" -o "./install.sh" && chmod +x "./install.sh"
  bash "./install.sh"
  rm -rf "$(realpath .)" && cd - >/dev/null 2>&1 || true
 #Check
  if [ -z "${SYSTMP+x}" ] || [ -z "${SYSTMP##*[[:space:]]}" ]; then
    SYSTMP="$(dirname "$(mktemp -u)" | tr -d '[:space:]')"
  fi
  if [ ! -d "$SYSTMP" ]; then
    mkdir -p "$SYSTMP"
  fi
  if [ ! -s "${SYSTMP}/INITIALIZED" ]; then
    exit 1
  fi
EOS
#------------------------------------------------------------------------------------#
##Config
RUN <<EOS
 #Configure ENV
  curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/.bashrc" -o "/etc/bash.bashrc"
  ln --symbolic --force "/etc/bash.bashrc" "/root/.bashrc" 2>/dev/null
  ln --symbolic --force "/etc/bash.bashrc" "/home/alpine/.bashrc" 2>/dev/null
  ln --symbolic --force "/etc/bash.bashrc" "/etc/bash/bashrc" 2>/dev/null
EOS
ENV GIT_ASKPASS="/bin/echo"
ENV GIT_TERMINAL_PROMPT="0"
#------------------------------------------------------------------------------------#
#END