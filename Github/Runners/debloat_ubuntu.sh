#!/usr/bin/env bash

# GitHub Actions Runner Debloat CLI Tool
# Removes bloat from GitHub Actions runners to free up ~40GB of space
#
# Usage:
#   ./debloat.sh              # Auto-detect runner environment
#   ./debloat.sh --force      # Force run regardless of environment
#   ./debloat.sh --help       # Show help

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly PROVISIONER_FILE="/opt/runner/provisioner"

# Function to print colored output
log() {
    local level="$1"
    shift
    case "$level" in
        "info")  echo -e "${BLUE}[INFO]${NC} $*" ;;
        "warn")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "error") echo -e "${RED}[ERROR]${NC} $*" ;;
        "success") echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
    esac
}

# Function to show help
show_help() {
    cat << EOF
GitHub Actions Runner Debloat Tool

DESCRIPTION:
    Removes bloat from GitHub Actions runners to free up approximately 40GB of disk space.
    By default, only runs when executed as 'runner' user and provisioner file exists.

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    --force     Force execution regardless of environment detection
    --help      Show this help message

EXAMPLES:
    $SCRIPT_NAME              # Auto-detect runner environment
    $SCRIPT_NAME --force      # Force run on any system
    
WHAT GETS REMOVED:
    • Android NDK (~12GB)     • Haskell (~5GB)
    • HostedToolCache (~12GB) • Snap packages (~5GB)
    • DotNET (~2GB)           • GCP SDK (~2GB)
    • Swift (~1.7GB)          • JVM (~1.5GB)
    • Mono (~1.5GB)           • PowerShell (~1GB)
    • Azure CLI (~800MB)      • Miniconda (~700MB)
    • Microsoft tools (~700MB) • AWS CLI (~500MB)
    • Julia (~500MB)          • Heroku (~500MB)
    • AZ PowerShell (~500MB)

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
    local root_disk
    root_disk="$(df -h / | awk 'NR==2 {print $1}')"
    
    echo "$(df -h "$root_disk" | awk 'NR==2 {print $1":"$2":"$3":"$5}')"
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

# Function to remove directories safely
safe_remove() {
    local paths=("$@")
    local removed_count=0
    
    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            if sudo rm -rf "$path" 2>/dev/null; then
                ((removed_count++))
            fi
        fi
    done
    
    return $removed_count
}

# Function to handle snap removal
remove_snaps() {
    log "info" "Starting snap package removal..."
    
    # Check if snap is installed
    if ! command -v snap >/dev/null 2>&1; then
        log "info" "Snap not installed, skipping snap removal"
        return 0
    fi
    
    # Get list of installed snaps
    local snaps
    snaps=$(snap list 2>/dev/null | awk 'NR>1 {print $1}' | grep -v -E '^(core|bare|snapd)' || true)
    
    if [[ -n "$snaps" ]]; then
        log "info" "Removing user snap packages..."
        # Remove user snaps in parallel
        echo "$snaps" | xargs -n1 -P4 -I{} sudo snap remove --purge {} 2>/dev/null || true
    fi
    
    # Remove system snaps in correct dependency order
    local system_snaps=("bare" "core20" "core22" "core18" "core" "snapd")
    for snap in "${system_snaps[@]}"; do
        if snap list "$snap" >/dev/null 2>&1; then
            log "info" "Removing system snap: $snap"
            sudo snap remove --purge "$snap" >/dev/null 2>&1 || true
        fi
    done
    
    # Disable and remove snapd
    log "info" "Disabling snapd services..."
    sudo systemctl disable --now snapd.service snapd.socket snapd.seeded.service >/dev/null 2>&1 || true
    sudo systemctl mask snapd >/dev/null 2>&1 || true
    
    # Remove snapd package
    sudo apt purge -y snapd >/dev/null 2>&1 || true
    
    # Clean up snap directories
    safe_remove /snap /var/snap /var/cache/snapd /var/lib/snapd
    safe_remove "$HOME/snap" "/root/snap"
    
    # Prevent snapd reinstallation
    sudo tee /etc/apt/preferences.d/no-snap.pref >/dev/null 2>&1 << 'EOF' || true
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF
    
    # Unmount any remaining snap mounts
    df -h 2>/dev/null | awk '/\/snap\// {print $6}' | while IFS= read -r mount; do
        sudo umount "$mount" >/dev/null 2>&1 || true
    done
    
    log "success" "Snap removal completed"
}

# Function to perform cleanup operations
perform_cleanup() {
    log "info" "Starting parallel cleanup operations..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package cache
    log "info" "Updating package cache..."
    sudo apt update -qq >/dev/null 2>&1
    
    # Define cleanup jobs with descriptions
    declare -A cleanup_jobs=(
        ["android"]="Android NDK (~12GB):/usr/local/lib/android"
        ["aws"]="AWS CLI (~500MB):/usr/local/*aws*cli*"
        ["azure"]="Azure CLI (~800MB):/opt/az"
        ["azpowershell"]="AZ PowerShell (~500MB):/usr/share/az_*"
        ["dotnet"]="DotNET (~2GB):/usr/lib/dotnet:/usr/share/dotnet"
        ["gcp"]="GCP SDK (~2GB):/usr/lib/google-cloud-sdk"
        ["haskell"]="Haskell (~5GB):/usr/local/.ghcup"
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
    for job in "${!cleanup_jobs[@]}"; do
        {
            local info="${cleanup_jobs[$job]}"
            local desc="${info%%:*}"
            local paths="${info#*:}"
            
            log "info" "Removing $desc"
            IFS=':' read -ra path_array <<< "$paths"
            safe_remove "${path_array[@]}"
        } &
        pids+=($!)
    done
    
    # Handle snap removal separately
    remove_snaps &
    pids+=($!)
    
    # Wait for all cleanup jobs to complete
    log "info" "Waiting for cleanup operations to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Final system cleanup
    log "info" "Running final system cleanup..."
    sudo apt autoremove -y -qq >/dev/null 2>&1 || true
    sudo apt autoclean -qq >/dev/null 2>&1 || true
    sudo apt update -qq >/dev/null 2>&1 || true
    
    # Clean package cache
    sudo apt clean >/dev/null 2>&1 || true
    
    unset DEBIAN_FRONTEND
}

# Main execution function
main() {
    local force=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
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
    
    # Check if we should run
    if ! should_run "$force"; then
        exit 1
    fi
    
    log "info" "GitHub Actions Runner Debloat Tool"
    log "info" "This will remove approximately 40GB of unused software"
    
    # Get initial disk stats
    local initial_stats
    initial_stats="$(get_disk_stats)"
    local root_disk total_size initial_used initial_percent
    root_disk="$(parse_disk_stats "$initial_stats" "disk")"
    total_size="$(parse_disk_stats "$initial_stats" "total")"
    initial_used="$(parse_disk_stats "$initial_stats" "used")"
    initial_percent="$(parse_disk_stats "$initial_stats" "percent")"
    
    log "info" "Initial disk usage: $initial_used / $total_size ($initial_percent used)"
    
    # Perform cleanup
    perform_cleanup
    
    # Get final disk stats
    local final_stats final_used final_percent
    final_stats="$(get_disk_stats)"
    final_used="$(parse_disk_stats "$final_stats" "used")"
    final_percent="$(parse_disk_stats "$final_stats" "percent")"
    
    # Show results
    log "success" "Cleanup completed successfully!"
    log "info" "Disk usage: $initial_used → $final_used ($initial_percent → $final_percent)"
    
    # Calculate space freed (approximate - doesn't account for unit differences)
    log "success" "Runner debloat completed - significant disk space has been freed"
}

# Execute main function with all arguments
main "$@"
