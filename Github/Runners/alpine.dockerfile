# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
ARG TARGETARCH=amd64

# Stage for official Alpine images (aarch64, riscv64, x86_64)
FROM alpine:edge AS official
RUN apk add --no-cache ca-certificates tzdata

# Stage for loongarch64 using local rootfs file
FROM scratch AS loongarch64-base
ADD /tmp/alpine-minirootfs-loongarch64.tar.gz /

FROM loongarch64-base AS loongarch64
RUN apk add --no-cache ca-certificates tzdata

# Final stage - select based on architecture
FROM ${TARGETARCH} AS final
CMD ["/bin/sh"]