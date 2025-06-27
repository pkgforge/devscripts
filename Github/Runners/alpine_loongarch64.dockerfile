# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
FROM scratch
ADD alpine-minirootfs-loongarch64.tar.gz /
ENV GIT_ASKPASS="/bin/echo"
ENV GIT_TERMINAL_PROMPT="0"
RUN apk add ca-certificates tzdata --latest --upgrade --no-cache --no-interactive
CMD ["/bin/sh"]
#------------------------------------------------------------------------------------#
#END