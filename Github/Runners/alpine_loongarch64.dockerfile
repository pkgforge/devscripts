# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
FROM scratch
ADD alpine-minirootfs-loongarch64.tar.gz /
ENV GIT_ASKPASS="/bin/echo"
ENV GIT_TERMINAL_PROMPT="0"
RUN <<EOS
  set +e
  #Config
   echo "nameserver 1.1.1.1" > "/etc/resolv.conf"
   echo "nameserver 2606:4700:4700::1111" >> "/etc/resolv.conf"
   echo "nameserver 8.8.8.8" >> "/etc/resolv.conf"
   echo "nameserver 2620:0:ccc::2" >> "/etc/resolv.conf"
   mkdir -pv "/etc/apk"
   echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" | tee "/etc/apk/repositories"
   echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" | tee -a "/etc/apk/repositories"
   echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" | tee -a "/etc/apk/repositories"
  #Update
   apk upgrade --no-cache --no-interactive 2>/dev/null
   apk add ca-certificates --latest --upgrade --no-cache --no-interactive
   apk add tzdata --latest --upgrade --no-cache --no-interactive
EOS
CMD ["/bin/sh"]
#------------------------------------------------------------------------------------#
#END