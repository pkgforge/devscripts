# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
#https://hub.docker.com/r/pkgforge/debian-builder-unstable
FROM debian:unstable
#------------------------------------------------------------------------------------#
##Base Deps
ENV DEBIAN_FRONTEND="noninteractive"
RUN <<EOS
  #Base
  set +e
  export DEBIAN_FRONTEND="noninteractive"
  echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
  packages="apt-transport-https apt-utils autopoint bash bison ca-certificates coreutils curl dos2unix fdupes file findutils gettext git gnupg2 gperf imagemagick jq locales locate moreutils nano ncdu p7zip-full rename rsync software-properties-common texinfo sudo tmux unzip util-linux xz-utils wget zip"
  #Install
  apt update -y -qq
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #Install_Re
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #NetTools
  packages="dnsutils inetutils-ftp inetutils-ftpd inetutils-inetd inetutils-ping inetutils-syslogd inetutils-tools inetutils-traceroute iproute2 net-tools netcat-traditional"
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  packages="iputils-arping iputils-clockdiff iputils-ping iputils-tracepath iproute2"
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  setcap 'cap_net_raw+ep' "$(which ping)"
  #Python
  apt install python3 -y
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
 #Passwordless sudo for runner
  echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" >> "/etc/sudoers"
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
##Set PATH [Default: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] /command is s6-tools
#ENV PATH "/command:${PATH}"
#RUN echo 'export PATH="/command:${PATH}"' >> "/etc/bash.bashrc"
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Addons
RUN <<EOS
 ##Addons
 #https://github.com/pkgforge/devscripts/blob/main/Linux/install_bins_curl.sh
 curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/install_bins_curl.sh" -o "./tools.sh"
 dos2unix --quiet "./tools.sh" && chmod +x "./tools.sh"
 bash "./tools.sh" 2>/dev/null || true ; rm -rf "./tools.sh"
 ##Appimage tools
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/go-appimagetool.no_strip" -o "/usr/local/bin/go-appimagetool" && chmod +x "/usr/local/bin/go-appimagetool"
 curl -qfsSL "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage" -o "/usr/local/bin/appimagetool" && chmod +x "/usr/local/bin/appimagetool"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/linuxdeploy.no_strip" -o "/usr/local/bin/linuxdeploy" && chmod +x "/usr/local/bin/linuxdeploy"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/mkappimage" -o "/usr/local/bin/mkappimage" && chmod +x "/usr/local/bin/mkappimage"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/Baseutils/squashfstools/mksquashfs" -o "/usr/local/bin/mksquashfs" && chmod +x "/usr/local/bin/mksquashfs"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/Baseutils/squashfstools/sqfscat" -o "/usr/local/bin/sqfscat" && chmod +x "/usr/local/bin/sqfscat"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/Baseutils/squashfstools/sqfstar" -o "/usr/local/bin/sqfstar" && chmod +x "/usr/local/bin/sqfstar"
 curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/Baseutils/squashfstools/unsquashfs" -o "/usr/local/bin/unsquashfs" && chmod +x "/usr/local/bin/unsquashfs"
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Build Tools
RUN <<EOS
  #----------------------#
  #Main
  set +e
  packages="aria2 asciidoc asciidoctor attr autoconf autoconf-archive automake autopoint bc binutils b3sum bc bison bison++ bisonc++ brotli build-essential ca-certificates ccache clang cmake cmake-extras coreutils cython3 diffutils dos2unix execline findutils fontconfig gawk gcc gettext help2man itstool lzip jq libarchive-dev libargparse-dev libassuan-dev libbearssl-dev libblkid-dev libbpf-dev libbpfcc-dev libbrotli-dev libcap-dev libcapnp-dev libcapstone-dev libc-ares-dev libcmocka-dev libedit-dev libelf-dev libevent-dev libfuse-dev libfuse3-dev libharfbuzz-dev libhwloc-dev libidn-dev libidn2-dev libjemalloc-dev liblz4-dev liblzo*-dev libmagick*-*-dev libmpv-dev libndctl-dev libnvme-dev libpcre2-dev libpopt-dev libpsl-dev libsdl2-dev libseccomp-dev libselinux1-dev libsndio-dev libsodium-dev libsqlite3-dev libssh-dev libsysprof*-dev libtool libtool-bin libunistring-dev liburing libusb-dev libwayland-dev libwolfssl-dev libx11-dev libx11-xcb-dev libxdp-dev libxi-dev libxkbcommon-dev libxmlb-dev libxv-dev libxxhash-dev libyaml-dev libzimg-dev libzstd-dev linux-headers-amd64 mlibxxhash-dev ake mesa-common-dev meson musl musl-dev musl-tools nasm nettle-dev npm patchelf policycoreutils pkg-config python3 p7zip-full spirv-cross rsync swig texinfo texi2html txt2html util-linux wget xsltproc xxhash xz-utils yasm"
  #Install
  apt update -y -qq
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #Install_Re
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
  #----------------------#
  #Dockerc
  curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/dockerc" -o "/usr/bin/dockerc" && chmod +x "/usr/bin/dockerc"
  #----------------------#
  #Install Meson & Ninja
  #sudo rm "/usr/bin/meson" "/usr/bin/ninja" 2>/dev/null
  pip install meson ninja --upgrade 2>/dev/null
  pip install meson ninja --break-system-packages --upgrade --force-reinstall 2>/dev/null
  #python3 -m pip install meson ninja --upgrade
  #Installs to /usr/local/bin/
  #sudo ln -s "$HOME/.local/bin/meson" "/usr/bin/meson" 2>/dev/null
  #sudo ln -s "$HOME/.local/bin/ninja" "/usr/bin/ninja" 2>/dev/null
  #sudo chmod +xwr "/usr/bin/meson" "/usr/bin/ninja" 2>/dev/null
  #----------------------#
  #libpcap
  sudo apt install libpcap-dev pcaputils -y 2>/dev/null 
  #----------------------#        
  #libsqlite3
  sudo apt install libsqlite3-dev sqlite3 sqlite3-pcre sqlite3-tools -y 2>/dev/null
  #----------------------#
  #lzma
  sudo apt install liblz-dev librust-lzma-sys-dev lzma lzma-dev -y
  #----------------------#
  #mold
  sudo apt install mold -y
  #----------------------#
  #staticx: https://github.com/JonathonReinhart/staticx/blob/main/.github/workflows/build-test.yml
  export CWD="$(realpath .)" ; cd "$(mktemp -d)" >/dev/null 2>&1 ; realpath .
  #Switch to default: https://github.com/JonathonReinhart/staticx/pull/284
  git clone --filter "blob:none" "https://github.com/JonathonReinhart/staticx" --branch "add-type-checking" && cd "./staticx"
  #https://github.com/JonathonReinhart/staticx/blob/main/build.sh
  pip install -r "./requirements.txt" --break-system-packages --upgrade --force
  sudo apt update -y
  sudo apt install -y busybox musl-tools scons
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
ENV PATH="${HOME}/bin:${HOME}/.cargo/bin:${HOME}/.cargo/env:${HOME}/.go/bin:${HOME}/go/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${HOME}/.local/bin:${HOME}/miniconda3/bin:${HOME}/miniconda3/condabin:/usr/local/zig:/usr/local/zig/lib:/usr/local/zig/lib/include:/usr/local/musl/bin:/usr/local/musl/lib:/usr/local/musl/include:$PATH"
#------------------------------------------------------------------------------------#
