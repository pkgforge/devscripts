group "default" {
  targets = ["alpine", "alpine-loong64"]
}

target "alpine" {
  context = "./"
  dockerfile = "alpine.dockerfile"
  target = "final"
  platforms = ["linux/amd64", "linux/arm64", "linux/riscv64"]
  tags = [
    "pkgforge/alpine:edge",
    "pkgforge/alpine:edge-${DOCKER_TAG}",
    "ghcr.io/pkgforge/devscripts/alpine:edge",
    "ghcr.io/pkgforge/devscripts/alpine:edge-${DOCKER_TAG}"
  ]
  output = ["type=registry,compression=zstd,compression-level=22"]
}

target "alpine-loong64" {
  context = "./"
  dockerfile = "alpine.dockerfile"
  target = "final-loong64"
  platforms = ["linux/loong64"]
  tags = [
    "pkgforge/alpine:edge-loong64",
    "pkgforge/alpine:edge-${DOCKER_TAG}-loong64",
    "ghcr.io/pkgforge/devscripts/alpine:edge-loong64",
    "ghcr.io/pkgforge/devscripts/alpine:edge-${DOCKER_TAG}-loong64"
  ]
  output = ["type=registry,compression=zstd,compression-level=22"]
}
