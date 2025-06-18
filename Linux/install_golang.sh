#!/usr/bin/env bash

#-------------------------------------------------------#
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Install & Setup Go
###-----------------------------------------------------###

#-------------------------------------------------------#
##ENV
set -euo pipefail
GO_DIR="${HOME}/.go"
GO_BIN_DIR="${HOME}/go/bin"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
#-------------------------------------------------------#

#-------------------------------------------------------#
##Architecture
case "$(uname -m)" in
    aarch64) ARCH="arm64" ;;
    armv6l) ARCH="armv6l" ;;
    armv7l) ARCH="armv6l" ;;
    i?86) ARCH="386" ;;
    s390x) ARCH="s390x" ;;
    ppc64le) ARCH="ppc64le" ;;
    x86_64) ARCH="amd64" ;;
    *) echo "[-] Unsupported architecture: $(uname -m)" && exit 1 ;;
esac
echo "[+] Installing Go for linux-${ARCH}..."
#-------------------------------------------------------#

#-------------------------------------------------------#
##Deps
for cmd in curl find grep tar; do
    command -v "${cmd}" >/dev/null || { echo "[-] Missing: ${cmd}" && exit 1; }
done
#-------------------------------------------------------#

#-------------------------------------------------------#
##Install
#Check if Go is already installed and remove it
if command -v go >/dev/null 2>&1; then
    EXISTING_GO="$(command -v go)"
    EXISTING_GOROOT="$(go env GOROOT 2>/dev/null || echo "")"
    echo "[!] Found existing Go installation at: ${EXISTING_GO}"
    [[ -n "${EXISTING_GOROOT}" ]] && echo "[!] GOROOT: ${EXISTING_GOROOT}"
    
    # Remove from common system locations
    for sys_path in "/usr/local/go" "/usr/go" "/opt/go"; do
        [[ -d "${sys_path}" ]] && { echo "[!] Removing system Go: ${sys_path}" && sudo rm -rf "${sys_path}"; }
    done
    
    # Remove from user locations
    [[ -n "${EXISTING_GOROOT}" && -d "${EXISTING_GOROOT}" && "${EXISTING_GOROOT}" != "${GO_DIR}" ]] && {
        echo "[!] Removing existing GOROOT: ${EXISTING_GOROOT}"
        rm -rf "${EXISTING_GOROOT}"
    }
fi
#Clean Existing
[[ -d "${GO_DIR}" ]] && rm -rf "${GO_DIR}"
[[ -d "${GO_BIN_DIR}" ]] && rm -rf "${GO_BIN_DIR}"
#Get Latest Version
cd "${TEMP_DIR}"
LATEST_VERSION="$(curl -qfsSL "https://golang.org/VERSION?m=text" | grep -Ev '[0-9]{4}[^0-9]?[0-1][0-9][^0-9]?[0-3][0-9]' | head -1 | tr -d '"'\''[:space:]')"
[[ -z "${LATEST_VERSION}" || "${LATEST_VERSION}" == "null" ]] && { 
    echo "[-] Failed to get latest Go version" && exit 1; 
}
DOWNLOAD_URL="https://golang.org/dl/${LATEST_VERSION}.linux-${ARCH}.tar.gz"
echo "[+] Downloading Go ${LATEST_VERSION}..."
#Download
for i in {1..3}; do
    curl -w "(DL) <== %{url}\n" -fSL "${DOWNLOAD_URL}" -o "go.tar.gz" && break
    [[ $i -eq 3 ]] && { echo "[-] Download failed" && exit 1; }
    echo "[!] Retry $i/3..."
done
#Extract and install
tar -xzf "go.tar.gz"
GO_SRC="$(find "." -maxdepth 1 -type d -name "*go*" | head -1)"
[[ -z "${GO_SRC}" || ! -d "${GO_SRC}" ]] && { echo "[-] Extract failed" && exit 1; }
mkdir -p "${HOME}"
mv "${GO_SRC}" "${GO_DIR}"
#Create GOPATH bin directory
mkdir -p "${GO_BIN_DIR}"
#-------------------------------------------------------#

#-------------------------------------------------------#
##Check
export GOROOT="${GO_DIR}"
export GOPATH="${HOME}/go"
export PATH="${GO_DIR}/bin:${GO_BIN_DIR}:${PATH}"
hash -r &>/dev/null
command -v go >/dev/null || { echo "[-] Installation failed" && exit 1; }
echo "[+] Success! Go version: $(go version)"
echo "[+] GOROOT: ${GOROOT}"
echo "[+] GOPATH: ${GOPATH}"
echo "[|] PATH: export PATH=\"${GO_DIR}/bin:${GO_BIN_DIR}:\${PATH}\""
#-------------------------------------------------------#
