#!/usr/bin/env bash

#-------------------------------------------------------#
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Install & Setup Zig
###-----------------------------------------------------###

#-------------------------------------------------------#
##ENV
set -euo pipefail
ZIG_DIR="/usr/local/zig"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
#-------------------------------------------------------#

#-------------------------------------------------------#
##Architecture
case "$(uname -m)" in
    aarch64) ARCH="aarch64" ;;
    armv7l) ARCH="armv7a" ;;
    i?86) ARCH="i386" ;;
    riscv64) ARCH="riscv64" ;;
    x86_64) ARCH="x86_64" ;;
    *) echo "[-] Unsupported architecture: $(uname -m)" && exit 1 ;;
esac
echo "[+] Installing Zig for linux-${ARCH}..."
#-------------------------------------------------------#

#-------------------------------------------------------#
##Deps
for cmd in curl jq tar; do
    command -v "${cmd}" >/dev/null || { echo "[-] Missing: ${cmd}" && exit 1; }
done
#-------------------------------------------------------#

#-------------------------------------------------------#
##Install
#Clean Existing
[[ -d "${ZIG_DIR}" ]] && sudo rm -rf "${ZIG_DIR}"
#Get URL
cd "${TEMP_DIR}"
DOWNLOAD_URL="$(curl -qfsSL "https://ziglang.org/download/index.json" | \
               jq -r ".master.\"${ARCH}-linux\".tarball // empty")"
[[ -z "${DOWNLOAD_URL}" || "${DOWNLOAD_URL}" == "null" ]] && { 
    echo "[-] No release found for $ARCH-linux" && exit 1; 
}
#Download
for i in {1..3}; do
    curl -w "(DL) <== %{url}\n" -fSL "${DOWNLOAD_URL}" -o "zig.tar.xz" && break
    [[ $i -eq 3 ]] && { echo "[-] Download failed" && exit 1; }
    echo "[!] Retry $i/3..."
done
#Extract and install
tar -xf "zig.tar.xz"
ZIG_SRC="$(find . -maxdepth 1 -type d -name "*zig*" | head -1)"
[[ -z "${ZIG_SRC}" ]] && { echo "[-] Extract failed" && exit 1; }
sudo mkdir -p "${ZIG_DIR}"
sudo cp -r "${ZIG_SRC}"/* "${ZIG_DIR}"/
#-------------------------------------------------------#

#-------------------------------------------------------#
##Check
export PATH="${ZIG_DIR}:${PATH}"
hash -r &>/dev/null
command -v zig >/dev/null || { echo "[-] Installation failed" && exit 1; }
echo "[+] Success! Zig version: $(zig version)"
sudo ldconfig 2>/dev/null || true
#-------------------------------------------------------#