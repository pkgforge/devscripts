# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
# Based on :: https://github.com/pkgforge/devscripts/blob/main/Github/Runners/ubuntu-systemd-base.dockerfile
# Preconfigured with: Systemd + SSHD + Docker
# URL: https://hub.docker.com/r/pkgforge/gh-runner-riscv64-ubuntu
FROM ubuntu:latest
#------------------------------------------------------------------------------------#
##Base Deps
ENV DEBIAN_FRONTEND="noninteractive"
RUN <<EOS
  #Base
  export DEBIAN_FRONTEND="noninteractive"
  echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
  packages="apt-transport-https apt-utils bash ca-certificates coreutils curl dos2unix fdupes findutils git gnupg2 imagemagick jq locales locate moreutils nano ncdu p7zip-full rename rsync software-properties-common texinfo sudo tmux unzip util-linux xz-utils wget zip"
  #Install
  apt update -y -qq
  for pkg in $packages; do apt install -y --ignore-missing "$pkg"; done
  #Install_Re
  for pkg in $packages; do apt install -y --ignore-missing "$pkg"; done
  #unminimize : https://wiki.ubuntu.com/Minimal
  yes | unminimize
  #Python
  apt install python3 -y
  #Test
  python --version 2>/dev/null ; python3 --version 2>/dev/null
  #Install pip:
  #python3 -m ensurepip --upgrade ; pip3 --version
  #curl -qfsSL "https://bootstrap.pypa.io/get-pip.py" -o "$SYSTMP/get-pip.py" && python3 "$SYSTMP/get-pip.py"
  packages="libxslt-dev lm-sensors pciutils procps python3-distro python-dev-is-python3 python3-lxml python3-netifaces python3-pip python3-venv sysfsutils virt-what"
  for pkg in $packages; do apt install -y --ignore-missing "$pkg"; done
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
  apt update -y
  packages="dbus iptables iproute2 libsystemd0 kmod systemd systemd-sysv udev"
  for pkg in $packages; do apt install -y --ignore-missing "$pkg"; done
 ##Prevents journald from reading kernel messages from /dev/kmsg
 # echo "ReadKMsg=no" >> "/etc/systemd/journald.conf"
 #Disable systemd services/units that are unnecessary within a container.
  #systemctl mask "systemd-udevd.service"
  #systemctl mask "systemd-udevd-kernel.socket"
  #systemctl mask "systemd-udevd-control.socket"
  #systemctl mask "systemd-modules-load.service"
  #systemctl mask "sys-kernel-debug.mount"
  #systemctl mask "sys-kernel-tracing.mount"
 #Housekeeping
  apt clean -y
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
 #Passwordless sudo for runner
  echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" >> "/etc/sudoers"
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
##Install Docker
RUN <<EOS
  #Install Docker
  rm -rf "/var/lib/apt/lists/"*
  cd "$(mktemp -d)" >/dev/null 2>&1
  curl -qfsSL "https://get.docker.com" -o "./get-docker.sh" && sh "./get-docker.sh"
  cd - >/dev/null 2>&1
  apt update -y -qq
  hash -r &>/dev/null
  command -v docker || apt install 'docker.io' -y
 #Add runner to docker
  groupadd docker 2>/dev/null
  usermod -aG "docker" "runner"
 #Add Docker Completions
  curl -qfsSL "https://raw.githubusercontent.com/docker/docker-ce/master/components/cli/contrib/completion/bash/docker" > "/etc/bash_completion.d/docker.sh"
 #Confiure Docker Opts
  #Remove Hardlimit
  sed -i 's/ulimit -Hn/# ulimit -Hn/g' "/etc/init.d/docker"
  #Install Additional Deps
  packages="btrfs-progs fuse-overlayfs fuse3 kmod libfuse3-dev"
  for pkg in $packages; do apt install -y --ignore-missing "$pkg" || true; done
  true
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Addons
RUN <<EOS
 ##Addons
 #https://github.com/pkgforge/devscripts/blob/main/Linux/install_bins_curl.sh
 curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/install_bins_curl.sh" -o "./tools.sh"
 dos2unix --quiet "./tools.sh" && chmod +x "./tools.sh"
 bash "./tools.sh" 2>/dev/null || true ; rm -rf "./tools.sh"
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Build Tools
RUN <<EOS
  apt update -y
  packages="aria2 automake bc binutils b3sum build-essential ca-certificates ccache diffutils dos2unix findutils gawk lzip jq libtool libtool-bin make musl musl-dev musl-tools p7zip-full rsync texinfo wget xz-utils"
  for pkg in $packages; do apt install -y --ignore-missing "$pkg"; done
  apt install python3 -y
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Download Runner Script
# https://github.com/dkurt/github_actions_riscv
WORKDIR /runner
RUN <<EOS
 #Setup Dotnet: https://github.com/dkurt/dotnet_riscv/releases/latest
  wget --quiet --show-progress "https://github.com/dkurt/dotnet_riscv/releases/latest/download/dotnet-sdk-9.0.100-linux-riscv64-gcc-ubuntu-24.04.tar.gz" -O "./dotnet.tar.gz"
  if [ ! -f "./dotnet.tar.gz" ]; then
     exit 1
  else
     mkdir -pv "/opt/dotnet"
     tar -xzf "./dotnet.tar.gz" -C "/opt/dotnet"
     if [ ! -f "/opt/dotnet/dotnet" ]; then
        exit 1
     else
        ln -fsv "/opt/dotnet/dotnet" "/usr/local/bin/dotnet"
        rm -rf "./dotnet.tar.gz"
     fi
  fi
 #Setup GH Runner (riscv64): https://github.com/dkurt/github_actions_riscv/releases/latest
  wget --quiet --show-progress "https://github.com/pkgforge/devscripts/releases/download/gh-riscv64-Linux/runner.tar.gz" -O "./runner.tar.gz"
  if [ ! -f "./runner.tar.gz" ]; then
     exit 1
  fi
 #Untar
  mkdir -p "/runner-init"
  tar -xzf "./runner.tar.gz" -C "/runner-init" && rm "./runner.tar.gz"
 #Dos2unix
  find "/runner-init" -type f -exec dos2unix --quiet {} \; 2>/dev/null || true
 #Chown
  chown -R "runner:runner" "/runner-init"
  chmod -R 755 "/runner-init"
  chmod 'a+x' "/runner-init/run.sh" 2>/dev/null
  chmod 'a+x' "/runner-init/run-helper.sh" 2>/dev/null
 #Run Install
  chmod +x "/runner-init/bin/installdependencies.sh" && bash "/runner-init/bin/installdependencies.sh"
 #Remove cache 
  rm -rf "/var/lib/apt/lists/"* 2>/dev/null
EOS
#Copy Manager script
COPY "./manager.sh" "/usr/local/bin/manager.sh"
RUN chmod 'a+x' "/usr/local/bin/manager.sh"
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Display & x11 :: https://github.com/puppeteer/puppeteer/issues/8148
RUN <<EOS
 #x11 & display server
  echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
  apt update -y
  packages="dbus-x11 fonts-ipafont-gothic fonts-freefont-ttf gtk2-engines-pixbuf imagemagick libxss1 xauth xfonts-base xfonts-100dpi xfonts-75dpi xfonts-cyrillic xfonts-scalable x11-apps xorg xvfb"
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
 #Re
  echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
  apt update -y
  packages="dbus-x11 fonts-ipafont-gothic fonts-freefont-ttf gtk2-engines-pixbuf imagemagick libxss1 xauth xfonts-base xfonts-100dpi xfonts-75dpi xfonts-cyrillic xfonts-scalable x11-apps xorg xvfb"
  for pkg in $packages; do DEBIAN_FRONTEND="noninteractive" apt install -y --ignore-missing "$pkg"; done
 #Configure
  touch "/root/.Xauthority"
  sudo -u "runner" touch "/home/runner/.Xauthority"
 #To start: (-ac --> disable access control restrictions)
 #Xvfb -ac ":0" & 
 # export DISPLAY=":0" && google-chrome
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##This is no longer needed because replaced docker with podman
##Docker systemctl https://github.com/gdraheim/docker-systemctl-replacement
RUN <<EOS
#systemctl
#System has not been booted with systemd as init system (PID 1). Can't operate.
#Failed to connect to bus: Host is down
#Replace with patched
 apt install python3 -y
# curl -qfsSL "https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py" -o "$(which systemctl)"
 mkdir -p "/var/run/dbus" ; dbus-daemon --config-file="/usr/share/dbus-1/system.conf" --print-address
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Enable SSH & SSH Service
RUN <<EOS
  ##Install SSH
  set +e
  apt update -y && apt install openssh-server ssh -y
  #Config
  mkdir -p "/run/sshd" ; mkdir -p "/etc/ssh" ; touch "/var/log/auth.log" "/var/log/btmp" 2>/dev/null || true
  mkdir -p "/root/.ssh" ; chown "root:root" "/root/.ssh"
  #touch "/etc/ssh/authorized_keys" "/root/.ssh/authorized_keys" "/root/.ssh/config" "/root/.ssh/known_hosts"
  mkdir -p "/home/runner/.ssh" ; chown "runner:runner" "/home/runner/.ssh"
  touch "/etc/ssh/authorized_keys" "/home/runner/.ssh/authorized_keys" "/home/runner/.ssh/config" "/home/runner/.ssh/known_hosts"
  #Generate-Keys
  echo "yes" | ssh-keygen -N "" -t "ecdsa" -b 521 -f "/etc/ssh/ssh_host_ecdsa_key"
  #cp "/etc/ssh/ssh_host_ecdsa_key" "/home/runner/.ssh/id_ecdsa" ; cp "/etc/ssh/ssh_host_ecdsa_key" "/root/.ssh/id_ecdsa"
  #cp "/etc/ssh/ssh_host_ecdsa_key.pub" "/home/runner/.ssh/id_ecdsa.pub" ; cp "/etc/ssh/ssh_host_ecdsa_key.pub" "root/.ssh/id_ecdsa.pub"
  echo "yes" | ssh-keygen -N "" -t "ed25519" -f "/etc/ssh/ssh_host_ed25519_key"
  #cp "/etc/ssh/ssh_host_ed25519_key" "/home/runner/.ssh/id_ed25519" ; cp "/etc/ssh/ssh_host_ed25519_key" "/root/.ssh/id_ed25519"
  #cp "/etc/ssh/ssh_host_ed25519_key.pub" "/home/runner/.ssh/id_ed25519.pub" ; cp "/etc/ssh/ssh_host_ed25519_key.pub" "/root/.ssh/id_ed25519.pub"
  echo "yes" | ssh-keygen -N "" -t "rsa" -b 4096 -f "/etc/ssh/ssh_host_rsa_key"
  #cp "/etc/ssh/ssh_host_rsa_key" "/home/runner/.ssh/id_rsa" ; cp "/etc/ssh/ssh_host_rsa_key" "/root/.ssh/id_rsa"
  #cp "/etc/ssh/ssh_host_rsa_key.pub" "/home/runner/.ssh/id_rsa.pub" ; cp "/etc/ssh/ssh_host_rsa_key.pub" "/root/.ssh/id_rsa.pub"
  curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/sshd_config_passwordless" -o "/etc/ssh/sshd_config"
  #Perms
  chown -R "root:root" "/root/.ssh" ; chown "root:root" "/etc/ssh/authorized_keys" ; chmod 644 "/etc/ssh/authorized_keys"
  chown -R "runner:runner" "/home/runner/.ssh"
  sudo -u "runner" chmod 750 -R "/home/runner"
  sudo -u "runner" chmod 700 -R "/home/runner/.ssh"
  sudo -u "runner" chmod 600 "/home/runner/.ssh/authorized_keys" "/home/runner/.ssh/config"
  sudo -u "runner" chmod 644 "/home/runner/.ssh/known_hosts"
  systemctl enable ssh --now 2>/dev/null || true
EOS
EXPOSE 22
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Start
RUN <<EOS
  locale-gen "en_US.UTF-8"
EOS
ENV GIT_ASKPASS="/bin/echo"
ENV GIT_TERMINAL_PROMPT="0"
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"
ENTRYPOINT ["/sbin/init"]
#------------------------------------------------------------------------------------#