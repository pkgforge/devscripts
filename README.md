#### Container Images
> ==> https://hub.docker.com/r/pkgforge/alpine-base-mimalloc ([`Alpine Base Image with Mimalloc`](https://github.com/tweag/rust-alpine-mimalloc))<br> 
> ==> https://hub.docker.com/r/pkgforge/alpine-builder ([`Alpine Build Image`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/alpine-builder.dockerfile))<br> 
> ==> https://hub.docker.com/r/pkgforge/alpine-builder-mimalloc ([`Alpine Builder Image using Mimalloc`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/alpine-builder.dockerfile))<br> 
> ==> https://hub.docker.com/r/pkgforge/archlinux ([`ArchLinux Base Image`](https://github.com/pkgforge-dev/docker-archlinux))<br> 
> ==> https://hub.docker.com/r/pkgforge/archlinux-builder ([`ArchLinux Builder Image`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/archlinux-builder.dockerfile))<br> 
> ==> https://hub.docker.com/r/pkgforge/debian-builder-unstable ([`Debian Builder Image`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/debian-builder-unstable.dockerfile))<br> 
> ==> https://hub.docker.com/r/pkgforge/gh-runner-aarch64-ubuntu ([`GHA Runner Image`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/aarch64-ubuntu.dockerfile))<br> 
> ==> https://hub.docker.com/r/pkgforge/gh-runner-x86_64-ubuntu ([`GHA Runner Image`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/x86_64-ubuntu.dockerfile))<br> 
> ==> https://hub.docker.com/r/pkgforge/ubuntu-builder ([`Ubuntu Builder Image`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/ubuntu-builder.dockerfile))<br> 
> ==> https://hub.docker.com/r/pkgforge/ubuntu-systemd-base ([`Ubuntu Dev Machine Image`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/ubuntu-systemd-base.dockerfile))<br>

#### ROOTFS
> ==> https://github.com/pkgforge/devscripts/releases/download/archlinux-base_aarch64/rootfs.tar ([`boostrap.sh`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/bootstrap/archlinux.sh))<br>
> ==> https://github.com/pkgforge/devscripts/releases/download/archlinux-base_x86_64/rootfs.tar ([`boostrap.sh`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/bootstrap/archlinux.sh))<br>
> ==> https://github.com/pkgforge/devscripts/releases/download/artix-base_x86_64/rootfs.tar ([`boostrap.sh`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/bootstrap/artix.sh))<br>
> ==> https://github.com/pkgforge/devscripts/releases/download/cachyos-base_x86_64/rootfs.tar ([`boostrap.sh`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/bootstrap/cachyos.sh))<br>
> ==> https://github.com/pkgforge/devscripts/releases/download/eweos-base_aarch64/rootfs.tar ([`boostrap.sh`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/bootstrap/eweos.sh))<br>
> ==> https://github.com/pkgforge/devscripts/releases/download/eweos-base_x86_64/rootfs.tar ([`boostrap.sh`](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/bootstrap/eweos.sh))<br>

#### Scripts
> [!WARNING]
> These scripts are meant for [@pkgforge](https://github.com/pkgforge)'s internal use only. **They might not work outside of [@pkgforge](https://github.com/pkgforge)'s context**
- [Bootstrapping using Static Binaries](https://github.com/pkgforge/devscripts/blob/main/Linux/install_bins_curl.sh)
- [Debloating Github Runners to Maximize Storage](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/debloat_ubuntu.sh)
- [Managing Self Hosted Github Runners](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/manage_linux.sh)
- [Provisioning Self Hosted Github Runners](https://github.com/pkgforge/devscripts/blob/main/Github/Runners/run_linux.sh)
- [.profile used by all containers](https://github.com/pkgforge/devscripts/blob/main/Linux/.bashrc)

#### Workflows
- [![🐬 Push Bootstrap Images (aarch64) 🐬](https://github.com/pkgforge/devscripts/actions/workflows/build_bootstrap_images_aarch64.yaml/badge.svg)](https://github.com/pkgforge/devscripts/actions/workflows/build_bootstrap_images_aarch64.yaml)
- [![🐬 Push Bootstrap Images (x86_64) 🐬](https://github.com/pkgforge/devscripts/actions/workflows/build_bootstrap_images_x86_64.yaml/badge.svg)](https://github.com/pkgforge/devscripts/actions/workflows/build_bootstrap_images_x86_64.yaml)
- [![🐬 Build Alpine Mimalloc Images for DockerHub 🐬](https://github.com/pkgforge/devscripts/actions/workflows/build_alpine_base_mimalloc.yaml/badge.svg)](https://github.com/pkgforge/devscripts/actions/workflows/build_alpine_base_mimalloc.yaml)
- [![🐬 Builds ArchLinux Images for DockerHub 🐬](https://github.com/pkgforge-dev/docker-archlinux/actions/workflows/build-deploy.yml/badge.svg)](https://github.com/pkgforge-dev/docker-archlinux/actions/workflows/build-deploy.yml)
- [![🐬 Builds GH-Runner Images (Self-Hosted) DockerHub 🐬](https://github.com/pkgforge/devscripts/actions/workflows/build_gh_runner_images.yaml/badge.svg)](https://github.com/pkgforge/devscripts/actions/workflows/build_gh_runner_images.yaml)
