# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
#https://hub.docker.com/r/pkgforge/alpine-builder
#FROM alpine:edge
ARG ARCH
FROM "ghcr.io/pkgforge/devscripts/alpine:${ARCH}"
#------------------------------------------------------------------------------------#
##Base Deps :: https://pkgs.alpinelinux.org/packages
RUN <<EOS
  set +e
  apk update && apk upgrade --no-interactive 2>/dev/null
  apk add alpine-sdk --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add autoconf --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add automake --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add b3sum --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add bash --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add bc --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add binutils --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add brotli-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add build-base --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add bzip2-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add bzip3-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add c-ares-dev --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add ca-certificates --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add cairo-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add clang --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add cmake --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add coreutils --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add croc --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add curl --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add curl-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add diffutils --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add dos2unix --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add file --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add findutils --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add fuse-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add fuse3 --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add fuse3-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add g++ --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add gawk --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add gcc --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add gettext-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add git --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add grep --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add iputils --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add jq --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libarchive-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libc-dev --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libcap-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libcap-ng-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libcurl --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libssh2-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libx11-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libxcb-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libxi-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libxkbcommon-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libxmlb --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add libxml2-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add lld --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add linux-headers --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add llvm --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add llvm-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add lz4-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add make --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add mold --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add moreutils --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add musl --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add musl-dev --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add nano --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add nasm --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add ncdu --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add ncurses-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add net-tools --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add openssl --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add openssl-dev --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add openssl-libs-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add patchelf --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add pcre-dev --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add pcre2-dev --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add pkgconfig --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add python3 --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add python3-dev --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add readline-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add rsync --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add rustup --latest --upgrade --no-cache --no-interactive 2>/dev/null ; rustup-init -y
  #https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/community/rustup/APKBUILD#L8
  hash -r &>/dev/null
  command -v cargo || apk add cargo --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add sed --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add sqlite-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add sudo --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add tar --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add tree --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add tzdata --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add util-linux-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add wayland-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add wget --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add xxd --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add xxhash --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add xz --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add xz-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add yaml-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add zlib-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add zstd --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add zstd-static --latest --upgrade --no-cache --no-interactive 2>/dev/null
  apk add 7zip --latest --upgrade --no-cache --no-interactive 2>/dev/null
 #Stats
  apk stats
EOS
#------------------------------------------------------------------------------------#
##Addons
RUN <<EOS
  set +e
 #musl-gcc wrapper
  ln --symbolic "/usr/bin/$(uname -m)-alpine-linux-musl-gcc" "/usr/local/bin/musl-gcc" 2>/dev/null
 #cleanup
  apk info -L
  rm -rfv "/var/cache/apk/"* 2>/dev/null
 #Exit
  true
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