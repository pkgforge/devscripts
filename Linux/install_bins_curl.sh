#!/usr/bin/env bash

#-------------------------------------------------------------------------------#
##Requires: coreutils + curl
##Usage
# bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/main/Linux/install_bins_curl.sh")
##Vars
# INSTALL_DIR="/tmp" "${other vars}" bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/main/Linux/install_bins_curl.sh")
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
if [[ "${DEBUG}" = "1" ]] || [[ "${DEBUG}" = "ON" ]]; then
  set -x
fi
# Dependency check
if ! command -v curl &>/dev/null; then
    echo -e "\n[-] FATAL: Install Curl (https://bin.pkgforge.dev/$(uname -m)/curl)\n"
    exit 1
fi

# Global variables for parallel execution
declare -a PARALLEL_PIDS=()
declare -A INSTALL_STATUS=()
MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-10}
# Global sudo usage flag
USE_SUDO=0
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Signal handling for immediate exit
cleanup_on_exit() {
    local exit_code=${1:-130}
    #echo -e "\n[!] Interrupted! Cleaning up background processes..."
    
    # Kill all background jobs from this script
    if [[ ${#PARALLEL_PIDS[@]} -gt 0 ]]; then
        echo "[!] Terminating ${#PARALLEL_PIDS[@]} background jobs..."
        for pid in "${PARALLEL_PIDS[@]}"; do
            if kill -0 "${pid}" 2>/dev/null; then
                kill -TERM "${pid}" 2>/dev/null || true
            fi
        done
        
        # Give processes a moment to terminate gracefully
        sleep 0.5
        
        # Force kill any remaining processes
        for pid in "${PARALLEL_PIDS[@]}"; do
            if kill -0 "${pid}" 2>/dev/null; then
                kill -KILL "${pid}" 2>/dev/null || true
            fi
        done
    fi
    
    # Clean up temporary files
    rm -f "/tmp/symlinks_$$" 2>/dev/null || true
    rm -f "/tmp/install_dirs_$$.lock" 2>/dev/null || true
    
    # Kill any curl processes that might be hanging
    pkill -f "curl.*bin\.pkgforge\.dev" 2>/dev/null || true
    
    #echo "[!] Cleanup completed. Exiting..."
    exit ${exit_code}
}

# Set up signal traps
trap 'cleanup_on_exit 130' SIGINT SIGTERM
trap 'cleanup_on_exit 1' EXIT
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Setup directories and permissions
setup_dirs() {
    # Check if running as root or have passwordless sudo
     if [[ $(id -u) -eq 0 ]] || (command -v sudo &>/dev/null && sudo -n true 2>/dev/null); then
         # System-wide installation
         INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
         INSTALL_DIR_ROOT="/usr/bin"
         INSTALL_PRE="${INSTALL_PRE:-sudo curl -qfsSL}"
         INSTALL_POST="${INSTALL_POST:-sudo chmod +x}"
         SYMLINK_CMD="${SYMLINK_CMD:-sudo ln -fsv}"
         USE_SUDO=1
         echo -e "\n[+] Setting Install Dir (ROOT) :: ${INSTALL_DIR}\n"
     else
         # User-space installation
         INSTALL_DIR="${INSTALL_DIR:-${HOME}/bin}"
         INSTALL_DIR_ROOT="${HOME}/bin"
         INSTALL_PRE="${INSTALL_PRE:-timeout -k 1m 5m curl -qfsSL}"
         INSTALL_POST="${INSTALL_POST:-chmod +x}"
         SYMLINK_CMD="${SYMLINK_CMD:-ln -fsv}"
         USE_SUDO=0
         echo -e "\n[+] Setting Install Dir (USERSPACE) :: ${INSTALL_DIR}\n"
     fi
     
     # If running as root, strip sudo from commands but keep USE_SUDO flag
     if [[ $(id -u) -eq 0 ]]; then
         INSTALL_PRE="${INSTALL_PRE/sudo /}"
         INSTALL_POST="${INSTALL_POST/sudo /}"
         SYMLINK_CMD="${SYMLINK_CMD/sudo /}"
         USE_SUDO=0  # Running as root, no need for sudo
     fi
     
    # Verify directories are writable (create if needed)
     for dir in "$INSTALL_DIR" "$INSTALL_DIR_ROOT"; do
         if [[ ! -d "$dir" ]]; then
             if [[ $USE_SUDO -eq 1 ]]; then
                 if ! sudo mkdir -p "$dir" 2>/dev/null; then
                     echo "[-] ERROR: Cannot create directory: $dir"
                     exit 1
                 fi
             else
                 if ! mkdir -p "$dir" 2>/dev/null; then
                     echo "[-] ERROR: Cannot create directory: $dir"
                     exit 1
                 fi
             fi
         fi
         
         # Test writability with appropriate permissions
         local test_file="${dir}/.write_test_$$"
         if [[ $USE_SUDO -eq 1 ]]; then
             if ! sudo touch "$test_file" 2>/dev/null; then
                 echo "[-] ERROR: Directory not writable: $dir"
                 echo "    Try running with appropriate permissions or set INSTALL_DIR manually"
                 exit 1
             fi
             sudo rm -f "$test_file" 2>/dev/null || true
         else
             if ! touch "$test_file" 2>/dev/null; then
                 echo "[-] ERROR: Directory not writable: $dir"
                 echo "    Try running with appropriate permissions or set INSTALL_DIR manually"
                 exit 1
             fi
             rm -f "$test_file" 2>/dev/null || true
         fi
     done
    
    INSTALL_DIR_LOCALH="${HOME}/.local/bin"
    
    # Create directories with proper locking to prevent race conditions
    local temp_lock="/tmp/install_dirs_$$.lock"
    (
        flock -x 200
        if [[ $USE_SUDO -eq 1 ]]; then
            sudo mkdir -p "${INSTALL_DIR}" "${INSTALL_DIR_ROOT}" "${INSTALL_DIR_LOCALH}"
            sudo chmod 777 -R "${HOME}/.local" 2>/dev/null || true
        else
            mkdir -p "${INSTALL_DIR}" "${INSTALL_DIR_ROOT}" "${INSTALL_DIR_LOCALH}"
        fi
    ) 200>"${temp_lock}"
    rm -f "${temp_lock}" 2>/dev/null || true
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Setup source URL based on architecture
setup_source() {
    if [[ -z ${INSTALL_SRC:-} ]]; then
        local arch
        arch=$(uname -m)
        case ${arch} in
            aarch64) INSTALL_SRC="https://bin.pkgforge.dev/aarch64-Linux" ;;
            riscv64) INSTALL_SRC="https://bin.pkgforge.dev/riscv64-Linux" ;;
            x86_64)  INSTALL_SRC="https://bin.pkgforge.dev/x86_64-Linux" ;;
            *) 
                echo "[-] Unsupported architecture: ${arch}"
                exit 1
                ;;
        esac
        echo -e "\n[+] Fetching Bins from (Default) :: ${INSTALL_SRC}\n"
    else
        echo -e "\n[+] Using Bins from (Specified) :: ${INSTALL_SRC}\n"
    fi
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Setup parallel execution strategy
setup_strategy() {
    if [[ ${PARALLEL:-0} == "1" ]]; then
        USE_PARALLEL=1
        echo -e "\n[+] Installing in Parallel (Fast) Mode [Max ${MAX_PARALLEL_JOBS} concurrent jobs]\n"
    else
        USE_PARALLEL=0
        echo -e "\n[+] Installing in Sequential (Slow) Mode [Re Run : export PARALLEL=1 for Speed]\n"
    fi
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Wait for background jobs to complete and manage job limit
wait_for_jobs() {
    local max_jobs=${1:-${MAX_PARALLEL_JOBS}}
    
    while [[ ${#PARALLEL_PIDS[@]} -ge ${max_jobs} ]]; do
        local new_pids=()
        for pid in "${PARALLEL_PIDS[@]}"; do
            if kill -0 "${pid}" 2>/dev/null; then
                new_pids+=("${pid}")
            else
                wait "${pid}" 2>/dev/null || true
            fi
        done
        PARALLEL_PIDS=("${new_pids[@]}")
        
        if [[ ${#PARALLEL_PIDS[@]} -ge ${max_jobs} ]]; then
            sleep 0.1
        fi
    done
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Wait for all background jobs to complete
wait_all_jobs() {
    echo "[+] Waiting for all downloads to complete..."
    for pid in "${PARALLEL_PIDS[@]}"; do
        # Check if we're being interrupted
        if ! kill -0 "${pid}" 2>/dev/null; then
            continue
        fi
        wait "${pid}" 2>/dev/null || true
    done
    PARALLEL_PIDS=()
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Install binary to single location
install_bin() {
    local src_name="${1}"
    local dest_dir="${2}"
    local dest_name="${3:-${1}}"
    
    # Add timeout to curl commands to prevent hanging
    local install_cmd="${INSTALL_PRE}"
    if [[ ! ${install_cmd} =~ timeout ]]; then
        install_cmd="timeout -k 30s 120s ${install_cmd}"
    fi
    
    if eval "${install_cmd}" "${INSTALL_SRC}/${src_name}" -o "${dest_dir}/${dest_name}"; then
        eval "${INSTALL_POST}" "${dest_dir}/${dest_name}"
        INSTALL_STATUS["${src_name}"]="success"
        return 0
    else
        echo "[-] Failed to install ${src_name} to ${dest_dir}/${dest_name}"
        INSTALL_STATUS["${src_name}"]="failed"
        return 1
    fi
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Parallel wrapper for install_bin
install_bin_parallel() {
    local src_name="${1}"
    local dest_dir="${2}"
    local dest_name="${3:-${1}}"
    
    if [[ ${USE_PARALLEL} == "1" ]]; then
        wait_for_jobs "${MAX_PARALLEL_JOBS}"
        (
            # Set up signal handling in subshell
            trap 'exit 130' SIGINT SIGTERM
            install_bin "${src_name}" "${dest_dir}" "${dest_name}"
        ) &
        local bg_pid=$!
        PARALLEL_PIDS+=("${bg_pid}")
    else
        install_bin "${src_name}" "${dest_dir}" "${dest_name}"
    fi
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Create symlink for binary (with file existence check)
symlink_bin() {
    local target_path="${1}"
    local dest_dir="${2}"
    local link_name="${3}"
    
    # Wait a bit for file to be available if running in parallel
    if [[ ${USE_PARALLEL} == "1" ]]; then
        local attempts=0
        while [[ ! -f "${target_path}" && ${attempts} -lt 30 ]]; do
            sleep 0.1
            ((attempts++))
        done
    fi
    
    if [[ -f "${target_path}" ]]; then
        if [[ "${target_path}" != "${dest_dir}/${link_name}" ]]; then
           eval "${SYMLINK_CMD}" "${target_path}" "${dest_dir}/${link_name}" 2>/dev/null || {
               echo "[-] Warning: Failed to create symlink ${dest_dir}/${link_name} -> ${target_path}"
               return 1
           }
        fi
    else
        echo "[-] Warning: Target ${target_path} does not exist for symlink ${link_name}"
        return 1
    fi
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Install binary to multiple locations with symlinks
install_bin_multi() {
    local src_name="${1}"
    local dest_name="${2:-${1}}"
    local localh_flag="${3:-}"
    
    # Install to primary location
    install_bin_parallel "${src_name}" "${INSTALL_DIR}" "${dest_name}"
    
    # Store symlink creation for later (after all downloads complete)
    echo "${INSTALL_DIR}/${dest_name}:${INSTALL_DIR_ROOT}/${dest_name}" >> "/tmp/symlinks_$$"
    
    if [[ ${localh_flag} == "localh" ]]; then
        echo "${INSTALL_DIR}/${dest_name}:${INSTALL_DIR_LOCALH}/${dest_name}" >> "/tmp/symlinks_$$"
    fi
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Create all symlinks after downloads complete
create_symlinks() {
    if [[ -f "/tmp/symlinks_$$" ]]; then
        echo "[+] Creating symlinks..."
        while IFS=':' read -r target_path link_path; do
            local dest_dir dest_name
            dest_dir=$(dirname "${link_path}")
            dest_name=$(basename "${link_path}")
            symlink_bin "${target_path}" "${dest_dir}" "${dest_name}"
        done < "/tmp/symlinks_$$"
        rm -f "/tmp/symlinks_$$"
    fi
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Main installation function
install_all_bins() {
    local bins=(
        # Format: "source_name" or "source_name:dest_name" or "source_name=multi" or "source_name=multi+localh"
        "7z=multi"
        "actionlint"
        "anew"
        "anew-rs"
        "ansi2html"
        "ansi2txt"
        "archey"
        "aria2:aria2c"
        "askalono"
        "bsdtar"
        "b3sum=multi"
        "bita"
        "btop"
        "chafa"
        "cloudflared"
        "croc"
        "csvtk"
        "cutlines"
        "dbin"
        "dasel"
        "delta"
        "ds"
        "dos2unix"
        "duf"
        "duplicut"
        "dust"
        "dwarfs-tools:dwarfs"
        "dwarfs-tools:mkdwarfs"
        "dysk"
        "eget"
        "epoch"
        "faketty"
        "fastfetch"
        "freeze"
        "fusermount3:fusermount"
        "gdu"
        "gh"
        "gitleaks"
        "git-sizer"
        "glab"
        "glow"
        "httpx=multi+localh"
        "huggingface-cli"
        "husarnet"
        "husarnet-daemon"
        "imgcat"
        "jc"
        "jq"
        "logdy"
        "micro"
        "miniserve"
        "minisign"
        "ncdu"
        "notify"
        "ouch"
        "oras"
        "pipetty"
        "pixterm"
        "qsv"
        "rclone"
        "ripgrep:rg"
        "rga"
        "rsync"
        "script"
        "shellcheck"
        "soar"
        "speedtest-go"
        "sstrip"
        "strace"
        "sttr"
        "tailscale"
        "tailscaled"
        "taplo"
        "tldr"
        "tldr:tealdeer"
        "tmux"
        "tok"
        "trufflehog"
        "trurl"
        "ulexec"
        "unfurl"
        "upx"
        "validtoml"
        "wget"
        "wget2"
        "wormhole-rs"
        "xq"
        "xz"
        "unxz"
        "yq"
        "yj"
        "zapper"
        "zapper-stealth:zproccer"
        "zerotier-cli"
        "zerotier-idtool"
        "zerotier-one"
        "zstd=multi"
    )
    
    # Initialize symlinks file
    rm -f "/tmp/symlinks_$$"
    
    for bin_spec in "${bins[@]}"; do
        local src_name dest_name multi_flag localh_flag=""
        
        # Parse the specification
        if [[ ${bin_spec} == *"=multi"* ]]; then
            # Multi-location install
            multi_flag="multi"
            if [[ ${bin_spec} == *"+localh"* ]]; then
                localh_flag="localh"
                src_name="${bin_spec%=multi+localh}"
            else
                src_name="${bin_spec%=multi}"
            fi
            dest_name="${src_name}"
        elif [[ ${bin_spec} == *":"* ]]; then
            # Symlink case
            IFS=':' read -ra parts <<< "${bin_spec}"
            src_name="${parts[0]}"
            dest_name="${parts[1]}"
        else
            # Simple case
            src_name="${bin_spec}"
            dest_name="${bin_spec}"
        fi
        
        echo "[+] Installing: ${src_name} -> ${dest_name}"
        
        if [[ ${multi_flag} == "multi" ]]; then
            install_bin_multi "${src_name}" "${dest_name}" "${localh_flag}"
        elif [[ ${src_name} != "${dest_name}" ]]; then
            # This is a symlink case - install first, then queue symlink
            install_bin_parallel "${src_name}" "${INSTALL_DIR}" "${src_name}"
            echo "${INSTALL_DIR}/${src_name}:${INSTALL_DIR}/${dest_name}" >> "/tmp/symlinks_$$"
        else
            install_bin_parallel "${src_name}" "${INSTALL_DIR}" "${dest_name}"
        fi
    done
    
    # Wait for all downloads to complete
    if [[ ${USE_PARALLEL} == "1" ]]; then
        wait_all_jobs
    fi
    
    # Create all symlinks after downloads complete
    create_symlinks
    
    # Report failed installations
    local failed_list=()
    for bin_name in "${!INSTALL_STATUS[@]}"; do
        if [[ ${INSTALL_STATUS[${bin_name}]} == "failed" ]]; then
            failed_list+=("${bin_name}")
        fi
    done
    
    if [[ ${#failed_list[@]} -gt 0 ]]; then
        echo -e "\n[!] Failed to install: ${failed_list[*]}"
    fi
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Main execution
main() {
    setup_dirs
    setup_source  
    setup_strategy
    
    local pre_size
    pre_size=$(du -sh "${INSTALL_DIR}" 2>/dev/null | cut -f1)
    
    install_all_bins
    
    set +x; echo
    
    # Clean up any remaining background processes
    if [[ ${USE_PARALLEL} == "1" ]]; then
        wait_all_jobs
    fi
    
    reset >/dev/null 2>&1; echo
    
    # Fix permissions
    if [[ $USE_SUDO -eq 1 ]]; then
        sudo chmod 777 -R "${HOME}/.local" 2>/dev/null || true
    fi
    
    # Check PATH
    local path_dirs=("${INSTALL_DIR_ROOT}" "${INSTALL_DIR}" "${INSTALL_DIR_LOCALH}")
    local missing_paths=()
    
    for dir in "${path_dirs[@]}"; do
        if [[ ":${PATH}:" != *":${dir}:"* ]]; then
            missing_paths+=("${dir}")
        fi
    done
    
    if [[ ${#missing_paths[@]} -gt 0 ]]; then
        echo -e "\n[!] Adjust your \"\$PATH\" to include: [ ${missing_paths[*]} ]"
        echo -e "[!] Current \"\$PATH\" : [ ${PATH} ]\n"
    fi
    
    # Print stats
    local post_size
    post_size=$(du -sh "${INSTALL_DIR}" 2>/dev/null | cut -f1)
    echo -e "\n[+] Disk Size (${INSTALL_DIR}) :: ${pre_size:-0K} --> ${post_size:-0K}\n"
    
    echo -e "[+] Installation completed!"
    
    # Cleanup
    rm -f "/tmp/symlinks_$$" 2>/dev/null || true
    
    # Remove the EXIT trap since we completed successfully
    trap - EXIT
}
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#-------------------------------------------------------------------------------#