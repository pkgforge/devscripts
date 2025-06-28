#!/usr/bin/env bash
# bash <(curl -qfsSL 'https://github.com/pkgforge/devscripts/raw/refs/heads/main/Linux/rbuilder.sh')
# rbuilder - A minimal alternative to cross-rs/cross
# Usage: rbuilder [+toolchain] <cargo-subcommand> [options...]

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

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    if [[ "${RBUILDER_QUIET:-0}" == "1" ]]; then
        return 0
    fi
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    if [[ "${RBUILDER_QUIET:-0}" == "1" ]]; then
        return 0
    fi
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_verbose() {
    if [[ "${RBUILDER_VERBOSE:-0}" != "1" ]]; then
        return 0
    fi
    echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
}

log_verbose_date() {
    if [[ "${RBUILDER_VERBOSE:-0}" != "1" ]]; then
        return 0
    fi
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" >&2
}

# Cleanup function
cleanup() {
    local exit_code=$?
    bash -c 'pgrep cargo | sudo kill -9 2>/dev/null' 2>/dev/null
    bash -c 'sudo pgrep cargo | xargs sudo kill -9 2>/dev/null' 2>/dev/null
    # Fix permissions on mounted directories
    if [[ -n "${ARTIFACT_DIR:-}" && -d "${ARTIFACT_DIR}" ]]; then
        log_verbose "Fixing permissions on artifact directory: ${ARTIFACT_DIR}"
        sudo chown -R "$(id -u):$(id -g)" "${ARTIFACT_DIR}" 2>/dev/null || true
    fi
    if [[ -n "${WORKSPACE_DIR:-}" && -d "${WORKSPACE_DIR}" ]]; then
        log_verbose "Fixing permissions on workspace: ${WORKSPACE_DIR}"
        sudo chown -R "$(id -u):$(id -g)" "${WORKSPACE_DIR}" 2>/dev/null || true
    fi
    
    exit ${exit_code}
}

# Set up signal handlers
trap cleanup EXIT

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
    RUSTFLAGS               Custom RUSTFLAGS (passed through to container)

SUPPORTED TARGETS:
    aarch64-unknown-linux-musl      (Alpine aarch64)
    aarch64-unknown-linux-gnu       (Debian aarch64)
    loongarch64-unknown-linux-musl  (Alpine loongarch64)
    loongarch64-unknown-linux-gnu   (Debian loongarch64)
    riscv64gc-unknown-linux-musl    (Alpine riscv64)
    riscv64gc-unknown-linux-gnu     (Debian riscv64)
    x86_64-unknown-linux-musl       (Alpine x86_64)
    x86_64-unknown-linux-gnu        (Debian x86_64)
EOF
}

# Check if command exists
command_exists() {
    if [[ -z "${1:-}" ]]; then
        return 1
    fi
    command -v "$1" &>/dev/null
}

# Check if current directory contains a Rust project
check_rust_project() {
    local current_dir="${PWD}"
    
    # Check for Cargo.toml in current directory or parent directories
    while [[ "${current_dir}" != "/" ]]; do
        if [[ -f "${current_dir}/Cargo.toml" ]]; then
            WORKSPACE_DIR="${current_dir}"
            log_verbose "Found Rust project at: ${WORKSPACE_DIR}"
            return 0
        fi
        current_dir="$(dirname "${current_dir}")"
    done
    
    # Also check for other Rust project indicators
    if [[ -f "${PWD}/Cargo.lock" ]] || [[ -d "${PWD}/src" ]] || [[ -f "${PWD}/rust-toolchain" ]] || [[ -f "${PWD}/rust-toolchain.toml" ]]; then
        log_verbose "Found Rust project indicators in current directory"
        return 0
    fi
    
    log_error "No Rust project found in current directory or parent directories"
    log_error "Expected to find Cargo.toml, Cargo.lock, src/ directory, or rust-toolchain file"
    return 1
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
        return 1
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
        return 1
    fi
    
    return 0
}

# Check QEMU/binfmt
check_qemu_binfmt() {
    local cross_qemu=0

    # Check if binfmt_misc is mounted and QEMU handlers are enabled
    if [[ -d "/proc/sys/fs/binfmt_misc" ]]; then
        if grep -qi 'enabled' "/proc/sys/fs/binfmt_misc/qemu-arm" 2>/dev/null || \
           grep -qi 'enabled' "/proc/sys/fs/binfmt_misc/qemu-aarch64" 2>/dev/null; then
            log_info "QEMU binfmt_misc handlers are registered and enabled"
            cross_qemu=1
        fi
    fi

    # Fallback: check for qemu-user-static binaries in PATH
    if [[ "${cross_qemu}" -eq 0 ]]; then
        if command_exists qemu-user-static &>/dev/null || \
           command_exists qemu-aarch64-static &>/dev/null; then
            log_info "QEMU user-static binaries found in PATH"
            cross_qemu=1
        fi
    fi

    if [[ "${cross_qemu}" -eq 0 ]]; then
        log_error "QEMU user emulation not found. Cross-platform builds may fail."
        log_error "Install with:   sudo apt-get install qemu-user-static (Debian/Ubuntu)"
        log_error "                sudo pacman -S qemu-user-static (Arch)"
        log_error "Github Actions: https://github.com/docker/setup-qemu-action"
        echo ""
        return 1
    fi
    return 0
}

# Get the default RUST TARGET
get_default_rust_target() {
    local ARCH OS LIBC
    ARCH="$(uname -m)"
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

    [[ "${ARCH}" == "riscv64" ]] && ARCH="riscv64gc"

    if ldd --version 2>&1 | grep -qi 'musl'; then
        LIBC="musl"
    else
        LIBC="gnu"
    fi

    RUST_TARGET="${ARCH}-unknown-${OS}-${LIBC}"
    log_info "No target specified, defaulting to: ${RUST_TARGET}"
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
        get_default_rust_target &>/dev/null
        [[ -z "${RUST_TARGET}" ]] && RUST_TARGET="x86_64-unknown-linux-musl"
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
            return 1
            ;;
    esac
    
    log_verbose "Target: ${RUST_TARGET}"
    log_verbose "Container: ${CONTAINER_IMAGE}"
    log_verbose "Platform: ${CONTAINER_PLATFORM}"
    return 0
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
        if ! mkdir -p "${ARTIFACT_DIR}"; then
            log_error "Failed to create artifact directory: ${ARTIFACT_DIR}"
            return 1
        fi
        
        # Check if writable
        if [[ ! -w "${ARTIFACT_DIR}" ]]; then
            log_error "Artifact directory is not writable: ${ARTIFACT_DIR}"
            return 1
        fi
        
        log_info "Artifact directory: ${ARTIFACT_DIR}"
    fi
    return 0
}

# Update cargo args with the final target
update_cargo_target_arg() {
    local i
    local target_updated=0
    
    # Find and update existing --target argument
    for ((i=0; i<${#CARGO_ARGS[@]}; i++)); do
        if [[ "${CARGO_ARGS[i]}" == "--target" ]]; then
            if ((i+1 < ${#CARGO_ARGS[@]})); then
                CARGO_ARGS[i+1]="${RUST_TARGET}"
                target_updated=1
                break
            fi
        elif [[ "${CARGO_ARGS[i]}" =~ ^--target=(.+)$ ]]; then
            CARGO_ARGS[i]="--target=${RUST_TARGET}"
            target_updated=1
            break
        fi
    done
    
    # Add --target if not present and not default
    if [[ "${target_updated}" -eq 0 ]]; then
        CARGO_ARGS+=("--target" "${RUST_TARGET}")
        log_info "Added --target=${RUST_TARGET} to cargo args"
    else
        log_info "Updated --target=${RUST_TARGET} in cargo args"
    fi
}

# Generate container setup script
# This function creates a script that will run inside the container
# All variables must be properly escaped to avoid host environment pollution
generate_setup_script() {
    # Use printf with %q to properly escape and quote the values
    local escaped_workspace
    local escaped_rust_target
    local escaped_toolchain
    local escaped_rbuild_static
    local escaped_rustflags
    
    escaped_workspace=$(printf '%q' "${DEFAULT_WORKSPACE}")
    escaped_rust_target=$(printf '%q' "${RUST_TARGET}")
    escaped_toolchain=$(printf '%q' "${TOOLCHAIN}")
    escaped_rbuild_static=$(printf '%q' "${RBUILD_STATIC:-0}")
    escaped_rustflags=$(printf '%q' "${RUSTFLAGS:-}")
    
    cat << EOF
#!/usr/bin/env bash
set -e

# Container setup script - all variables are properly isolated from host
echo "=== Container Setup Script Starting ==="

# Define constants inside the container
readonly CONTAINER_WORKSPACE=${escaped_workspace}
readonly CONTAINER_RUST_TARGET=${escaped_rust_target}
readonly CONTAINER_TOOLCHAIN=${escaped_toolchain}
readonly CONTAINER_RBUILD_STATIC=${escaped_rbuild_static}
CONTAINER_RUSTFLAGS=${escaped_rustflags}

# Sanity checks for required variables
if [[ -z "\${CONTAINER_RUST_TARGET}" ]]; then
    echo "ERROR: RUST_TARGET not set" >&2
    exit 1
fi

if [[ -z "\${CONTAINER_TOOLCHAIN}" ]]; then
    echo "ERROR: TOOLCHAIN not set" >&2
    exit 1
fi

if [[ -z "\${CONTAINER_WORKSPACE}" ]]; then
    echo "ERROR: WORKSPACE not set" >&2
    exit 1
fi

echo "Container configuration:"
echo "  Workspace: \${CONTAINER_WORKSPACE}"
echo "  Rust Target: \${CONTAINER_RUST_TARGET}"
echo "  Toolchain: \${CONTAINER_TOOLCHAIN}"
echo "  Static Build: \${CONTAINER_RBUILD_STATIC}"
echo "  Custom RUSTFLAGS: \${CONTAINER_RUSTFLAGS}"

# Source environment files if they exist
if [[ -f /etc/profile ]]; then
    source /etc/profile 2>/dev/null || true
fi

if [[ -f ~/.profile ]]; then
    source ~/.profile 2>/dev/null || true
fi

if [[ -f ~/.bashrc ]]; then
    source ~/.bashrc 2>/dev/null || true
fi

# Refresh command hash table
hash -r 2>/dev/null || true

# Change to workspace directory
echo "Changing to workspace directory: \${CONTAINER_WORKSPACE}"
if ! cd "\${CONTAINER_WORKSPACE}"; then
    echo "ERROR: Failed to change to workspace directory: \${CONTAINER_WORKSPACE}" >&2
    exit 1
fi

# Verify we're in the right place
if [[ ! -f "Cargo.toml" ]]; then
    echo "ERROR: Cargo.toml not found in workspace directory: \${CONTAINER_WORKSPACE}" >&2
    echo "Current directory: \$(pwd)" >&2
    echo "Directory contents:" >&2
    ls -la . >&2 || true
    exit 1
fi

echo "Successfully positioned in workspace: \$(pwd)"

# Source Rust environment if available
if [[ -f ~/.cargo/env ]]; then
    source ~/.cargo/env 2>/dev/null || true
fi

# Refresh hash table again after sourcing cargo env
hash -r 2>/dev/null || true

# Tool checking function
check_tool() {
    local tool_name="\$1"
    if [[ -z "\${tool_name}" ]]; then
        echo "ERROR: check_tool called without argument" >&2
        return 1
    fi
    
    if ! command -v "\${tool_name}" &>/dev/null; then
        echo "ERROR: \${tool_name} not found in container" >&2
        echo "PATH: \${PATH}" >&2
        return 1
    fi
    
    echo "  \${tool_name}: \$(command -v "\${tool_name}")"
    return 0
}

echo "Checking required tools..."
check_tool clang || exit 1
check_tool cargo || exit 1
check_tool rustc || exit 1

# Skip rustup check for riscv64 targets as they might not have it
if [[ "\${CONTAINER_RUST_TARGET}" != *"riscv64"* ]]; then
    check_tool rustup || exit 1
fi

echo "Tool versions:"
rustc --version 2>/dev/null || { echo "ERROR: rustc version check failed" >&2; exit 1; }
cargo --version 2>/dev/null || { echo "ERROR: cargo version check failed" >&2; exit 1; }

# Handle toolchain and target setup
if [[ "\${CONTAINER_RUST_TARGET}" == *"riscv64"* ]]; then
    echo "Special handling for riscv64 target..."
    
    # Check if we're on a native riscv64 system
    detected_arch="\$(uname -m 2>/dev/null | tr -d '[:space:]')"
    if [[ "\${detected_arch}" == "riscv64" ]]; then
        echo "Running on native riscv64 system"
        detected_target="\$(rustc -Vv 2>/dev/null | sed -n 's/^[[:space:]]*host[[:space:]]*:[[:space:]]*//p' | grep -i "riscv" | tr -d "[:space:]")"
        if [[ -n "\${detected_target}" ]]; then
            export RUST_TARGET="\${detected_target}"
            echo "Detected RISC-V target: \${RUST_TARGET}"
        else
            echo "Failed to detect RISC-V target, using configured target: \${CONTAINER_RUST_TARGET}"
            export RUST_TARGET="\${CONTAINER_RUST_TARGET}"
        fi
    else
        echo "Cross-compiling to riscv64 from \${detected_arch}"
        export RUST_TARGET="\${CONTAINER_RUST_TARGET}"
        if command -v rustup &>/dev/null; then
            echo "Adding target: \${RUST_TARGET}"
            rustup target add "\${RUST_TARGET}" || {
                echo "WARNING: Failed to add target \${RUST_TARGET}, continuing anyway..." >&2
            }
        fi
    fi

    # Remove any occurrences of '-C link-self-contained=yes'
    if [[ -n "\${CONTAINER_RUSTFLAGS}" ]]; then
      CONTAINER_RUSTFLAGS_TMP="\$(echo "\${CONTAINER_RUSTFLAGS}" | sed -E 's/-C[[:space:]]+link-self-contained[[:space:]]*=[[:space:]]*yes//g' | xargs)"
      export CONTAINER_RUSTFLAGS="\${CONTAINER_RUSTFLAGS_TMP}"
    fi
else
    echo "Standard toolchain setup for target: \${CONTAINER_RUST_TARGET}"
    export RUST_TARGET="\${CONTAINER_RUST_TARGET}"
    
    # Set up toolchain
    if [[ "\${CONTAINER_TOOLCHAIN}" == "nightly" ]]; then
        echo "Setting up nightly toolchain..."
        rustup default nightly || { echo "ERROR: Failed to set nightly toolchain" >&2; exit 1; }
    else
        echo "Setting up stable toolchain..."
        rustup default stable || { echo "ERROR: Failed to set stable toolchain" >&2; exit 1; }
    fi
    
    echo "Adding target: \${RUST_TARGET}"
    rustup target add "\${RUST_TARGET}" || { echo "ERROR: Failed to add target \${RUST_TARGET}" >&2; exit 1; }
fi

# Re:Set RUST_TARGET
readonly CONTAINER_RUSTFLAGS=${escaped_rustflags}
echo "Final Rust target: \${RUST_TARGET}"
if [[ "\${RUST_TARGET}" == *"riscv64"* ]]; then
    echo "FINAL_RUST_TARGET=\${RUST_TARGET}" > "/tmp/rust_target_export"
fi

# Handle RUSTFLAGS setup
if [[ "\${CONTAINER_RBUILD_STATIC}" == "1" ]]; then
    echo "Setting up static linking flags..."
    
    # Build RUSTFLAGS array
    declare -a rust_flags=()
    rust_flags+=("-C" "target-feature=+crt-static")
    rust_flags+=("-C" "default-linker-libraries=yes")
    
    # Only add link-self-contained for non-GNU/custom targets
    if [[ "\${RUST_TARGET}" != *"gnu"* && "\${RUST_TARGET}" != *"alpine"* ]]; then
        rust_flags+=("-C" "link-self-contained=yes")
    fi
    
    rust_flags+=("-C" "prefer-dynamic=no")
    rust_flags+=("-C" "embed-bitcode=yes")
    rust_flags+=("-C" "lto=yes")
    rust_flags+=("-C" "opt-level=z")
    rust_flags+=("-C" "debuginfo=none")
    rust_flags+=("-C" "strip=symbols")
    rust_flags+=("-C" "linker=clang")
    
    # Add mold linker if available
    if command -v mold &>/dev/null; then
        mold_path="\$(command -v mold)"
        rust_flags+=("-C" "link-arg=-fuse-ld=\${mold_path}")
        echo "Using mold linker: \${mold_path}"
    fi
    
    rust_flags+=("-C" "link-arg=-Wl,--Bstatic")
    rust_flags+=("-C" "link-arg=-Wl,--static")
    rust_flags+=("-C" "link-arg=-Wl,-S")
    rust_flags+=("-C" "link-arg=-Wl,--build-id=none")
    
    # Convert array to space-separated string
    export RUSTFLAGS="\${rust_flags[*]}"
    echo "Static build RUSTFLAGS: \${RUSTFLAGS}"    
elif [[ -n "\${CONTAINER_RUSTFLAGS}" ]]; then
    if echo "\${RUST_TARGET}" | grep -Eqi "alpine|gnu"; then
        RUSTFLAGS_TMP="\$(echo "\${CONTAINER_RUSTFLAGS}" | sed -E 's/-C[[:space:]]+link-self-contained[[:space:]]*=[[:space:]]*yes//g' | xargs)"
        export RUSTFLAGS="\${RUSTFLAGS_TMP}"
        echo "Using RUSTFLAGS (Provided + Sanitized): \${RUSTFLAGS}"
    else
        export RUSTFLAGS="\${CONTAINER_RUSTFLAGS}"
        echo "Using RUSTFLAGS (Provided): \${RUSTFLAGS}"
    fi
else
    echo "No custom RUSTFLAGS specified"
fi
export CARGO_BUILD_JOBS="\$(nproc)"
export CARGO_INCREMENTAL="1"
export CARGO_NET_RETRY="10"
export CARGO_NET_TIMEOUT="300"
export RUST_BACKTRACE="0"
export CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"
echo "=== Container Setup Complete ==="
echo "Running cargo command..."
echo ""
EOF
}

# Pull container image
pull_image() {
    if [[ -z "${CONTAINER_IMAGE}" ]]; then
        log_error "Container image not set"
        return 1
    fi
    
    log_info "Pulling container image: ${CONTAINER_IMAGE}"
    
    local pull_cmd=()
    if [[ -n "${USE_SUDO}" ]]; then
        pull_cmd+=("${USE_SUDO}")
    fi
    pull_cmd+=("${CONTAINER_ENGINE}" "pull" "--platform=${CONTAINER_PLATFORM}" "${CONTAINER_IMAGE}")
    
    if ! "${pull_cmd[@]}"; then
        log_error "Failed to pull container image: ${CONTAINER_IMAGE}"
        return 1
    fi
    return 0
}

# Get total memory in bytes with multiple fallbacks
get_total_memory_bytes() {
    local memory_bytes=0
    
    # Method 1: Try /proc/meminfo (most reliable on Linux)
    if [[ -r "/proc/meminfo" ]]; then
        # Extract MemTotal, handle various whitespace patterns
        memory_bytes="$(awk '/^[[:space:]]*MemTotal[[:space:]]*:/ {
            # Remove all non-digit characters except for the number
            gsub(/[^0-9]/, "", $2); 
            print $2 * 1024
        }' /proc/meminfo 2>/dev/null)"
    fi
    
    # Method 2: Fallback to free command if /proc/meminfo failed
    if [[ -z "${memory_bytes}" || "${memory_bytes}" -eq 0 ]]; then
        # Use free with bytes, handle various output formats
        memory_bytes="$(free -b 2>/dev/null | awk '
            /^[[:space:]]*Mem[[:space:]]*:/ { 
                gsub(/[^0-9]/, "", $2); 
                if ($2 > 0) print $2 
            }
            /^[[:space:]]*Memory[[:space:]]*:/ { 
                gsub(/[^0-9]/, "", $2); 
                if ($2 > 0) print $2 
            }
        ')"
    fi
    
    # Method 3: Try alternative free output parsing
    if [[ -z "${memory_bytes}" || "${memory_bytes}" -eq 0 ]]; then
        memory_bytes="$(free 2>/dev/null | awk '
            NR==2 { 
                gsub(/[^0-9]/, "", $2); 
                if ($2 > 0) print $2 * 1024 
            }
        ')"
    fi
    
    # Method 4: macOS fallback using sysctl
    if [[ -z "${memory_bytes}" || "${memory_bytes}" -eq 0 ]] && command -v sysctl >/dev/null 2>&1; then
        memory_bytes="$(sysctl -n 'hw.memsize' 2>/dev/null)"
    fi
    
    # Validation: ensure we got a reasonable memory value (at least 100MB)
    if [[ -n "${memory_bytes}" && "${memory_bytes}" -gt 104857600 ]]; then
        echo "${memory_bytes}"
    else
        # Ultimate fallback: assume 2GB if all methods fail
        echo "2147483648"
    fi
}

# Function to calculate 80% of memory with proper formatting
calculate_memory_limit() {
    local total_memory
    total_memory="$(get_total_memory_bytes)"
    
    # Calculate 80% and format appropriately
    local memory_limit
    memory_limit="$(printf "%.0f" "$(echo "$total_memory * 0.8" | bc 2>/dev/null || echo "$total_memory * 8 / 10" | awk '{print int($1)}')")"
    
    echo "${memory_limit}"
}

# Detect available resources
detect_resources() {
    local available_cpus available_memory
    
    available_cpus="$(nproc 2>/dev/null || echo '1')"
    available_memory="$(calculate_memory_limit)"
    
    log_verbose "Available CPUs: ${available_cpus}"
    log_verbose "Available memory: $((available_memory / 1024 / 1024))MB"
    
    return 0
}

# Run container
run_container() {
    local container_name
    container_name="rbuilder-$(date +%s)-$$"
    local setup_script
    setup_script="$(generate_setup_script)"
    
    if [[ -z "${setup_script}" ]]; then
        log_error "Failed to generate setup script"
        return 1
    fi
    
    # Prepare mount arguments
    MOUNT_ARGS+=("-v" "${WORKSPACE_DIR}:${DEFAULT_WORKSPACE}")
    
    if [[ -n "${ARTIFACT_DIR}" ]]; then
        MOUNT_ARGS+=("-v" "${ARTIFACT_DIR}:${ARTIFACT_DIR}")
    fi
    
    # Prepare environment arguments - only pass what's absolutely necessary
    # The setup script will handle all the configuration internally
    
    # Create and run container
    log_info "Starting container..."
    
    local container_cmd=()
    if [[ -n "${USE_SUDO}" ]]; then
        container_cmd+=("${USE_SUDO}")
    fi
    
    container_cmd+=(
        "${CONTAINER_ENGINE}" "run"
        "--name=${container_name}"
        "--rm"
        "--platform=${CONTAINER_PLATFORM}"
        "--workdir=${DEFAULT_WORKSPACE}"
        "--cpus=$(nproc)"
        "--dns=1.1.1.1"
        "--dns=8.8.8.8"
        "--ipc=host"
        "--log-driver=none"
        "--memory-swappiness=1"
        "--oom-kill-disable=true"
        "--security-opt=seccomp=unconfined"
        "--shm-size=2g"
        "--ulimit=memlock=-1:-1"
        "--ulimit=nofile=1048576:1048576"
        "--ulimit=nproc=32768:32768"
    )
    
    # Add mount arguments
    container_cmd+=("${MOUNT_ARGS[@]}")
    
    # Add image and command
    container_cmd+=("${CONTAINER_IMAGE}")
    
    # Build the final command that combines setup and cargo execution
    local final_cmd="set -e; ${setup_script}"
    final_cmd+=" && exec cargo"
    
    # Add each cargo argument properly quoted
    local arg
    for arg in "${CARGO_ARGS[@]}"; do
        final_cmd+=" $(printf '%q' "${arg}")"
    done
    
    container_cmd+=("bash" "-c" "${final_cmd}")
    
    log_verbose "Container command: ${container_cmd[*]}"
    
    # Create a temporary container to extract the final target for riscv64
    if [[ "${RUST_TARGET}" == *"riscv64"* ]]; then
        log_verbose "Detecting final RISC-V target..."
        
        local temp_cmd=()
        if [[ -n "${USE_SUDO}" ]]; then
            temp_cmd+=("${USE_SUDO}")
        fi
        
        temp_cmd+=(
            "${CONTAINER_ENGINE}" "run" "--rm"
            "--platform=${CONTAINER_PLATFORM}"
            "--workdir=${DEFAULT_WORKSPACE}"
            "${MOUNT_ARGS[@]}"
            "${CONTAINER_IMAGE}"
            "bash" "-c" "set -e; ${setup_script} && cat '/tmp/rust_target_export' 2>/dev/null || true"
        )
        
        local temp_output
        if temp_output=$("${temp_cmd[@]}" 2>/dev/null); then
            if [[ "${temp_output}" =~ FINAL_RUST_TARGET=(.+) ]]; then
                local final_target="${BASH_REMATCH[1]}"
                if [[ "${final_target}" != "${RUST_TARGET}" ]]; then
                    RUST_TARGET="${final_target}"
                    log_info "Updated RUST_TARGET to: ${RUST_TARGET}"
                    update_cargo_target_arg
                    
                    # Rebuild the final command with updated target
                    final_cmd="set -e; ${setup_script}"
                    final_cmd+=" && exec cargo"
                    for arg in "${CARGO_ARGS[@]}"; do
                        final_cmd+=" $(printf '%q' "${arg}")"
                    done
                    container_cmd[${#container_cmd[@]}-1]="${final_cmd}"
                fi
            fi
        fi
    fi

    log_info "Cargo Args (Final): ${CARGO_ARGS[*]}"

    # Execute the container
    if ! "${container_cmd[@]}"; then
        log_error "Container execution failed"
        return 1
    fi
    
    log_success "Build completed successfully!"
    return 0
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
        return 1
    fi
    
    log_info "Cargo args: ${CARGO_ARGS[*]}"
    return 0
}

# Main function
main() {
    log_info "Starting ${SCRIPT_NAME} v${VERSION}"
    
    # Parse arguments
    if ! parse_args "$@"; then
        exit 1
    fi
    
    # Check QEMU Binfmt
    check_qemu_binfmt
    #if ! check_qemu_binfmt; then
    #    exit 1
    #fi

    # Check if we're in a Rust project
    if ! check_rust_project; then
        exit 1
    fi
    
    # Detect container engine
    if ! detect_container_engine; then
        exit 1
    else
      detect_resources
    fi

    # Determine target and container image
    if ! determine_target_and_image; then
        exit 1
    fi
    
    # Parse artifact directory
    if ! parse_artifact_dir; then
        exit 1
    fi

    #Add Update Target
    if ! update_cargo_target_arg; then
        exit 1
    fi
    
    # Pull container image
    if ! pull_image; then
        exit 1
    fi
    
    # Run the build
    if ! run_container; then
        exit 1
    fi
    
    return 0
}

# Run main function with all arguments
if ! main "$@"; then
    exit 1
fi