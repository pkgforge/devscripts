#!/usr/bin/env bash
# GitHub Actions Runner Debloater
# Removes bloat from GitHub Actions runners and optionally creates optimized build mount
# Can free up to 40GB+ of space and create unified build volumes using LVM
#
# Usage:
#   bash <(curl -qfsSL 'https://github.com/pkgforge/devscripts/raw/refs/heads/main/Github/Runners/debloat_ubuntu.sh')
#   ./debloat.sh                    # Auto-detect runner environment
#   ./debloat.sh --force            # Force run regardless of environment
#   ./debloat.sh --mount /build     # Create optimized build mount at /build
#   ./debloat.sh --unmount          # Remove LVM mount and restore original setup
#   ./debloat.sh --help             # Show help

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script configuration
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly PROVISIONER_FILE="/opt/runner/provisioner"
readonly VG_NAME="buildvg"

# Default values for mount options
readonly DEFAULT_ROOT_RESERVE_MB=1024
readonly DEFAULT_TEMP_RESERVE_MB=100
readonly DEFAULT_SWAP_SIZE_MB=4096
readonly DEFAULT_PV_LOOP_PATH="/pv.img"
readonly DEFAULT_TMP_PV_LOOP_PATH="/mnt/tmp-pv.img"
readonly DEFAULT_MOUNT_OWNERSHIP="runner:runner"

# Function to print colored output
log() {
    local level="$1"
    shift
    case "$level" in
        "info")    echo -e "${BLUE}[INFO]${NC} $*" ;;
        "warn")    echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "error")   echo -e "${RED}[ERROR]${NC} $*" ;;
        "success") echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
        "mount")   echo -e "${CYAN}[MOUNT]${NC} $*" ;;
    esac
}

# Function to show help
show_help() {
    cat << EOF
GitHub Actions Runner Debloater

DESCRIPTION:
    Removes bloat from GitHub Actions runners to free up 40GB+ of disk space.
    Optionally creates an optimized LVM build mount combining root and temp storage.
    By default, only runs when executed as 'runner' user and provisioner file exists.

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    --force                    Force execution regardless of environment detection
    --mount PATH               Create optimized build mount at PATH using LVM
    --unmount                  Remove LVM mount and restore original setup
    --root-reserve-mb MB       Space to reserve on root filesystem (default: $DEFAULT_ROOT_RESERVE_MB)
    --temp-reserve-mb MB       Space to reserve on temp filesystem (default: $DEFAULT_TEMP_RESERVE_MB)
    --swap-size-mb MB          Swap space to create in MB (default: $DEFAULT_SWAP_SIZE_MB)
    --mount-ownership USER:GROUP  Ownership for mount point (default: $DEFAULT_MOUNT_OWNERSHIP)
    --overprovision-lvm        Use sparse LVM files (use with caution)
    --remove-docker-images     Remove cached Docker images (~3GB)
    --remove-codeql           Remove CodeQL bundles (~5.4GB)
    --parallel-jobs N         Number of parallel cleanup jobs (default: auto-detect)
    --help                    Show this help message

EXAMPLES:
    $SCRIPT_NAME                           # Standard cleanup
    $SCRIPT_NAME --force                   # Force run on any system
    $SCRIPT_NAME --mount /build            # Cleanup + create optimized build mount
    $SCRIPT_NAME --unmount                 # Remove LVM mount and restore system
    $SCRIPT_NAME --mount /build --remove-docker-images --remove-codeql
    
WHAT GETS REMOVED:
    • Android NDK (~12GB)         • Haskell (~5GB)
    • HostedToolCache (~12GB)     • Snap packages (~5GB)
    • DotNET (~2GB)              • GCP SDK (~2GB)
    • Swift (~1.7GB)             • JVM (~1.5GB)
    • Mono (~1.5GB)              • PowerShell (~1GB)
    • Azure CLI (~800MB)         • Miniconda (~700MB)
    • Microsoft tools (~700MB)   • AWS CLI (~500MB)
    • Julia (~500MB)             • Heroku (~500MB)
    • AZ PowerShell (~500MB)
    
MOUNT FEATURE:
    When --mount is used, creates an optimized build volume using LVM that:
    • Combines root filesystem and /mnt temp storage
    • Recreates swap space efficiently
    • Provides maximum available space for builds
    • Uses ext4 filesystem optimized for build workloads

UNMOUNT FEATURE:
    When --unmount is used, safely removes LVM setup:
    • Unmounts build volumes and restores original swap
    • Removes volume groups and physical volumes
    • Cleans up loop devices and files
    • Restores system to pre-mount state
EOF
}

# Function to check if running as runner user
is_runner_user() {
    [[ "$USER" == "runner" ]] || [[ "$(whoami)" == "runner" ]]
}

# Function to check if provisioner file exists
provisioner_exists() {
    [[ -s "$PROVISIONER_FILE" ]]
}

# Function to check if we should run
should_run() {
    local force="$1"
    
    if [[ "$force" == "true" ]]; then
        log "warn" "Force mode enabled - running regardless of environment"
        return 0
    fi
    
    if ! is_runner_user; then
        log "error" "Not running as 'runner' user (current: $(whoami))"
        log "info" "Use --force to override this check"
        return 1
    fi
    
    if ! provisioner_exists; then
        log "error" "GitHub Actions provisioner file not found: $PROVISIONER_FILE"
        log "info" "Use --force to override this check"
        return 1
    fi
    
    return 0
}

# Function to get disk usage stats
get_disk_stats() {
    local path="${1:-/}"
    local root_disk
    root_disk="$(df -h "$path" | awk 'NR==2 {print $1}')"
    
    df -h "$root_disk" | awk 'NR==2 {print $1":"$2":"$3":"$5}'
}

# Function to parse disk stats
parse_disk_stats() {
    local stats="$1"
    local field="$2"
    
    case "$field" in
        "disk") echo "$stats" | cut -d: -f1 ;;
        "total") echo "$stats" | cut -d: -f2 ;;
        "used") echo "$stats" | cut -d: -f3 ;;
        "percent") echo "$stats" | cut -d: -f4 ;;
    esac
}

# Function to show disk space report
show_disk_report() {
    local title="$1"
    
    echo
    log "info" "$title"
    echo "Memory and swap:"
    sudo free -h
    echo
    sudo swapon --show 2>/dev/null || echo "No swap active"
    echo
    echo "Available storage:"
    sudo df -h
    echo
}

# Function to remove directories safely with progress
safe_remove() {
    local paths=("$@")
    local removed_count=0
    
    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            local size=""
            if command -v du &>/dev/null; then
                size="$(du -sh "$path" 2>/dev/null | cut -f1 || echo "unknown")"
            fi
            
            if sudo rm -rf "$path" 2>/dev/null; then
                ((removed_count++))
                [[ -n "$size" ]] && log "info" "  Removed $path ($size)"
            fi
        fi
    done
    
    return $removed_count
}

# Function to handle snap removal
remove_snaps() {
    log "info" "Starting snap package removal..."
    
    # Check if snap is installed
    if ! command -v snap &>/dev/null; then
        log "info" "Snap not installed, skipping snap removal"
        return 0
    fi
    
    # Get list of installed snaps
    local snaps
    snaps=$(snap list 2>/dev/null | awk 'NR>1 {print $1}' | grep -v -E '^(core|bare|snapd)' || true)
    
    if [[ -n "$snaps" ]]; then
        log "info" "Removing user snap packages..."
        echo "$snaps" | xargs -n1 -P4 -I{} sudo snap remove --purge {} 2>/dev/null || true
    fi
    
    # Remove system snaps in correct dependency order
    local system_snaps=("bare" "core20" "core22" "core18" "core" "snapd")
    for snap in "${system_snaps[@]}"; do
        if snap list "$snap" &>/dev/null; then
            log "info" "Removing system snap: $snap"
            sudo snap remove --purge "$snap" &>/dev/null || true
        fi
    done
    
    # Disable and remove snapd
    log "info" "Disabling snapd services..."
    sudo systemctl disable --now snapd.service snapd.socket snapd.seeded.service &>/dev/null || true
    sudo systemctl mask snapd &>/dev/null || true
    
    # Remove snapd package
    sudo apt purge -y snapd &>/dev/null || true
    
    # Clean up snap directories
    safe_remove /snap /var/snap /var/cache/snapd /var/lib/snapd
    safe_remove "$HOME/snap" "/root/snap"
    
    # Prevent snapd reinstallation
    sudo tee /etc/apt/preferences.d/no-snap.pref &>/dev/null << 'EOF' || true
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF
    
    # Unmount any remaining snap mounts
    df -h 2>/dev/null | awk '/\/snap\// {print $6}' | while IFS= read -r mount; do
        sudo umount "$mount" &>/dev/null || true
    done
    
    log "success" "Snap removal completed"
}

# Function to remove Docker images
remove_docker_images() {
    log "info" "Starting comprehensive Docker/Podman cleanup..."
    
    for cmd in docker podman; do
        if ! command -v "$cmd" &>/dev/null; then
            continue
        fi
        
        log "info" "Cleaning up $cmd..."
        
        case "$cmd" in
            docker)
                # Stop and remove all containers
                local containers
                containers=$($cmd ps -aq 2>/dev/null || true)
                if [[ -n "$containers" ]]; then
                    sudo $cmd stop $containers &>/dev/null || true
                    sudo $cmd rm -f $containers &>/dev/null || true
                fi
                
                # Remove all images
                local images
                images=$($cmd images -aq 2>/dev/null || true)
                if [[ -n "$images" ]]; then
                    sudo $cmd rmi -f $images &>/dev/null || true
                fi
                
                # Remove all volumes
                local volumes
                volumes=$($cmd volume ls -q 2>/dev/null || true)
                if [[ -n "$volumes" ]]; then
                    sudo $cmd volume rm $volumes &>/dev/null || true
                fi
                
                # Remove all networks (except default ones)
                local networks
                networks=$($cmd network ls -q --filter type=custom 2>/dev/null || true)
                if [[ -n "$networks" ]]; then
                    sudo $cmd network rm $networks &>/dev/null || true
                fi
                
                # System-wide cleanup
                sudo $cmd system prune -af --volumes &>/dev/null || true
                sudo $cmd builder prune -af &>/dev/null || true
                
                # Clean up Docker root directory if possible
                sudo systemctl stop docker &>/dev/null || true
                safe_remove /var/lib/docker/tmp /var/lib/docker/overlay2
                sudo systemctl start docker &>/dev/null || true
                ;;
                
            podman)
                # Stop and remove all containers
                sudo $cmd stop --all &>/dev/null || true
                sudo $cmd rm -af &>/dev/null || true
                
                # Remove all images
                sudo $cmd rmi -af &>/dev/null || true
                
                # Remove all volumes
                sudo $cmd volume rm --all &>/dev/null || true
                
                # Remove all pods
                sudo $cmd pod rm -af &>/dev/null || true
                
                # System reset (nuclear option for podman)
                sudo $cmd system reset -f &>/dev/null || true
                ;;
        esac
        
        log "success" "$cmd cleanup completed"
    done
    
    # Clean up additional container-related directories
    safe_remove /var/lib/containerd /var/lib/containers
    
    log "success" "Container runtime cleanup completed"
}

# Function to remove CodeQL
remove_codeql() {
    log "info" "Removing CodeQL bundles..."
    safe_remove /opt/hostedtoolcache/CodeQL
}

# Function to get optimal parallel job count
get_parallel_jobs() {
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || echo "4")
    echo $((cpu_count > 8 ? 8 : cpu_count))
}

# Function to perform cleanup operations
perform_cleanup() {
    local remove_docker="$1"
    local remove_codeql="$2"
    local parallel_jobs="$3"
    
    log "info" "Starting parallel cleanup operations (using $parallel_jobs jobs)..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package cache
    log "info" "Updating package cache..."
    sudo apt update -qq &>/dev/null
    
    # Define cleanup jobs with descriptions
    declare -A cleanup_jobs=(
        ["android"]="Android NDK (~12GB):/usr/local/lib/android"
        ["aws"]="AWS CLI (~500MB):/usr/local/*aws*cli*"
        ["azure"]="Azure CLI (~800MB):/opt/az"
        ["azpowershell"]="AZ PowerShell (~500MB):/usr/share/az_*"
        ["dotnet"]="DotNET (~2GB):/usr/lib/dotnet:/usr/share/dotnet"
        ["gcp"]="GCP SDK (~2GB):/usr/lib/google-cloud-sdk"
        ["haskell"]="Haskell (~5GB):/usr/local/.ghcup:/opt/ghc"
        ["heroku"]="Heroku (~500MB):/usr/local/lib/heroku"
        ["toolcache"]="HostedToolCache (~12GB):/opt/hostedtoolcache"
        ["jvm"]="JVM (~1.5GB):/usr/lib/jvm"
        ["julia"]="Julia (~500MB):/usr/local/*julia*"
        ["miniconda"]="Miniconda (~700MB):/usr/share/miniconda"
        ["microsoft"]="Microsoft (~700MB):/opt/microsoft"
        ["mono"]="Mono (.NET) (~1.5GB):/usr/lib/mono"
        ["powershell"]="PowerShell (~1GB):/usr/local/share/powershell"
        ["swift"]="Swift (~1.7GB):/usr/share/swift"
    )
    
    # Start cleanup jobs in parallel
    local pids=()
    local job_count=0
    
    for job in "${!cleanup_jobs[@]}"; do
        # Limit parallel jobs
        if [[ $job_count -ge $parallel_jobs ]]; then
            wait -n  # Wait for any job to complete
            ((job_count--))
        fi
        
        {
            local info="${cleanup_jobs[$job]}"
            local desc="${info%%:*}"
            local path_string="${info#*:}"
            
            log "info" "Removing $desc"
            IFS=':' read -ra path_array <<< "$path_string"
            safe_remove "${path_array[@]}"
        } &
        pids+=($!)
        ((job_count++))
    done
    
    # Handle additional removals
    if [[ "$remove_docker" == "true" ]]; then
        remove_docker_images &
        pids+=($!)
    fi
    
    if [[ "$remove_codeql" == "true" ]]; then
        remove_codeql &
        pids+=($!)
    fi
    
    # Handle snap removal separately (it's complex)
    remove_snaps &
    pids+=($!)
    
    # Wait for all cleanup jobs to complete
    log "info" "Waiting for cleanup operations to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Final system cleanup
    log "info" "Running final system cleanup..."
    sudo apt autoremove -y -qq &>/dev/null || true
    sudo apt autoclean -qq &>/dev/null || true
    sudo apt clean &>/dev/null || true
    
    unset DEBIAN_FRONTEND
}

# Function to unmount and cleanup LVM setup
unmount_build_mount() {
    local pv_loop_path="$1"
    local tmp_pv_loop_path="$2"
    
    log "mount" "Starting LVM unmount and cleanup process..."
    
    # Find and unmount any build volumes
    local build_mounts
    build_mounts=$(mount | grep "/dev/mapper/${VG_NAME}-buildlv" | awk '{print $3}' || true)
    
    if [[ -n "$build_mounts" ]]; then
        log "mount" "Unmounting build volumes..."
        echo "$build_mounts" | while IFS= read -r mount_point; do
            log "mount" "Unmounting: $mount_point"
            sudo umount "$mount_point" 2>/dev/null || true
        done
    fi
    
    # Deactivate swap if it's from our VG
    if sudo swapon --show | grep -q "${VG_NAME}-swap"; then
        log "mount" "Deactivating LVM swap..."
        sudo swapoff "/dev/mapper/${VG_NAME}-swap" 2>/dev/null || true
    fi
    
    # Remove logical volumes
    if sudo lvs 2>/dev/null | grep -q "$VG_NAME"; then
        log "mount" "Removing logical volumes..."
        sudo lvremove -f "/dev/mapper/${VG_NAME}-buildlv" 2>/dev/null || true
        sudo lvremove -f "/dev/mapper/${VG_NAME}-swap" 2>/dev/null || true
    fi
    
    # Remove volume group
    if sudo vgs 2>/dev/null | grep -q "$VG_NAME"; then
        log "mount" "Removing volume group: $VG_NAME"
        sudo vgremove -f "$VG_NAME" 2>/dev/null || true
    fi
    
    # Find and remove physical volumes / loop devices
    local loop_devices
    loop_devices=$(sudo losetup -l | grep -E "(${pv_loop_path}|${tmp_pv_loop_path})" | awk '{print $1}' || true)
    
    if [[ -n "$loop_devices" ]]; then
        log "mount" "Removing loop devices..."
        echo "$loop_devices" | while IFS= read -r loop_dev; do
            log "mount" "Removing loop device: $loop_dev"
            sudo pvremove -f "$loop_dev" 2>/dev/null || true
            sudo losetup -d "$loop_dev" 2>/dev/null || true
        done
    fi
    
    # Remove loop files
    log "mount" "Removing loop files..."
    safe_remove "$pv_loop_path" "$tmp_pv_loop_path"
    
    # Restore original swap if possible
    log "mount" "Attempting to restore original swap..."
    if [[ -f /mnt/swapfile ]]; then
        sudo swapon /mnt/swapfile 2>/dev/null || true
    elif sudo fallocate -l 2G /mnt/swapfile 2>/dev/null; then
        sudo chmod 600 /mnt/swapfile
        sudo mkswap /mnt/swapfile &>/dev/null
        sudo swapon /mnt/swapfile &>/dev/null || true
        log "mount" "Created new 2GB swap file at /mnt/swapfile"
    fi
    
    log "success" "LVM unmount and cleanup completed successfully"
}

# Function to create optimized build mount
create_build_mount() {
    local mount_path="$1"
    local root_reserve_mb="$2"
    local temp_reserve_mb="$3"
    local swap_size_mb="$4"
    local mount_ownership="$5"
    local overprovision="$6"
    local pv_loop_path="$7"
    local tmp_pv_loop_path="$8"
    
    log "mount" "Creating optimized build mount at $mount_path"
    log "mount" "Configuration:"
    log "mount" "  Root reserve: ${root_reserve_mb} MB"
    log "mount" "  Temp reserve: ${temp_reserve_mb} MB"
    log "mount" "  Swap size: ${swap_size_mb} MB"
    log "mount" "  Overprovision: ${overprovision}"
    log "mount" "  Ownership: ${mount_ownership}"
    
    # Store original workspace owner if it exists
    local workspace_owner=""
    if [[ -n "${GITHUB_WORKSPACE:-}" ]] && [[ -d "$GITHUB_WORKSPACE" ]]; then
        workspace_owner="$(stat -c '%U:%G' "$GITHUB_WORKSPACE" 2>/dev/null || echo "runner:runner")"
    fi
    
    # Ensure mount path exists
    sudo mkdir -p "$mount_path"
    
    # Check if mount path is not empty and warn
    if [[ -n "$(find "$mount_path" -maxdepth 1 -mindepth 1 -print -quit 2>/dev/null)" ]]; then
        log "warn" "Mount path $mount_path is not empty, data loss might occur"
        log "warn" "Contents:"
        find "$mount_path" -maxdepth 1 -mindepth 1 -exec ls -ld {} \; 2>/dev/null | head -5 || true
    fi
    
    # Unmount existing swap
    log "mount" "Unmounting existing swap..."
    sudo swapoff -a 2>/dev/null || true
    sudo rm -f /mnt/swapfile 2>/dev/null || true
    
    # Create LVM setup
    log "mount" "Creating LVM physical volumes..."
    
    # Create loop PV on root filesystem
    local root_reserve_kb=$((root_reserve_mb * 1024))
    local root_free_kb
    root_free_kb=$(df --block-size=1024 --output=avail / | tail -1)
    local root_lvm_size_kb=$((root_free_kb - root_reserve_kb))
    local root_lvm_size_bytes=$((root_lvm_size_kb * 1024))
    
    if [[ $root_lvm_size_kb -le 0 ]]; then
        log "error" "Insufficient space on root filesystem"
        return 1
    fi
    
    log "mount" "Creating root PV: ${root_lvm_size_kb} KB"
    sudo touch "$pv_loop_path"
    sudo fallocate -z -l "$root_lvm_size_bytes" "$pv_loop_path"
    local root_loop_dev
    root_loop_dev=$(sudo losetup --find --show "$pv_loop_path")
    sudo pvcreate -f "$root_loop_dev"
    
    # Create PV on temp filesystem
    local temp_reserve_kb=$((temp_reserve_mb * 1024))
    local temp_free_kb
    temp_free_kb=$(df --block-size=1024 --output=avail /mnt | tail -1)
    local temp_lvm_size_kb=$((temp_free_kb - temp_reserve_kb))
    local temp_lvm_size_bytes=$((temp_lvm_size_kb * 1024))
    
    if [[ $temp_lvm_size_kb -le 0 ]]; then
        log "error" "Insufficient space on temp filesystem"
        sudo losetup -d "$root_loop_dev" 2>/dev/null || true
        return 1
    fi
    
    log "mount" "Creating temp PV: ${temp_lvm_size_kb} KB"
    sudo touch "$tmp_pv_loop_path"
    sudo fallocate -z -l "$temp_lvm_size_bytes" "$tmp_pv_loop_path"
    local temp_loop_dev
    temp_loop_dev=$(sudo losetup --find --show "$tmp_pv_loop_path")
    sudo pvcreate -f "$temp_loop_dev"
    
    # Create volume group
    log "mount" "Creating volume group: $VG_NAME"
    sudo vgcreate "$VG_NAME" "$temp_loop_dev" "$root_loop_dev"
    
    # Create and activate swap
    log "mount" "Creating swap: ${swap_size_mb} MB"
    sudo lvcreate -L "${swap_size_mb}M" -n swap "$VG_NAME"
    sudo mkswap "/dev/mapper/${VG_NAME}-swap"
    sudo swapon "/dev/mapper/${VG_NAME}-swap"
    
    # Create build volume
    log "mount" "Creating build volume with remaining space"
    sudo lvcreate -l 100%FREE -n buildlv "$VG_NAME"
    
    # Format filesystem
    log "mount" "Formatting build volume..."
    if [[ "$overprovision" == "true" ]]; then
        sudo mkfs.ext4 -m0 "/dev/mapper/${VG_NAME}-buildlv"
    else
        sudo mkfs.ext4 -Enodiscard -m0 "/dev/mapper/${VG_NAME}-buildlv"
    fi
    
    # Mount build volume
    log "mount" "Mounting build volume at $mount_path"
    sudo mount "/dev/mapper/${VG_NAME}-buildlv" "$mount_path"
    sudo chown -R "$mount_ownership" "$mount_path"
    
    # Recreate GitHub workspace if needed
    if [[ -n "${GITHUB_WORKSPACE:-}" ]] && [[ ! -d "$GITHUB_WORKSPACE" ]]; then
        log "mount" "Recreating GitHub workspace: $GITHUB_WORKSPACE"
        sudo mkdir -p "$GITHUB_WORKSPACE"
        sudo chown -R "${workspace_owner:-runner:runner}" "$GITHUB_WORKSPACE"
    fi
    
    log "success" "Build mount created successfully at $mount_path"
}

# Main execution function
main() {
    local force=false
    local mount_path=""
    local unmount=false
    local root_reserve_mb=$DEFAULT_ROOT_RESERVE_MB
    local temp_reserve_mb=$DEFAULT_TEMP_RESERVE_MB
    local swap_size_mb=$DEFAULT_SWAP_SIZE_MB
    local mount_ownership=$DEFAULT_MOUNT_OWNERSHIP
    local overprovision="false"
    local pv_loop_path=$DEFAULT_PV_LOOP_PATH
    local tmp_pv_loop_path=$DEFAULT_TMP_PV_LOOP_PATH
    local remove_docker="false"
    local remove_codeql="false"
    local parallel_jobs=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            --mount)
                mount_path="$2"
                shift 2
                ;;
            --unmount)
                unmount=true
                shift
                ;;
            --root-reserve-mb)
                root_reserve_mb="$2"
                shift 2
                ;;
            --temp-reserve-mb)
                temp_reserve_mb="$2"
                shift 2
                ;;
            --swap-size-mb)
                swap_size_mb="$2"
                shift 2
                ;;
            --mount-ownership)
                mount_ownership="$2"
                shift 2
                ;;
            --overprovision-lvm)
                overprovision="true"
                shift
                ;;
            --remove-docker-images)
                remove_docker="true"
                shift
                ;;
            --remove-codeql)
                remove_codeql="true"
                shift
                ;;
            --parallel-jobs)
                parallel_jobs="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "error" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Set default parallel jobs if not specified
    if [[ -z "$parallel_jobs" ]]; then
        parallel_jobs=$(get_parallel_jobs)
    fi
    
    # Validate mount path
    if [[ -n "$mount_path" ]] && [[ ! "$mount_path" =~ ^/ ]]; then
        log "error" "Mount path must be absolute: $mount_path"
        exit 1
    fi
    
    # Handle unmount operation
    if [[ "$unmount" == "true" ]]; then
        log "info" "GitHub Actions Runner Debloat Tool - Unmount Mode"
        unmount_build_mount "$pv_loop_path" "$tmp_pv_loop_path"
        show_disk_report "=== Final Disk Usage After Unmount ==="
        exit 0
    fi
    
    # Check if we should run
    if ! should_run "$force"; then
        exit 1
    fi
    
    log "info" "GitHub Actions Runner Debloat Tool - Enhanced Version"
    log "info" "This will remove approximately 40GB+ of unused software"
    [[ -n "$mount_path" ]] && log "info" "Will create optimized build mount at: $mount_path"
    
    # Show initial disk report
    show_disk_report "=== Initial Disk Usage ==="
    
    # Get initial disk stats
    local initial_stats
    initial_stats="$(get_disk_stats)"
    local initial_used initial_percent
    initial_used="$(parse_disk_stats "$initial_stats" "used")"
    initial_percent="$(parse_disk_stats "$initial_stats" "percent")"
    
    # Perform cleanup
    perform_cleanup "$remove_docker" "$remove_codeql" "$parallel_jobs"
    
    # Create build mount if requested
    if [[ -n "$mount_path" ]]; then
        create_build_mount "$mount_path" "$root_reserve_mb" "$temp_reserve_mb" "$swap_size_mb" "$mount_ownership" "$overprovision" "$pv_loop_path" "$tmp_pv_loop_path"
    fi
    
    # Show final disk report
    show_disk_report "=== Final Disk Usage ==="
    
    # Calculate and show results
    local final_stats final_used final_percent
    final_stats="$(get_disk_stats)"
    final_used="$(parse_disk_stats "$final_stats" "used")"
    final_percent="$(parse_disk_stats "$final_stats" "percent")"
    
    log "success" "Runner debloat completed successfully!"
    log "info" "Disk usage change: $initial_used ($initial_percent) → $final_used ($final_percent)"
    
    if [[ -n "$mount_path" ]]; then
        log "success" "Optimized build mount available at: $mount_path"
        log "info" "Build mount stats:"
        df -h "$mount_path" 2>/dev/null || true
    fi
}

# Execute main function with all arguments
main "$@"
