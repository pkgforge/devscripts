# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
ARG TARGETARCH=amd64
ENV DEBIAN_FRONTEND=noninteractive

# Stage for official Debian images (amd64, arm64, riscv64)
FROM debian:unstable AS official
RUN apt update && \
    apt install -y ca-certificates curl wget && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create aliases for official architectures
FROM official AS amd64
FROM official AS arm64
FROM official AS riscv64

# Stage for loongarch64 using pre-built image
FROM docker.io/pkgforge/debian:loongarch64 AS loongarch64
RUN apt update && \
    apt install -y ca-certificates curl wget && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Select based on architecture
FROM ${TARGETARCH} AS final
CMD ["/bin/bash"]