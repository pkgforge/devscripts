# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
# DOCKER HUB URL : https://hub.docker.com/r/pkgforge/ubuntu-builder
FROM ubuntu:latest
#FROM ubuntu:rolling
#------------------------------------------------------------------------------------#
##Base Deps
ENV DEBIAN_FRONTEND="noninteractive"
RUN <<EOS
  #Base
  apt-get update -y
  packages="apt-transport-https apt-utils bash ca-certificates coreutils curl dos2unix fdupes findutils git gnupg2 imagemagick jq locales locate moreutils nano ncdu p7zip-full rename rsync software-properties-common sudo texinfo tmux tree unzip util-linux xz-utils wget zip"
  #Install
  apt-get update -y -qq
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #Install_Re
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #unminimize : https://wiki.ubuntu.com/Minimal
  yes | unminimize
  #Python
  apt-get install python3 -y
  #Test
  python --version 2>/dev/null ; python3 --version 2>/dev/null
  #Install pip:
  #python3 -m ensurepip --upgrade ; pip3 --version
  #curl -qfsSL "https://bootstrap.pypa.io/get-pip.py" -o "$SYSTMP/get-pip.py" && python3 "$SYSTMP/get-pip.py"
  packages="libxslt-dev lm-sensors pciutils procps python3-distro python-dev-is-python3 python3-lxml python3-netifaces python3-pip python3-venv sysfsutils virt-what"
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  pip install --break-system-packages --upgrade pip || pip install --upgrade pip
  #Misc
  pip install ansi2txt --break-system-packages --force-reinstall --upgrade
  #pipx
  pip install pipx --upgrade 2>/dev/null
  pip install pipx --upgrade --break-system-packages 2>/dev/null
EOS
#------------------------------------------------------------------------------------#
##Systemd installation
RUN <<EOS
  #SystemD
  apt-get update -y
  packages="dbus iptables iproute2 libsystemd0 kmod systemd systemd-sysv udev"
  for pkg in $packages; do apt install -y --ignore-missing "$pkg"; done
 #Housekeeping
  apt-get clean -y
  rm -rf "/lib/systemd/system/getty.target" 2>/dev/null
  rm -rf "/lib/systemd/system/systemd"*udev* 2>/dev/null
  rm -rf "/usr/share/doc/"* 2>/dev/null
  rm -rf "/usr/share/local/"* 2>/dev/null
  rm -rf "/usr/share/man/"* 2>/dev/null
  rm -rf "/var/cache/debconf/"* 2>/dev/null
  rm -rf "/var/lib/apt/lists/"* 2>/dev/null
  rm -rf "/var/log/"* 2>/dev/null
  rm -rf "/var/tmp/"* 2>/dev/null
  rm -rf "/tmp/"* 2>/dev/null
EOS
# Make use of stopsignal (instead of sigterm) to stop systemd containers.
STOPSIGNAL SIGRTMIN+3
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Create User + Setup Perms
RUN <<EOS
 #Add runner
  useradd --create-home "runner"
 #Set password
  echo "runner:runneradmin" | chpasswd
 #Add runner to sudo
  usermod -aG "sudo" "runner"
  usermod -aG "sudo" "root"
 #Passwordless for runner
  echo "%sudo  ALL=(ALL:ALL) NOPASSWD:ALL" >> "/etc/sudoers"
 #Remove preconfigured admin user
  userdel -r "admin" 2>/dev/null || true
EOS
##Change Default shell for runner to bash
RUN <<EOS
 #Check current shell
  grep runner "/etc/passwd"
 #Change to bash 
  usermod --shell "/bin/bash" "runner" 2>/dev/null
  curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/.bashrc" -o "/etc/bash.bashrc"
  dos2unix --quiet "/etc/bash.bashrc" 2>/dev/null
  ln --symbolic --force "/etc/bash.bashrc" "/home/runner/.bashrc" 2>/dev/null
  ln --symbolic --force "/etc/bash.bashrc" "/root/.bashrc" 2>/dev/null
  ln --symbolic --force "/etc/bash.bashrc" "/etc/bash/bashrc" 2>/dev/null
 #Recheck 
  grep runner "/etc/passwd"
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Addons
RUN <<EOS
 #Addons
 #https://github.com/pkgforge/devscripts/blob/main/Linux/install_bins_curl.sh
 curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/install_bins_curl.sh" -o "./tools.sh"
 dos2unix --quiet "./tools.sh" && chmod +x "./tools.sh"
 bash "./tools.sh" 2>/dev/null || true ; rm -rf "./tools.sh"
 ##Appimage tools
 curl -qfsSL "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage" -o "/usr/local/bin/appimagetool" && chmod +x "/usr/local/bin/appimagetool"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/mkappimage" -o "/usr/local/bin/mkappimage" && chmod +x "/usr/local/bin/mkappimage"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/mksquashfs" -o "/usr/local/bin/mksquashfs" && chmod +x "/usr/local/bin/mksquashfs"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/sqfscat" -o "/usr/local/bin/sqfscat" && chmod +x "/usr/local/bin/sqfscat"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/sqfstar" -o "/usr/local/bin/sqfstar" && chmod +x "/usr/local/bin/sqfstar"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/unsquashfs" -o "/usr/local/bin/unsquashfs" && chmod +x "/usr/local/bin/unsquashfs"
 true
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Build Tools
RUN <<EOS
  #----------------------#
  #Main
  set +e
  packages="apt-transport-https apt-utils aria2 asciidoc asciidoctor attr autoconf autoconf-archive automake autopoint bc binutils bison bison++ bisonc++ b3sum brotli build-essential byacc ca-certificates ccache clang cmake cmake-data coreutils desktop-file-utils devscripts diffutils dnsutils dos2unix flex file findutils fontconfig gawk gcc git-lfs gnupg2 gettext help2man imagemagick itstool lzip jq libarchive-dev libargparse-dev libassuan-dev libbearssl-dev libblkid-dev libbpf-dev libbpfcc-dev libbrotli-dev libcap-dev libcapnp-dev libcapstone-dev libc-ares-dev libcmocka-dev libedit-dev libelf-dev libevent-dev libfuse-dev libfuse3-dev libharfbuzz-dev libhwloc-dev libidn-dev libidn2-dev libjemalloc-dev liblz-dev liblz4-dev liblzo*-dev libmagick*-*-dev libmpv-dev libndctl-dev libnvme-dev libpcre2-dev libpopt-dev libpsl-dev librust-lzma-sys-dev libsdl2-dev libseccomp-dev libselinux1-dev libsndio-dev libsodium-dev libsqlite3-dev libssh-dev libtool libtool-bin libunistring-dev liburing libusb-dev libwayland-dev libwolfssl-dev libx11-dev libx11-xcb-dev libxdp-dev libxi-dev libxkbcommon-dev libxmlb-dev libxv-dev libxxhash-dev libyaml-dev libzimg-dev libzstd-dev linux-headers-generic lzma lzma-dev make meson moreutils musl musl-dev musl-tools nasm nettle-dev npm patch patchelf pkg-config python3 python3-pip python3-venv p7zip-full qemu-user-static rsync scons software-properties-common spirv-cross sqlite3 sqlite3-pcre sqlite3-tools swig texinfo texi2html tree txt2html util-linux wget xsltproc xxhash xz-utils yasm zsync"
  #Install
  apt-get update -y -qq
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #Install_Re
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #----------------------#
  #Dockerc
  curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/dockerc" -o "/usr/bin/dockerc" && chmod +x "/usr/bin/dockerc"
  #----------------------#
  #Install Meson & Ninja
  #rm "/usr/bin/meson" "/usr/bin/ninja" 2>/dev/null
  pip install meson ninja --upgrade 2>/dev/null
  pip install meson ninja --break-system-packages --upgrade --force-reinstall 2>/dev/null
  #----------------------#
  #libpcap
  apt install libpcap-dev pcaputils -y 2>/dev/null 
  #----------------------#        
  #libsqlite3
  apt-get install libsqlite3-dev sqlite3 sqlite3-pcre sqlite3-tools -y 2>/dev/null
  #----------------------#
  #lzma
  apt-get install liblz-dev librust-lzma-sys-dev lzma lzma-dev -y
  #----------------------#
  #staticx: https://github.com/JonathonReinhart/staticx/blob/main/.github/workflows/build-test.yml
  export CWD="$(realpath .)" ; cd "$(mktemp -d)" >/dev/null 2>&1 ; realpath .
  #Switch to default: https://github.com/JonathonReinhart/staticx/pull/284
  git clone --filter "blob:none" "https://github.com/JonathonReinhart/staticx" --branch "add-type-checking" && cd "./staticx"
  #https://github.com/JonathonReinhart/staticx/blob/main/build.sh
  pip install -r "./requirements.txt" --break-system-packages --upgrade --force
  apt-get update -y
  apt-get install -y busybox musl-tools scons
  export BOOTLOADER_CC="musl-gcc"
  rm -rf "./build" "./dist" "./scons_build" "./staticx/assets"
  python "./setup.py" sdist bdist_wheel
  find "dist/" -name "*.whl" | xargs -I {} sh -c 'newname=$(echo {} | sed "s/none-[^/]*\.whl$/none-any.whl/"); mv "{}" "$newname"'
  find "dist/" -name "*.whl" | xargs pip install --break-system-packages --upgrade --force
  staticx --version || pip install staticx --break-system-packages --force-reinstall --upgrade ; unset BOOTLOADER_CC
  rm -rf "$(realpath .)" ; cd "${CWD}"
  #----------------------#
  #pyinstaller
  pip install "git+https://github.com/pyinstaller/pyinstaller" --break-system-packages --force-reinstall --upgrade ; pyinstaller --version
  #----------------------#
  #golang
  cd "$(mktemp -d)" >/dev/null 2>&1 ; realpath .
  curl -qfsSL "https://git.io/go-installer" -o "./install.sh"
  dos2unix --quiet "./install.sh" && chmod +x "./install.sh"
  echo "yes" | bash "./install.sh" 2>/dev/null || true
  rm -rf "$(realpath .)" ; cd "${CWD}"
  #----------------------#
  #Nix
   hash -r &>/dev/null
   sudo -u "runner" bash -c \
   '
   pushd "$(mktemp -d)" &>/dev/null
   curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/install_nix.sh" -o "./install_nix.sh"
   dos2unix --quiet "./install_nix.sh" ; chmod +x "./install_nix.sh"
   bash "./install_nix.sh" || true
   rm -rf "$(realpath .)" ; popd &>/dev/null
   ' || true
  #----------------------#
  #patchelf
  curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/patchelf" -o "/usr/bin/patchelf" && chmod +x "/usr/bin/patchelf"
  #----------------------#
  #Rust
  cd "$(mktemp -d)" >/dev/null 2>&1 ; realpath .
  curl -qfsSL "https://sh.rustup.rs" -o "./install.sh"
  dos2unix --quiet "./install.sh" && chmod +x "./install.sh"
  bash "./install.sh" -y 2>/dev/null || true
  rm -rf "$(realpath .)" ; cd "${CWD}"
  #----------------------#
  #Zig
   hash -r &>/dev/null
   if ! command -v zig >/dev/null 2>&1; then
     cd "$(mktemp -d)" >/dev/null 2>&1
     curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/install_zig.sh" -o "./install_zig.sh"
     dos2unix --quiet "./install_zig.sh" ; chmod +x "./install_zig.sh"
     bash "./install_zig.sh" 2>/dev/null || true ; rm -rf "./install_zig.sh"
   fi
  #Exit
  #----------------------#
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Start
RUN <<EOS
 #Locale
  echo "LC_ALL=en_US.UTF-8" | tee -a "/etc/environment"
  echo "en_US.UTF-8 UTF-8" | tee -a "/etc/locale.gen"
  echo "LANG=en_US.UTF-8" | tee -a "/etc/locale.conf"
  locale-gen "en_US.UTF-8"
 #Dialog
  echo "debconf debconf/frontend select Noninteractive" | debconf-set-selections
  debconf-show debconf 
EOS
ENV DEBIAN_FRONTEND="noninteractive"
ENV GIT_ASKPASS="/bin/echo"
ENV GIT_TERMINAL_PROMPT="0"
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"
ENV PATH="${HOME}/bin:${HOME}/.cargo/bin:${HOME}/.cargo/env:${HOME}/.go/bin:${HOME}/go/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${HOME}/.local/bin:${HOME}/miniconda3/bin:${HOME}/miniconda3/condabin:/usr/local/zig:/usr/local/zig/lib:/usr/local/zig/lib/include:/usr/local/musl/bin:/usr/local/musl/lib:/usr/local/musl/include:${PATH}"
#------------------------------------------------------------------------------------#