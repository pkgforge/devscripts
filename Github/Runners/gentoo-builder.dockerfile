# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
## Image: https://hub.docker.com/r/pkgforge/gentoo-builder-*
## Base: https://github.com/gentoo/gentoo-docker-images
ARG BASE_IMG="docker.io/gentoo/stage3:llvm"
FROM gentoo/portage:latest AS portage
FROM "${BASE_IMG}"
COPY --from=portage "/var/db/repos/gentoo" "/var/db/repos/gentoo"
#------------------------------------------------------------------------------------#
##Base Deps
RUN <<EOS
  #Fix Initial Repo
   set +e ; export CWD="$(realpath .)" ; cd "$(mktemp -d)" &>/dev/null ; realpath "."
   emerge --sync --ask="n" --jobs="$(($(nproc)+1))" || rm -rf "/var/db/repos/gentoo" 2>/dev/null 
   emerge --sync --ask="n" --jobs="$(($(nproc)+1))"
   mv -fv "/etc/portage/gnupg" "/etc/portage/gnupg.bak"
   getuto ; emerge --sync --ask="n" --jobs="$(($(nproc)+1))"
   emerge "dev-vcs/git" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg
   emerge "dev-vcs/git" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg 2>/dev/null
   if ! command -v git >/dev/null; then
      echo "FATAL: Failed to Install GIT"
     exit 1
   fi
   emerge "net-misc/curl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg
   if ! command -v curl >/dev/null; then
     wget "https://bin.pkgforge.dev/$(uname -m)-$(uname -s)/curl" -O "/usr/bin/curl"
     chmod +x "/usr/bin/curl"
     curl --version
   fi
  #Add New Settings
   mkdir -pv "/etc/portage/repos.conf"
   curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/gentoo.conf" -o "/etc/portage/repos.conf/gentoo.conf"
   echo '' >> "/etc/portage/make.conf"
   echo '# Prefer Static Libs' >> "/etc/portage/make.conf"
   echo 'USE="${USE} static-libs"' >> "/etc/portage/make.conf"
   #echo '' >> "/etc/portage/make.conf"
   #echo '# Prefer Prebuilts' >> "/etc/portage/make.conf"
   #echo 'FEATURES="getbinpkg binpkg-request-signature"' >> "/etc/portage/make.conf"
  #Update/Sync
   cd "$(mktemp -d)" &>/dev/null ; realpath "."
   rm -rf "/var/db/repos/gentoo" 2>/dev/null
   emerge --sync --ask="n" --jobs="$(($(nproc)+1))" || true
   git -C "/var/db/repos/gentoo/" reset --hard 2>/dev/null
   emerge --sync --ask="n" --jobs="$(($(nproc)+1))"
   yes "y" | eselect news read all &>/dev/null
  #Base Pkgs
   packages="app-arch/p7zip app-arch/unzip app-arch/zip app-editors/nano app-misc/jq app-misc/screen app-portage/gentoolkit dev-lang/python dev-python/pip net-dns/bind-tools net-misc/wget sys-apps/locale-gen sys-apps/moreutils sys-apps/net-tools sys-apps/util-linux sys-devel/gettext sys-fs/ncdu-bin"
  #Install
   for pkg in $packages; do emerge "$pkg" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace ; done
  #Install_Re
   for pkg in $packages; do emerge "$pkg" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace ; done
  #Python
   pip install --upgrade pip || pip install --break-system-packages --upgrade pip
   pip install pipx --upgrade || pip install pipx --upgrade --break-system-packages 2>/dev/null
   curl -qfsSL "https://astral.sh/uv/install.sh" -o "./install.sh"
   dos2unix --quiet "./install.sh" && chmod +x "./install.sh"
   bash "./install.sh" 2>/dev/null || true ; rm -rf "./install.sh"
  #Test
   python --version 2>/dev/null ; python3 --version 2>/dev/null
   pipx --version 2>/dev/null
   PATH="${HOME}/bin:${HOME}/.cargo/bin:${HOME}/.cargo/env:${HOME}/.go/bin:${HOME}/go/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${HOME}/.local/bin:${HOME}/miniconda3/bin:${HOME}/miniconda3/condabin:/usr/local/zig:/usr/local/zig/lib:/usr/local/zig/lib/include:/usr/local/musl/bin:/usr/local/musl/lib:/usr/local/musl/include:${PATH}" uv --version 2>/dev/null
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Create User + Setup Perms
RUN <<EOS
 #Add sudo
  export CWD="$(realpath .)"
  emerge "app-admin/sudo" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
 #Add runner
  useradd --create-home "runner"
 #Set password
  echo "runner:runneradmin" | chpasswd
 #Add runner to sudo
  usermod -aG "wheel" "runner"
  usermod -aG "wheel" "root"
 #Passwordless sudo for runner
  echo "%wheel   ALL=(ALL:ALL) NOPASSWD:ALL" >> "/etc/sudoers"
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
#RUN echo 'export PATH="/command:${PATH}"' >> "/etc/bash.bashrc"
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Addons
RUN <<EOS
 ##Addons
 export CWD="$(realpath .)"
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
   export CWD="$(realpath .)"
   packages="app-arch/7zip app-arch/brotli app-arch/bzip2 app-arch/bzip3 app-arch/gzip app-arch/lz4 app-arch/lz5 app-arch/lzlib app-arch/lzma app-arch/lzop app-arch/rar app-arch/tar app-arch/upx-bin app-arch/xz-utils app-arch/zip app-arch/zstd app-text/asciidoc app-text/docx2txt app-text/dos2unix app-text/doxygen app-text/html-xml-utils app-text/texi2html app-text/texlive app-text/xml2 app-text/xml2doc dev-build/autoconf dev-build/automake dev-build/b2 dev-build/bmake dev-build/cmake dev-build/just dev-build/kbuild dev-build/libtool dev-build/make dev-build/meson dev-build/muon dev-build/ninja dev-build/pmake dev-build/qconf dev-build/samurai dev-build/scons dev-lang/execline dev-lang/ghc dev-lang/go dev-lang/lua dev-lang/luajit dev-lang/mujs dev-lang/ocaml dev-lang/perl dev-lang/php dev-lang/rust-bin dev-lang/typescript dev-lang/yasm dev-lang/zig-bin dev-python/xxhash dev-ruby/asciidoctor dev-util/byacc dev-util/ccache dev-util/desktop-file-utils dev-util/gperf dev-util/intltool dev-util/itstool dev-util/spirv-headers dev-util/yacc dev-vcs/cvs dev-vcs/fossil dev-vcs/subversion net-dns/c-ares net-dns/libidn net-dns/libidn2 net-misc/aria2 net-misc/axel net-misc/croc net-misc/iperf net-misc/openssh net-misc/sshpass net-misc/wget net-misc/wget2 net-misc/whois net-misc/zsync sys-apps/acl sys-apps/attr sys-apps/coreutils sys-apps/diffutils sys-apps/dmidecode sys-apps/ethtool sys-apps/findutils sys-apps/i2c-tools sys-apps/kbd sys-apps/less sys-apps/lsb-release sys-apps/moreutils sys-apps/net-tools sys-apps/policycoreutils sys-apps/progress sys-apps/rename sys-apps/ripgrep sys-apps/shadow sys-apps/texinfo sys-apps/util-linux sys-apps/which sys-devel/autogen sys-devel/bc sys-devel/binutils sys-devel/bison sys-devel/elftoolchain sys-devel/flex sys-devel/gcc sys-devel/gettext sys-devel/m4 sys-devel/mold sys-devel/multilib-gcc-wrapper sys-devel/native-cctools sys-devel/patch"
  #Install
   emerge --sync --ask="n" --jobs="$(($(nproc)+1))"
   yes "y" | eselect news read all &>/dev/null
   for pkg in $packages; do emerge "$pkg" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace ; done
  #Static Libs: https://packages.gentoo.org/useflags/static-libs
   emerge "dev-db/sqlite" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/angelscript" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/bitset" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/capstone" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/cgilib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/chmlib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/confuse" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/crypto++" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/cyrus-sasl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/dbus-glib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/eekboard" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/elfutils" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/eventlog" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/expat" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/flatbuffers" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/geoip" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/gf2x" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/glib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/gmp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/hiredict" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/hiredis" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/hyphen" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/icu" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/icu-layoutex" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/input-pad" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/isl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/ivykis" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/jansson" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/json-c" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libaio" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libatasmart" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libax25" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libbpf" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libbsd" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libbson" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libburn" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libcdio" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libcgroup" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libconfig" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libcpuid" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libdnsres" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libedit" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/liberasurecode" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libestr" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libev" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libevent" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libf2c" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libfastjson" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libffi" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libfido2" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libfstrcmp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libgamin" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libgcrypt" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libgpg-error" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libgrapheme" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libical" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libiconv" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libintl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libisoburn" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libisofs" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libkpass" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libksba" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/liblognorm" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libltdl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/liblzw" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libmelf" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libmix" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libmodbus" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libmoe" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libotf" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libp11" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libpcre" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libpcre2" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libpfm" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libpqxx" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libpwquality" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/librdkafka" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/librelp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libserialport" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libsodium" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libspnav" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libtasn1" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libtermkey" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libtommath" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libucl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libudfread" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libuev" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libunibreak" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libunistring" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libusb" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libutf8proc" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libxml2" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libxslt" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libyaml" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/libzip" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/lzo" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/mongo-c-driver" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/mpc" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/mpfr" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/mxml" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/nettle" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/oniguruma" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/OpenNI2" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/openssl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/ossp-uuid" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/popt" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/protobuf" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/protobuf-c" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/rasqal" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/redis-ipc" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/rocksdb" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/rremove" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/s2n" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/snowball-stemmer" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/spdlog" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/squareball" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/starpu" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/stfl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/tinyxml" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/ucl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/userspace-rcu" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/xapian" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/xerces-c" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "dev-libs/xmlsec" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/alsa-oss" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/flac" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/freeimage" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/freetype" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/gst-rtsp-server" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/imlib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/lcms" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libcaca" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libjpeg-turbo" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/liblo" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/liblrdf" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libmad" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libmetalink" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libmikmod" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libmpd" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libmtp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libpng" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libsdl2" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libsdl3" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/libwebp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/opus" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/ptex" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sbc" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl2-image" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl2-mixer" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl2-net" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl2-ttf" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl-image" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl-mixer" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl-pango" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl-sound" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/sdl-ttf" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/t1lib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/tiff" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/virglrenderer" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/x264" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "media-libs/zimg" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/c-client" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/courier-authlib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/czmq" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/daq" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/enet" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/gloox" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/gnutls" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/ldns" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libbtbb" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libcork" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libesmtp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libetpan" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libgsasl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libircclient" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/liblockfile" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libmicrohttpd" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libnet" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libnetfilter_queue" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libnftnl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libnids" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libnsl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libntlm" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libosmo-dsp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libpcap" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libpcapnav" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libprotoident" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libpsl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libslirp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libsrsirc" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libsrtp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libssh" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libtirpc" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/libupnp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/liquid-dsp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/mbedtls" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/nghttp2" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/nghttp3" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/ngtcp2" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/pjproject" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/rabbitmq-c" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/shairplay" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/zeromq" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "net-libs/zmqpp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sci-libs/blis" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sci-libs/gsl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sci-libs/ldl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sci-libs/libdap" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sci-libs/libigl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sci-libs/libticonv" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-devel/autogen" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-devel/binutils" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-devel/binutils-hppa64" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-devel/gettext" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/btrfs-progs" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/cryptsetup" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/e2fsprogs" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/erofs-utils" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/fswatch" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/fuse" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/lvm2" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/nilfs-utils" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/ntfs3g" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/progsreiserfs" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/reiserfsprogs" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/squashfuse" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/sysfsutils" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-fs/xfsprogs" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/argp-standalone" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/binutils-libs" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/blocksruntime" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/cracklib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/error-standalone" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/fts-standalone" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/gdbm" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libapparmor" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libcap" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libcap-ng" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libieee1284" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libnvidia-container" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/librtas" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libseccomp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libselinux" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libservicelog" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libsmbios" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libunwind" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/liburing" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libutempter" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/libxcrypt" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/musl" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/ncurses" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/obstack-standalone" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/openipmi" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/readline" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/rpmatch-standalone" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/slang" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "sys-libs/zlib" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/agg" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/fltk" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/libdlo" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/libdockapp" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/libgxim" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/libxkbcommon" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/motif" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/pixman" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
   emerge "x11-libs/xosd" --ask="n" --jobs="$(($(nproc)+1))" --getbinpkg --noreplace
  #patchelf
   if ! command -v patchelf >/dev/null; then
     curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)/patchelf" -o "/usr/bin/patchelf" && chmod +x "/usr/bin/patchelf"
   fi
  #----------------------#
  #Rust
   if ! command -v cargo >/dev/null; then
     cd "$(mktemp -d)" >/dev/null 2>&1 ; realpath .
     curl -qfsSL "https://sh.rustup.rs" -o "./install.sh"
     dos2unix --quiet "./install.sh" && chmod +x "./install.sh"
     bash "./install.sh" -y 2>/dev/null || true
     rm -rf "$(realpath .)" ; cd "${CWD}"
   fi
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
   locale-gen "en_US.UTF-8" || locale-gen --generate "en_US.UTF-8"
 #End
   emerge --sync --ask="n" --jobs="$(($(nproc)+1))"
   yes "y" | eselect news read all &>/dev/null
   emerge --depclean --ask="n" --jobs="$(($(nproc)+1))"
   eclean-dist
   true
EOS
ENV GIT_ASKPASS="/bin/echo"
ENV GIT_TERMINAL_PROMPT="0"
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"
ENV PATH="${HOME}/bin:${HOME}/.cargo/bin:${HOME}/.cargo/env:${HOME}/.go/bin:${HOME}/go/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${HOME}/.local/bin:${HOME}/miniconda3/bin:${HOME}/miniconda3/condabin:/usr/local/zig:/usr/local/zig/lib:/usr/local/zig/lib/include:/usr/local/musl/bin:/usr/local/musl/lib:/usr/local/musl/include:${PATH}"
#------------------------------------------------------------------------------------#