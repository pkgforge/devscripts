# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
#https://hub.docker.com/r/pkgforge/alpine-rust
ARG ARCH
ARG TOOLCHAIN
FROM "ghcr.io/pkgforge/devscripts/alpine-slim:${ARCH}"
#------------------------------------------------------------------------------------#
##Setup Rust
RUN <<EOS
  set +e
  apk update && apk upgrade --no-cache --no-interactive 2>/dev/null
  apk add rustup --latest --upgrade --no-cache --no-interactive 2>/dev/null
  hash -r >/dev/null 2>&1
  rustup-init --default-toolchain "${TOOLCHAIN}" --no-modify-path -y || true
  if [ -d "/root/.rustup/toolchains" ] && [ "$(du -sm '/root/.rustup/toolchains' | cut -f1)" -gt 10 ]; then
    find "/root/.rustup/toolchains" -type d \( -path '*/share/bash' -o -path '*/share/doc' -o -path '*/share/fish' \
      -o -path '*/share/man' -o -path '*/share/zsh' \) -exec rm -rvf "{}" + 2>/dev/null || true
  else
    #https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/community/rustup/APKBUILD#L8
    if [ "$(uname -m)" == "riscv64" ]; then
       if ! command -v cargo >/dev/null 2>&1; then 
         apk add cargo --latest --upgrade --no-cache --no-interactive 2>/dev/null
       fi
       hash -r >/dev/null 2>&1
       if ! command -v cargo >/dev/null 2>&1; then 
         exit 1
       fi
    else
       exit 1
    fi
  fi
EOS
#------------------------------------------------------------------------------------#
#END