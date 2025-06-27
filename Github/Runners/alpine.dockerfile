# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#
ARG TARGETARCH=amd64

# Default base stage for most architectures
FROM alpine:edge AS base-stage
ARG TARGETARCH
RUN if [ "$TARGETARCH" != "loong64" ]; then \
        apk add --no-cache ca-certificates tzdata; \
    fi

# Special base for loong64
FROM scratch AS loong64-base
ADD /tmp/alpine-minirootfs-loongarch64.tar.gz /
RUN apk add --no-cache ca-certificates tzdata

# Final conditional stage
FROM base-stage AS final
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "loong64" ]; then \
        echo "Error: Use loong64-base target for loong64 architecture" && exit 1; \
    fi
CMD ["/bin/sh"]

# Dedicated final stage for loong64
FROM loong64-base AS final-loong64
CMD ["/bin/sh"]