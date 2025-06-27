# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#

# Default stage for most architectures
FROM alpine:edge AS final
RUN apk add --no-cache ca-certificates tzdata
CMD ["/bin/sh"]

# Special stage for loong64
FROM scratch AS final-loong64
ADD alpine-minirootfs-loongarch64.tar.gz /
RUN apk add --no-cache ca-certificates tzdata
CMD ["/bin/sh"]