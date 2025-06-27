# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
#FROM ghcr.io/pkgforge/devscripts/debian:loongarch64
FROM docker.io/pkgforge/debian:loongarch64
ENV GIT_ASKPASS="/bin/echo"
ENV GIT_TERMINAL_PROMPT="0"
ENV DEBIAN_FRONTEND="noninteractive"
RUN <<EOS
  set +e
  #Config
   echo "nameserver 1.1.1.1" > "/etc/resolv.conf"
   echo "nameserver 2606:4700:4700::1111" >> "/etc/resolv.conf"
   echo "nameserver 8.8.8.8" >> "/etc/resolv.conf"
   echo "nameserver 2620:0:ccc::2" >> "/etc/resolv.conf"
   apt autoremove -y 2>/dev/null
   apt clean -y 2>/dev/null
   apt purge -y 2>/dev/null
  #Update
   apt update -y -qq
   apt upgrade -y -qq
   apt autoremove -y 2>/dev/null
   apt clean -y 2>/dev/null
   apt purge -y 2>/dev/null
   rm -rvf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOS
CMD ["/bin/bash"]
#------------------------------------------------------------------------------------#
#END