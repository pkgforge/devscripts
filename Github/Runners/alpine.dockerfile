# syntax=docker/dockerfile:1
#------------------------------------------------------------------------------------#

ARG TARGETARCH

# Default stage for most architectures
FROM alpine:edge AS base-standard
RUN apk add --no-cache ca-certificates tzdata
CMD ["/bin/sh"]

# Special stage for loong64
FROM scratch AS base-loong64
ADD alpine-minirootfs-loongarch64.tar.gz /
RUN apk add --no-cache ca-certificates tzdata
CMD ["/bin/sh"]

# Final stage with conditional logic
FROM scratch AS final
COPY --from=base-${TARGETARCH:-standard} / /
# For loong64, this will copy from base-loong64
# For others, this will copy from base-standard