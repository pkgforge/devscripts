#!/usr/bin/env bash
# Debian LoongArch64 Rootfs Creation Script

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/rootfs-build"
LOG_FILE="${SCRIPT_DIR}/debian-rootfs-build.log"
RETRY_COUNT=3
RETRY_DELAY=5

# Debian configuration
DEBIAN_SUITE="${DEBIAN_SUITE:-unstable}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_ARCH="loong64"
OUTPUT_FILE="${SCRIPT_DIR}/debian-${DEBIAN_SUITE}-loongarch64.tar"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DEBIAN_ROOT=""
TAR_CMD="tar"

# Logging function
log() {
    local level="$1"
    shift
    local timestamp
    timestamp="$(date --utc '+%Y-%m-%d %H:%M:%S UTC')"
    echo -e "${timestamp} [${level}] $*" | tee -a "${LOG_FILE}"
}

info() { log "${BLUE}INFO${NC}" "$@"; }
warn() { log "${YELLOW}WARN${NC}" "$@"; }
error() { log "${RED}ERROR${NC}" "$@"; }
success() { log "${GREEN}SUCCESS${NC}" "$@"; }

# Error handler
error_exit() {
    error "$1"
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    info "Cleaning up temporary files..."
    
    # Unmount proc, sys, dev if mounted
    if [[ -n "${DEBIAN_ROOT}" ]] && [[ -d "${DEBIAN_ROOT}" ]]; then
        for mount_point in proc sys dev/pts dev; do
            local full_path="${DEBIAN_ROOT}/${mount_point}"
            if mountpoint -q "${full_path}" 2>/dev/null; then
                sudo umount "${full_path}" 2>/dev/null || warn "Failed to unmount ${full_path}"
            fi
        done
        
        # Kill any remaining processes in chroot
        sudo fuser -k "${DEBIAN_ROOT}" 2>/dev/null || true
        sleep 2
    fi
    
    # Remove work directory
    if [[ -d "${WORK_DIR}" ]]; then
        sudo rm -rf "${WORK_DIR}" || warn "Failed to remove work directory"
    fi
}

# Trap for cleanup
trap cleanup EXIT INT TERM

# Retry function with exponential backoff
retry() {
    local count=0
    local delay=$RETRY_DELAY
    while [[ $count -lt $RETRY_COUNT ]]; do
        if "$@"; then
            return 0
        fi
        count=$((count + 1))
        if [[ $count -lt $RETRY_COUNT ]]; then
            warn "Command failed, retrying in ${delay}s... (attempt $count/$RETRY_COUNT)"
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
    done
    return 1
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root directly. It will use sudo when needed."
        exit 1
    fi
    
    # Check if sudo is available
    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is required but not installed"
        exit 1
    fi
    
    # Test sudo access
    if ! sudo -n true 2>/dev/null; then
        info "This script requires sudo access. You may be prompted for your password."
        if ! sudo -v; then
            error_exit "Failed to obtain sudo access"
        fi
    fi
}

# Check if LoongArch64 is available in Debian repositories
check_loongarch_support() {
    local suite="$1"
    local mirror="$2"
    
    info "Checking LoongArch64 support for suite: $suite"
    
    # Define available debian-ports mirrors
    local ports_mirrors=(
        "http://deb.debian.org/debian-ports"
        "http://ftp.ports.debian.org/debian-ports"
        "https://deb.debian.org/debian-ports"
    )
    
    # Define suites to try for LoongArch64 (in order of preference)
    local suites_to_try=("$suite")
    
    # Add fallback suites if not already specified
    case "$suite" in
        "experimental"|"unreleased"|"sid"|"unstable")
            suites_to_try+=("experimental" "unreleased" "sid" "unstable")
            ;;
        *)
            suites_to_try+=("experimental" "unreleased" "sid" "unstable")
            ;;
    esac
    
    # Remove duplicates while preserving order
    local unique_suites=()
    for suite_candidate in "${suites_to_try[@]}"; do
        local found=0
        for existing in "${unique_suites[@]}"; do
            if [[ "$existing" == "$suite_candidate" ]]; then
                found=1
                break
            fi
        done
        if [[ $found -eq 0 ]]; then
            unique_suites+=("$suite_candidate")
        fi
    done
    
    # Try each combination of mirror and suite
    for suite_candidate in "${unique_suites[@]}"; do
        for ports_mirror in "${ports_mirrors[@]}"; do
            info "Checking LoongArch64 availability: $ports_mirror/dists/$suite_candidate"
            
            local release_url="${ports_mirror}/dists/${suite_candidate}/Release"
            
            # Check if the Release file exists and contains loong64
            if curl -sf --connect-timeout 10 --max-time 30 "$release_url" 2>/dev/null | grep -q "loong64"; then
                success "Found LoongArch64 support in debian-ports"
                info "Using suite: $suite_candidate"
                info "Using mirror: $ports_mirror"
                
                # Update global variables
                DEBIAN_MIRROR="$ports_mirror"
                DEBIAN_SUITE="$suite_candidate"
                
                return 0
            fi
            
            # Also check if there's a Packages file directly
            local packages_url="${ports_mirror}/dists/${suite_candidate}/main/binary-loong64/Packages.gz"
            if curl -sf --connect-timeout 10 --max-time 30 --head "$packages_url" >/dev/null 2>&1; then
                success "Found LoongArch64 packages in debian-ports"
                info "Using suite: $suite_candidate"
                info "Using mirror: $ports_mirror"
                
                DEBIAN_MIRROR="$ports_mirror"
                DEBIAN_SUITE="$suite_candidate"
                
                return 0
            fi
        done
    done
    
    # If we get here, no LoongArch64 support was found
    error "LoongArch64 (loong64) architecture not available in any Debian repositories"
    error ""
    error "Searched the following combinations:"
    for suite_candidate in "${unique_suites[@]}"; do
        for ports_mirror in "${ports_mirrors[@]}"; do
            error "  - $ports_mirror (suite: $suite_candidate)"
        done
    done
    error ""
    error "This may be because:"
    error "  1. LoongArch64 support is very experimental and limited"
    error "  2. Network connectivity issues preventing repository access"
    error "  3. Debian ports infrastructure is temporarily unavailable"
    error "  4. LoongArch64 packages are not yet available for any suite"
    error ""
    info "Possible solutions:"
    info "  - Check network connectivity and try again later"
    info "  - Visit https://wiki.debian.org/Ports for current status"
    info "  - Check https://buildd.debian.org/status/architecture.php?a=loong64"
    info "  - Consider using a different architecture like riscv64 or arm64"
    info "  - Monitor https://lists.debian.org/debian-ports/ for updates"
    
    return 1
}

# Verify system requirements
check_requirements() {
    info "Checking system requirements..."
    
    local missing_tools=()
    
    # Essential tools (check debootstrap with sudo since it might only be in /usr/sbin)
    for tool in wget curl tar gzip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    # Check debootstrap with sudo since it's often only available as root
    if ! sudo which debootstrap >/dev/null 2>&1 && ! command -v debootstrap >/dev/null 2>&1; then
        missing_tools+=("debootstrap")
    fi
    
    # Check if we have bsdtar (better for some archives)
    if command -v bsdtar >/dev/null 2>&1; then
        TAR_CMD="bsdtar"
        info "Using bsdtar for better archive handling"
    else
        TAR_CMD="tar"
        info "Using standard tar"
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
        info "Please install them using your package manager:"
        info "  Ubuntu/Debian: sudo apt update && sudo apt install ${missing_tools[*]}"
        info "  RHEL/CentOS/Fedora: sudo dnf install ${missing_tools[*]}"
        info "  Arch: sudo pacman -S ${missing_tools[*]}"
        exit 1
    fi
    
    # Check available disk space (at least 3GB for Debian)
    local available_space
    available_space="$(df "${SCRIPT_DIR}" | awk 'NR==2 {print $4}')"
    if [[ $available_space -lt 3145728 ]]; then # 3GB in KB
        warn "Low disk space detected. At least 3GB recommended for Debian rootfs creation."
    fi
    
    # Check debootstrap version (use sudo)
    local debootstrap_version
    debootstrap_version="$(sudo debootstrap --version 2>/dev/null | head -1 || echo 'unknown')"
    info "Using debootstrap: $debootstrap_version"
    
    success "System requirements check completed"
}

# Setup DNS configuration with reliable public DNS servers
setup_dns() {
    local chroot_dir="$1"
    
    info "Setting up DNS configuration..."
    
    # Create a reliable resolv.conf with multiple DNS providers
    sudo tee "${chroot_dir}/etc/resolv.conf" > /dev/null << 'EOF'
# Reliable public DNS servers
nameserver 1.1.1.1      # Cloudflare primary
nameserver 1.0.0.1      # Cloudflare secondary
nameserver 8.8.8.8      # Google primary
nameserver 8.8.4.4      # Google secondary
nameserver 9.9.9.9      # Quad9 primary

# Options for better reliability
options timeout:2
options attempts:3
options rotate
EOF
    
    info "DNS configuration completed with reliable public DNS servers"
}

# Setup chroot environment
setup_chroot() {
    local chroot_dir="$1"
    
    info "Setting up chroot environment..."
    
    # Create mount points if they don't exist
    sudo mkdir -p "${chroot_dir}"/{proc,sys,dev/pts}
    
    # Mount essential filesystems with proper error handling
    if ! mountpoint -q "${chroot_dir}/proc" 2>/dev/null; then
        sudo mount -t proc proc "${chroot_dir}/proc" || error_exit "Failed to mount proc"
    fi
    
    if ! mountpoint -q "${chroot_dir}/sys" 2>/dev/null; then
        sudo mount -t sysfs sysfs "${chroot_dir}/sys" || error_exit "Failed to mount sys"
    fi
    
    if ! mountpoint -q "${chroot_dir}/dev" 2>/dev/null; then
        sudo mount --bind /dev "${chroot_dir}/dev" || error_exit "Failed to bind mount dev"
    fi
    
    if ! mountpoint -q "${chroot_dir}/dev/pts" 2>/dev/null; then
        sudo mount -t devpts devpts "${chroot_dir}/dev/pts" || error_exit "Failed to mount devpts"
    fi
    
    # Setup DNS configuration with hardcoded reliable servers
    setup_dns "${chroot_dir}"
    
    # Prevent services from starting during package installation
    sudo tee "${chroot_dir}/usr/sbin/policy-rc.d" > /dev/null << 'EOF'
#!/bin/sh
# Prevent services from starting in chroot
echo "All runlevel operations denied by policy" >&2
exit 101
EOF
    sudo chmod +x "${chroot_dir}/usr/sbin/policy-rc.d"
    
    # Create a minimal environment file
    sudo tee "${chroot_dir}/etc/environment" > /dev/null << 'EOF'
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
LANG="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
DEBIAN_FRONTEND="noninteractive"
EOF
}

# Validate Debian suite
validate_suite() {
    local suite="$1"
    local valid_suites=("oldstable" "stable" "testing" "unstable" "sid" "experimental" "unreleased" "bookworm" "trixie" "forky")
    
    for valid_suite in "${valid_suites[@]}"; do
        if [[ "$suite" == "$valid_suite" ]]; then
            return 0
        fi
    done
    
    warn "Suite '$suite' may not be standard. Continuing anyway..."
    return 0
}

# Create Debian rootfs
create_debian_rootfs() {
    info "Creating Debian ${DEBIAN_SUITE} LoongArch64 rootfs..."
    
    # Validate suite
    validate_suite "$DEBIAN_SUITE"
    
    # Check LoongArch64 availability
    if ! check_loongarch_support "$DEBIAN_SUITE" "$DEBIAN_MIRROR"; then
        error_exit "LoongArch64 support not available"
    fi
    
    DEBIAN_ROOT="${WORK_DIR}/debian-rootfs"
    
    # Clean up any existing work directory
    if [[ -d "${WORK_DIR}" ]]; then
        sudo rm -rf "${WORK_DIR}"
    fi
    
    mkdir -p "${WORK_DIR}"
    
    # Create initial rootfs with debootstrap
    info "Running debootstrap with mirror: ${DEBIAN_MIRROR}"
    info "This may take 15-30 minutes..."
    
    local debootstrap_cmd=(
        sudo debootstrap
        --arch="${DEBIAN_ARCH}"
        --variant=minbase
        --include="apt-utils,ca-certificates,coreutils,curl,grep,jq,locales,tar,wget,gnupg,lsb-release"
        --exclude="systemd-timesyncd"
        "${DEBIAN_SUITE}"
        "${DEBIAN_ROOT}"
        "${DEBIAN_MIRROR}"
    )
    
    # Try the main command first
    if ! retry "${debootstrap_cmd[@]}"; then
        # If that fails, try with some different approaches
        warn "Primary debootstrap attempt failed"
        
        # Try with experimental if we're not already using it
        if [[ "$DEBIAN_SUITE" != "experimental" ]]; then
            info "Trying with experimental suite..."
            local debootstrap_cmd_exp=(
                sudo debootstrap
                --arch="${DEBIAN_ARCH}"
                --variant=minbase
                --include="apt-utils,ca-certificates,coreutils,curl,tar,wget"
                "experimental"
                "${DEBIAN_ROOT}"
                "${DEBIAN_MIRROR}"
            )
            
            if retry "${debootstrap_cmd_exp[@]}"; then
                DEBIAN_SUITE="experimental"
                info "Successfully switched to experimental suite"
            fi
        fi
        
        # If experimental didn't work, try with different component
        if [[ ! -d "${DEBIAN_ROOT}/bin" ]]; then
            info "Trying with main,contrib components..."
            local debootstrap_cmd_alt=(
                sudo debootstrap
                --arch="${DEBIAN_ARCH}"
                --variant=minbase
                --components="main,contrib"
                --include="apt-utils,ca-certificates,coreutils,curl,tar,wget"
                "${DEBIAN_SUITE}"
                "${DEBIAN_ROOT}"
                "${DEBIAN_MIRROR}"
            )
            
            if ! retry "${debootstrap_cmd_alt[@]}"; then
                # Last resort: try with minimal packages
                warn "Trying with minimal package set..."
                local debootstrap_cmd_minimal=(
                    sudo debootstrap
                    --arch="${DEBIAN_ARCH}"
                    --variant=minbase
                    "${DEBIAN_SUITE}"
                    "${DEBIAN_ROOT}"
                    "${DEBIAN_MIRROR}"
                )
                
                if ! retry "${debootstrap_cmd_minimal[@]}"; then
                    error_exit "Failed to create Debian rootfs with debootstrap after multiple attempts"
                fi
            fi
        fi
    fi
    
    # Verify that the rootfs was created successfully
    if [[ ! -d "${DEBIAN_ROOT}" ]] || [[ ! -f "${DEBIAN_ROOT}/etc/debian_version" ]]; then
        error_exit "Debian rootfs creation failed - missing essential files"
    fi
    
    # Setup chroot environment
    setup_chroot "${DEBIAN_ROOT}"
    
    # Configure the rootfs
    info "Configuring Debian rootfs..."
    
    # Set up locale with error handling
    sudo chroot "${DEBIAN_ROOT}" /bin/bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=C
        
        # Generate locale
        echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
        locale-gen || echo 'Warning: locale-gen failed'
        echo 'LANG=en_US.UTF-8' > /etc/default/locale
        
        # Set timezone to UTC
        echo 'UTC' > /etc/timezone
        ln -sf /usr/share/zoneinfo/UTC /etc/localtime || true
    " || warn "Locale configuration partially failed"
    
    # Update package lists and upgrade with better error handling
    info "Updating packages and installing essential tools..."
    sudo chroot "${DEBIAN_ROOT}" /bin/bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        
        # Update package lists
        apt update -y
        
        # Upgrade existing packages
        apt upgrade -y
        
        # Install essential packages
        apt install -y --no-install-recommends \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            jq \
            lsb-release \
            wget \
            vim-tiny \
            nano \
            less \
            procps \
            psmisc \
            iproute2 \
            iputils-ping \
            netbase \
            tzdata
            
        # Update CA certificates
        update-ca-certificates || true
    " || error_exit "Failed to update and install packages"
    
    # Clean up package cache and temporary files
    info "Cleaning up rootfs..."
    sudo chroot "${DEBIAN_ROOT}" /bin/bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        
        # Clean package cache
        apt autoremove -y --purge
        apt autoclean
        apt clean
        
        # Remove package lists (they'll be regenerated when needed)
        rm -rf /var/lib/apt/lists/*
        
        # Clean temporary files
        rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
        rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true
        
        # Clean logs but keep directories
        find /var/log -type f -name '*.log' -delete 2>/dev/null || true
        find /var/log -type f -name '*.log.*' -delete 2>/dev/null || true
        
        # Clean bash history
        history -c 2>/dev/null || true
        > /root/.bash_history 2>/dev/null || true
        
        # Remove policy-rc.d
        rm -f /usr/sbin/policy-rc.d
        
        # Keep DNS configuration for container use
        # (Don't remove resolv.conf as it's needed in containers)
        
        # Set proper permissions
        chmod 644 /etc/passwd /etc/group /etc/shadow 2>/dev/null || true
        chmod 755 /root /home 2>/dev/null || true
    " || warn "Cleanup partially failed"
    
    # Create archive
    info "Creating tar archive: ${OUTPUT_FILE}"
    
    # Change to the rootfs directory for proper tar creation
    cd "${DEBIAN_ROOT}"
    
    # Create the tar archive with proper options
    if ! sudo ${TAR_CMD} -cf "${OUTPUT_FILE}" --numeric-owner --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/pts/*' .; then
        error_exit "Failed to create tar archive"
    fi
    
    # Set proper ownership of the output file
    sudo chown "$(id -u):$(id -g)" "${OUTPUT_FILE}"
    
    # Verify the created archive
    info "Verifying created archive..."
    if [[ ! -f "${OUTPUT_FILE}" ]]; then
        error_exit "Output file was not created"
    fi
    
    if [[ ! -s "${OUTPUT_FILE}" ]]; then
        error_exit "Output file is empty"
    fi
    
    # Test archive integrity
    if ! ${TAR_CMD} -tf "${OUTPUT_FILE}" >/dev/null 2>&1; then
        error_exit "Created archive is corrupted"
    fi
    
    local file_size
    file_size="$(du -h "${OUTPUT_FILE}" | cut -f1)"
    local file_count
    file_count="$(${TAR_CMD} -tf "${OUTPUT_FILE}" | wc -l)"
    
    success "Debian ${DEBIAN_SUITE} LoongArch64 rootfs created successfully!"
    success "Output file: ${OUTPUT_FILE}"
    success "Size: ${file_size}"
    success "Files: ${file_count}"
    
    # Display information about the rootfs
    info "Rootfs information:"
    local arch_info
    local debian_version
    arch_info="$(sudo chroot "${DEBIAN_ROOT}" dpkg --print-architecture 2>/dev/null || echo 'unknown')"
    debian_version="$(sudo chroot "${DEBIAN_ROOT}" cat /etc/debian_version 2>/dev/null || echo 'unknown')"
    
    echo "  Architecture: ${arch_info}"
    echo "  Debian version: ${debian_version}"
    echo "  Suite: ${DEBIAN_SUITE}"
    echo "  Mirror used: ${DEBIAN_MIRROR}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create a Debian LoongArch64 rootfs using debootstrap.

OPTIONS:
    -s, --suite SUITE       Debian suite (default: unstable)
                           Valid: experimental, unreleased, unstable, sid, testing, stable
                           Note: LoongArch64 is mainly available in experimental/debian-ports
    -m, --mirror URL        Debian mirror URL (default: http://deb.debian.org/debian)
    -o, --output FILE       Output file path (default: debian-SUITE-loongarch64.tar)
    -h, --help             Show this help message
    -v, --verbose          Enable verbose output

EXAMPLES:
    $0                      # Create unstable rootfs (will search for LoongArch64)
    $0 -s experimental      # Create experimental rootfs (recommended for LoongArch64)
    $0 -s unreleased        # Try unreleased packages
    $0 -s sid -o my-rootfs.tar
    $0 -s testing -m http://deb.debian.org/debian-ports
    
ENVIRONMENT VARIABLES:
    DEBIAN_SUITE           Override default suite
    DEBIAN_MIRROR          Override default mirror

The created rootfs can be used in Docker containers:
    docker import ${OUTPUT_FILE##*/} debian-loongarch64:latest

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--suite)
                if [[ -z "${2:-}" ]]; then
                    error "Suite option requires a value"
                    exit 1
                fi
                DEBIAN_SUITE="$2"
                shift 2
                ;;
            -m|--mirror)
                if [[ -z "${2:-}" ]]; then
                    error "Mirror option requires a value"
                    exit 1
                fi
                DEBIAN_MIRROR="$2"
                shift 2
                ;;
            -o|--output)
                if [[ -z "${2:-}" ]]; then
                    error "Output option requires a value"
                    exit 1
                fi
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Update output file path if suite was changed and output wasn't explicitly set
    if [[ "${OUTPUT_FILE}" == "${SCRIPT_DIR}/debian-unstable-loongarch64.tar" ]] && [[ "${DEBIAN_SUITE}" != "unstable" ]]; then
        OUTPUT_FILE="${SCRIPT_DIR}/debian-${DEBIAN_SUITE}-loongarch64.tar"
    fi
    
    # Validate output file path
    if [[ -e "${OUTPUT_FILE}" ]]; then
        warn "Output file ${OUTPUT_FILE} already exists and will be overwritten"
    fi
}

# Main function
main() {
    # Initialize log file
    echo "=== Debian LoongArch64 Rootfs Build Log ===" > "${LOG_FILE}"
    
    info "Starting Debian LoongArch64 rootfs creation..."
    info "Suite: ${DEBIAN_SUITE}"
    info "Mirror: ${DEBIAN_MIRROR}"
    info "Output: ${OUTPUT_FILE}"
    info "Architecture: ${DEBIAN_ARCH}"
    
    check_root
    check_requirements
    create_debian_rootfs
    
    success "All done! Rootfs available at: ${OUTPUT_FILE}"
    info "You can now use this rootfs in your Docker environment:"
    info "  docker import ${OUTPUT_FILE##*/} debian-loongarch64:${DEBIAN_SUITE}"
    info "  docker run -it debian-loongarch64:${DEBIAN_SUITE} /bin/bash"
    info ""
    info "Build log saved to: ${LOG_FILE}"
}

# Validate environment before starting
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    echo "Error: This script requires Bash 4.0 or later" >&2
    exit 1
fi

# Parse arguments and run
parse_args "$@"
main