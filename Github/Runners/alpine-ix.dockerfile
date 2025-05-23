# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
#https://hub.docker.com/r/pkgforge/alpine-ix
#FROM alpine:edge
ARG ARCH
FROM "pkgforge/alpine-ix:${ARCH}"
ENV GIT_REPO="https://github.com/pg83/ix"
#ENV GIT_REPO="https://github.com/stal-ix/ix"
#------------------------------------------------------------------------------------#
##Setup Base
RUN <<EOS
  set +e
  apk update --no-interactive 2>/dev/null
  apk upgrade --latest --no-interactive 2>/dev/null
  apk add 7zip bash binutils build-base coreutils curl fakeroot findutils file g++ gcompat git grep iputils jq libc-dev linux-headers lld llvm moreutils parted python3 rsync sudo tar tree util-linux wget xz zstd --latest --upgrade --no-interactive
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
  apk stats
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
  bash "./install.sh" || true
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
  ln --symbolic --force "/etc/bash.bashrc" "/etc/bash/bashrc" 2>/dev/null
  true
EOS
ENV GIT_ASKPASS="/bin/echo"
ENV GIT_TERMINAL_PROMPT="0"
#------------------------------------------------------------------------------------#
#END