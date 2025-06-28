#!/usr/bin/env bash
# rbuilder - A minimal alternative to cross-rs/cross
# Usage: rbuilder [+toolchain] <cargo-subcommand> [options...]

set -euo pipefail

# Constants
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly VERSION="1.0.0"
readonly DEFAULT_WORKSPACE="/workspace"

# Global variables
declare -g CONTAINER_ENGINE=""
declare -g USE_SUDO=""
declare -g TOOLCHAIN="stable"
declare -g RUST_TARGET=""
declare -g CONTAINER_IMAGE=""
declare -g CONTAINER_PLATFORM=""
declare -g WORKSPACE_DIR="${PWD}"
declare -g ARTIFACT_DIR=""
declare -g CONTAINER_ID=""
declare -a CARGO_ARGS=()
declare -a MOUNT_ARGS=()
declare -a ENV_ARGS=()

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    [[ "${RBUILDER_QUIET:-0}" == "1" ]] && return 0
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    [[ "${RBUILDER_QUIET:-0}" == "1" ]] && return 0
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_verbose() {
    [[ "${RBUILDER_VERBOSE:-0}" == "1" ]] || return 0
    echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [[ -n "${CONTAINER_ID}" ]]; then
        log_verbose "Cleaning up container: ${CONTAINER_ID}"
        ${USE_SUDO} ${CONTAINER_ENGINE} rm -f "${CONTAINER_ID}" &>/dev/null || true
    fi
    
    # Fix permissions on mounted directories
    if [[ -n "${ARTIFACT_DIR}" && -d "${ARTIFACT_DIR}" ]]; then
        log_verbose "Fixing permissions on artifact directory: ${ARTIFACT_DIR}"
        sudo chown -R "$(id -u):$(id -g)" "${ARTIFACT_DIR}" 2>/dev/null || true
    fi
    
    log_verbose "Fixing permissions on workspace: ${WORKSPACE_DIR}"
    sudo chown -R "$(id -u):$(id -g)" "${WORKSPACE_DIR}" 2>/dev/null || true
    
    exit ${exit_code}
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Help function
show_help() {
    cat << EOF
${SCRIPT_NAME} v${VERSION} - A minimal alternative to cross-rs/cross

USAGE:
    ${SCRIPT_NAME} [+toolchain] <cargo-subcommand> [options...]

EXAMPLES:
    ${SCRIPT_NAME} build --release --target x86_64-unknown-linux-musl
    ${SCRIPT_NAME} +nightly build --target aarch64-unknown-linux-gnu
    RBUILD_STATIC=1 ${SCRIPT_NAME} build --release --target x86_64-unknown-linux-musl

ENVIRONMENT VARIABLES:
    RBUILD_STATIC=1         Enable static linking optimizations
    RBUILDER_QUIET=1        Quiet mode (suppress rbuilder output)
    RBUILDER_VERBOSE=1      Verbose mode (show detailed output)
    RUSTFLAGS              Custom RUSTFLAGS (passed through to container)

SUPPORTED TARGETS:
    x86_64-unknown-linux-musl    (Alpine x86_64)
    x86_64-unknown-linux-gnu     (Debian x86_64)
    aarch64-unknown-linux-musl   (Alpine aarch64)
    aarch64-unknown-linux-gnu    (Debian aarch64)
    riscv64gc-unknown-linux-musl (Alpine riscv64)
    riscv64gc-unknown-linux-gnu  (Debian riscv64)
    loongarch64-unknown-linux-musl (Alpine loongarch64)
    loongarch64-unknown-linux-gnu  (Debian loongarch64)

EOF
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Detect container engine
detect_container_engine() {
    if command_exists docker; then
        CONTAINER_ENGINE="docker"
        log_verbose "Found Docker"
    elif command_exists podman; then
        CONTAINER_ENGINE="podman"
        log_verbose "Found Podman"
    else
        log_error "Neither Docker nor Podman found. Please install one of them."
        exit 1
    fi
    
    # Test if we can run without sudo
    if ${CONTAINER_ENGINE} info &>/dev/null; then
        USE_SUDO=""
        log_verbose "Container engine works without sudo"
    elif sudo ${CONTAINER_ENGINE} info &>/dev/null; then
        USE_SUDO="sudo"
        log_verbose "Container engine requires sudo"
    else
        log_error "Cannot run ${CONTAINER_ENGINE} with or without sudo"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    # Check for qemu (for cross-platform emulation)
    if ! command_exists qemu-user-static && ! command_exists qemu-aarch64-static; then
        log_warn "QEMU user emulation not found. Cross-platform builds may fail."
        log_warn "Install with: sudo apt-get install qemu-user-static (Debian/Ubuntu)"
        log_warn "              sudo pacman -S qemu-user-static (Arch)"
    else
        log_verbose "QEMU user emulation available"
    fi
}

# Determine target and container image
determine_target_and_image() {
    # Parse cargo args to find target
    local i
    for ((i=0; i<${#CARGO_ARGS[@]}; i++)); do
        if [[ "${CARGO_ARGS[i]}" == "--target" ]]; then
            if ((i+1 < ${#CARGO_ARGS[@]})); then
                RUST_TARGET="${CARGO_ARGS[i+1]}"
                break
            fi
        elif [[ "${CARGO_ARGS[i]}" =~ ^--target=(.+)$ ]]; then
            RUST_TARGET="${BASH_REMATCH[1]}"
            break
        fi
    done
    
    # Default target if not specified
    if [[ -z "${RUST_TARGET}" ]]; then
        RUST_TARGET="aarch64-unknown-linux-musl"
        log_info "No target specified, defaulting to: ${RUST_TARGET}"
    fi
    
    # Determine container image and platform based on target
    case "${RUST_TARGET}" in
        x86_64-unknown-linux-musl)
            CONTAINER_IMAGE="ghcr.io/pkgforge/devscripts/alpine-builder:x86_64"
            CONTAINER_PLATFORM="linux/amd64"
            ;;
        x86_64-unknown-linux-gnu)
            CONTAINER_IMAGE="ghcr.io/pkgforge/devscripts/debian-builder-unstable:x86_64"
            CONTAINER_PLATFORM="linux/amd64"
            ;;
        aarch64-unknown-linux-musl)
            CONTAINER_IMAGE="ghcr.io/pkgforge/devscripts/alpine-builder:aarch64"
            CONTAINER_PLATFORM="linux/aarch64"
            ;;
        aarch64-unknown-linux-gnu)
            CONTAINER_IMAGE="ghcr.io/pkgforge/devscripts/debian-builder-unstable:aarch64"
            CONTAINER_PLATFORM="linux/aarch64"
            ;;
        riscv64gc-unknown-linux-musl)
            CONTAINER_IMAGE="ghcr.io/pkgforge/devscripts/alpine-builder:riscv64"
            CONTAINER_PLATFORM="linux/riscv64"
            ;;
        riscv64gc-unknown-linux-gnu)
            CONTAINER_IMAGE="ghcr.io/pkgforge/devscripts/debian-builder-unstable:riscv64"
            CONTAINER_PLATFORM="linux/riscv64"
            ;;
        loongarch64-unknown-linux-musl)
            CONTAINER_IMAGE="ghcr.io/pkgforge/devscripts/alpine-builder:loongarch64"
            CONTAINER_PLATFORM="linux/loong64"
            ;;
        loongarch64-unknown-linux-gnu)
            CONTAINER_IMAGE="ghcr.io/pkgforge/devscripts/debian-builder-unstable:loongarch64"
            CONTAINER_PLATFORM="linux/loong64"
            ;;
        *)
            log_error "Unsupported target: ${RUST_TARGET}"
            log_error "Supported targets: x86_64-unknown-linux-{musl,gnu}, aarch64-unknown-linux-{musl,gnu}, riscv64gc-unknown-linux-{musl,gnu}, loongarch64-unknown-linux-{musl,gnu}"
            exit 1
            ;;
    esac
    
    log_verbose "Target: ${RUST_TARGET}"
    log_verbose "Container: ${CONTAINER_IMAGE}"
    log_verbose "Platform: ${CONTAINER_PLATFORM}"
}

# Parse artifact directory
parse_artifact_dir() {
    local i
    for ((i=0; i<${#CARGO_ARGS[@]}; i++)); do
        if [[ "${CARGO_ARGS[i]}" == "--artifact-dir" ]]; then
            if ((i+1 < ${#CARGO_ARGS[@]})); then
                ARTIFACT_DIR="${CARGO_ARGS[i+1]}"
                break
            fi
        elif [[ "${CARGO_ARGS[i]}" =~ ^--artifact-dir=(.+)$ ]]; then
            ARTIFACT_DIR="${BASH_REMATCH[1]}"
            break
        fi
    done
    
    if [[ -n "${ARTIFACT_DIR}" ]]; then
        # Convert relative path to absolute
        if [[ ! "${ARTIFACT_DIR}" =~ ^/ ]]; then
            ARTIFACT_DIR="${PWD}/${ARTIFACT_DIR}"
        fi
        
        # Create directory if it doesn't exist
        mkdir -p "${ARTIFACT_DIR}"
        
        # Check if writable
        if [[ ! -w "${ARTIFACT_DIR}" ]]; then
            log_error "Artifact directory is not writable: ${ARTIFACT_DIR}"
            exit 1
        fi
        
        log_verbose "Artifact directory: ${ARTIFACT_DIR}"
    fi
}

# Generate container setup script
generate_setup_script() {
    cat << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Try to set env
if [[ -n "${HOME}" && -f "${HOME}/.bashrc" ]]; then
    source "${HOME}/.bashrc"
elif [[ -f ~/.bashrc ]]; then
    source ~/.bashrc
fi
hash -r &>/dev/null
if ! command -v cargo &>/dev/null; then
    if [[ -n "${HOME}" && -f "${HOME}/.cargo/env" ]]; then
        source "${HOME}/.cargo/env"
    elif [[ -f ~/.cargo/env ]]; then
        source ~/.cargo/env
    fi
fi
hash -r &>/dev/null

# Check required tools
check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: $1 not found in container" >&2
        exit 1
    fi
}

echo "Checking required tools..."
check_tool clang
check_tool cargo
check_tool rustc

# Skip rustup check for riscv64 targets
if [[ "${RUST_TARGET}" != *"riscv64"* ]]; then
    check_tool rustup
fi

echo "Tool versions:"
rustc --version
cargo --version

# Handle toolchain and target setup
if [[ "${RUST_TARGET}" == *"riscv64"* ]]; then
    # Special handling for riscv64
    if [[ "$(uname -m | tr -d '[:space:]')" == "riscv64" ]]; then
        DETECTED_TARGET="$(rustc -Vv 2>/dev/null | sed -n "s/^[[:space:]]*host[[:space:]]*:[[:space:]]*//p" | grep -i "riscv" | tr -d "[:space:]")"
        if [[ -n "${DETECTED_TARGET//[[:space:]]/}" ]]; then
            export RUST_TARGET="${DETECTED_TARGET}"
            echo "Detected RISC-V target: ${RUST_TARGET}"
        else
            echo "Failed to detect RISC-V target:"
            rustc -Vv
            exit 1
        fi
    else
        export RUST_TARGET="$(uname -m)-unknown-linux-musl"
        rustup target add "${RUST_TARGET}"
    fi
else
    # Standard toolchain setup
    if [[ "${TOOLCHAIN}" == "nightly" ]]; then
        rustup default nightly
    else
        rustup default stable
    fi
    rustup target add "${RUST_TARGET}"
fi

# Export RUST_TARGET
export RUST_TARGET

# Handle RUSTFLAGS
if [[ "${RBUILD_STATIC:-0}" == "1" ]]; then
    echo "Setting up static linking flags..."
    
    RUST_FLAGS=()
    RUST_FLAGS+=("-C target-feature=+crt-static")
    RUST_FLAGS+=("-C default-linker-libraries=yes")
    
    if ! echo "${RUST_TARGET}" | grep -Eqiv "alpine|gnu"; then
        RUST_FLAGS+=("-C link-self-contained=yes")
    fi
    
    RUST_FLAGS+=("-C prefer-dynamic=no")
    RUST_FLAGS+=("-C embed-bitcode=yes")
    RUST_FLAGS+=("-C lto=yes")
    RUST_FLAGS+=("-C opt-level=z")
    RUST_FLAGS+=("-C debuginfo=none")
    RUST_FLAGS+=("-C strip=symbols")
    RUST_FLAGS+=("-C linker=clang")
    
    # Add mold linker if available
    if command -v mold &>/dev/null; then
        RUST_FLAGS+=("-C link-arg=-fuse-ld=$(which mold)")
    fi
    
    RUST_FLAGS+=("-C link-arg=-Wl,--Bstatic")
    RUST_FLAGS+=("-C link-arg=-Wl,--static")
    RUST_FLAGS+=("-C link-arg=-Wl,-S")
    RUST_FLAGS+=("-C link-arg=-Wl,--build-id=none")
    
    export RUSTFLAGS="${RUST_FLAGS[*]}"
    echo "RUSTFLAGS: ${RUSTFLAGS}"
elif [[ -n "${RUSTFLAGS:-}" ]]; then
    export RUSTFLAGS
    echo "Using provided RUSTFLAGS: ${RUSTFLAGS}"
fi

echo "Setup complete. Running cargo command..."
EOF
}

# Pull container image
pull_image() {
    log_info "Pulling container image: ${CONTAINER_IMAGE}"
    if ! ${USE_SUDO} ${CONTAINER_ENGINE} pull --platform="${CONTAINER_PLATFORM}" "${CONTAINER_IMAGE}"; then
        log_error "Failed to pull container image: ${CONTAINER_IMAGE}"
        exit 1
    fi
}

# Run container
run_container() {
    local setup_script
    setup_script="$(generate_setup_script)"
    
    # Prepare mount arguments
    MOUNT_ARGS+=("-v" "${WORKSPACE_DIR}:${DEFAULT_WORKSPACE}")
    
    if [[ -n "${ARTIFACT_DIR}" ]]; then
        MOUNT_ARGS+=("-v" "${ARTIFACT_DIR}:${ARTIFACT_DIR}")
    fi
    
    # Prepare environment arguments
    ENV_ARGS+=("-e" "RUST_TARGET=${RUST_TARGET}")
    ENV_ARGS+=("-e" "TOOLCHAIN=${TOOLCHAIN}")
    ENV_ARGS+=("-e" "RBUILD_STATIC=${RBUILD_STATIC:-0}")
    
    if [[ -n "${RUSTFLAGS:-}" ]]; then
        ENV_ARGS+=("-e" "RUSTFLAGS=${RUSTFLAGS}")
    fi
    
    # Create and run container
    log_info "Starting container..."
    
    local container_cmd=(
        ${USE_SUDO} ${CONTAINER_ENGINE} run
        --rm
        --platform="${CONTAINER_PLATFORM}"
        --workdir="${DEFAULT_WORKSPACE}"
        "${MOUNT_ARGS[@]}"
        "${ENV_ARGS[@]}"
        "${CONTAINER_IMAGE}"
        bash -c "${setup_script} && cargo ${CARGO_ARGS[*]}"
    )
    
    log_verbose "Container command: ${container_cmd[*]}"
    
    # Execute the container
    "${container_cmd[@]}"
    
    log_success "Build completed successfully!"
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    # Check for help flags
    case "${1:-}" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        -V|--version|version)
            echo "${SCRIPT_NAME} v${VERSION}"
            exit 0
            ;;
    esac
    
    # Parse toolchain if specified
    if [[ "${1:-}" =~ ^\+(.+)$ ]]; then
        TOOLCHAIN="${BASH_REMATCH[1]}"
        log_verbose "Using toolchain: ${TOOLCHAIN}"
        shift
    fi
    
    # Remaining arguments are cargo args
    CARGO_ARGS=("$@")
    
    if [[ ${#CARGO_ARGS[@]} -eq 0 ]]; then
        log_error "No cargo subcommand specified"
        show_help
        exit 1
    fi
    
    log_verbose "Cargo args: ${CARGO_ARGS[*]}"
}

# Main function
main() {
    log_info "Starting ${SCRIPT_NAME} v${VERSION}"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Detect container engine
    detect_container_engine
    
    # Determine target and container image
    determine_target_and_image
    
    # Parse artifact directory
    parse_artifact_dir
    
    # Pull container image
    pull_image
    
    # Run the build
    run_container
}

# Run main function with all arguments
main "$@"