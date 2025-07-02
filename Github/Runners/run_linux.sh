#!/usr/bin/env bash
##Enhanced GitHub Self-Hosted Runner CLI
#SELF: bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Github/Runners/run_linux.sh")
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Set up environment
if [[ -z "${USER+x}" ]] || [[ -z "${USER##*[[:space:]]}" ]]; then
 USER="$(whoami | tr -d '[:space:]')"
fi
if [[ -z "${HOME+x}" ]] || [[ -z "${HOME##*[[:space:]]}" ]]; then
 #HOME="$(getent passwd "${USER}" | awk -F':' 'NF >= 6 {print $6}' | tr -d '[:space:]')"
 HOME="$(getent passwd "${USER}" | cut -d: -f6)"
fi
if [[ -z "${SYSTMP+x}" ]] || [[ -z "${SYSTMP##*[[:space:]]}" ]]; then
 SYSTMP="$(dirname "$(mktemp -u)" | tr -d '[:space:]')"
fi
export USER HOME SYSTMP
pushd "${HOME}" &>/dev/null || exit 1
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Script metadata
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="0.0.1"
SCRIPT_DESCRIPTION="GitHub Self-Hosted Runner Management Tool"
#Default configuration
DEFAULT_CONTAINER_NAME="self-hosted-$(uname -m)"
DEFAULT_CONTAINER_IMAGE="pkgforge/gh-runner-aarch64-ubuntu"
DEFAULT_CONTAINER_TMP_VOLUME="/var/lib/containers/tmp"
FALLBACK_CONTAINER_TMP_VOLUME="${HOME}/.tmp/containers/tmp"
DEFAULT_ENV_FILE="${HOME}/.config/gh-runner/.env"
DEFAULT_LOG_FILE=""
DEFAULT_PULL_POLICY="always"
#Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
#BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
#Logging functions
log_info() {
    echo -e "${GREEN}[+]${NC} $1"
}
log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}
log_error() {
    echo -e "${RED}[-]${NC} $1"
}
log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Help function
show_help() {
    cat << EOF
${SCRIPT_DESCRIPTION}

Usage: ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    -n, --name NAME             Container name (default: ${DEFAULT_CONTAINER_NAME})
    -i, --image IMAGE           Container image (default: ${DEFAULT_CONTAINER_IMAGE})
    -e, --env-file FILE         Environment file path (default: ${DEFAULT_ENV_FILE})
    -l, --log-file FILE         Log file path (default: temporary file)
    -p, --pull-policy POLICY    Pull policy: always|missing|never (default: ${DEFAULT_PULL_POLICY})
    
    --cleanup                   Only cleanup existing containers and exit
    --stop                      Stop running containers and exit
    --logs                      Show logs from running container
    --status                    Show container status
    
    --no-sudo                   Force running without sudo
    --force-sudo                Force running with sudo
    
    -v, --verbose               Enable verbose output
    -d, --debug                 Enable debug output
    -q, --quiet                 Suppress non-essential output
    
    -h, --help                  Show this help message
    --version                   Show version information

ENVIRONMENT VARIABLES:
    PODMAN_CONTAINER_NAME       Same as --name
    PODMAN_CONTAINER_IMAGE      Same as --image  
    PODMAN_ENV_FILE             Same as --env-file
    PODMAN_LOG_FILE             Same as --log-file
    PODMAN_PULL_POLICY          Same as --pull-policy
    PODMAN_SUDO                 Force sudo usage (set to 'sudo' or '')
    DEBUG                       Enable debug output (set to '1')

EXAMPLES:
    # Run with default settings
    ${SCRIPT_NAME}
    
    # Run with custom container name and image
    ${SCRIPT_NAME} --name my-runner --image custom/runner:latest
    
    # Run with custom environment file
    ${SCRIPT_NAME} --env-file /path/to/custom/.env
    
    # Cleanup existing containers
    ${SCRIPT_NAME} --cleanup
    
    # Show status of running containers
    ${SCRIPT_NAME} --status
    
    # Show logs from running container
    ${SCRIPT_NAME} --logs

NOTES:
    - Requires Podman to be installed and configured
    - May require passwordless sudo if Podman needs elevated privileges
    - Environment variables are overridden by command-line arguments
    - For more information: https://github.com/pkgforge/devscripts/blob/main/Github/Runners/README.md

EOF
}
#Version function
show_version() {
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
}
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            -i|--image)
                CONTAINER_IMAGE="$2"
                shift 2
                ;;
            -e|--env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            -l|--log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -p|--pull-policy)
                PULL_POLICY="$2"
                if [[ ! "${PULL_POLICY}" =~ ^(always|missing|never)$ ]]; then
                    log_error "Invalid pull policy: ${PULL_POLICY}. Must be: always, missing, or never"
                    exit 1
                fi
                shift 2
                ;;
            --cleanup)
                ACTION="cleanup"
                shift
                ;;
            --stop)
                ACTION="stop"
                shift
                ;;
            --logs)
                ACTION="logs"
                shift
                ;;
            --status)
                ACTION="status"
                shift
                ;;
            --no-sudo)
                FORCE_NO_SUDO=1
                shift
                ;;
            --force-sudo)
                FORCE_SUDO=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -d|--debug)
                DEBUG=1
                shift
                ;;
            -q|--quiet)
                QUIET=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Set configuration from environment variables and arguments
set_configuration() {
    #Set from environment variables first, then override with CLI args
    CONTAINER_NAME="${CONTAINER_NAME:-${PODMAN_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}}"
    CONTAINER_IMAGE="${CONTAINER_IMAGE:-${PODMAN_CONTAINER_IMAGE:-$DEFAULT_CONTAINER_IMAGE}}"
    ENV_FILE="${ENV_FILE:-${PODMAN_ENV_FILE:-$DEFAULT_ENV_FILE}}"
    LOG_FILE="${LOG_FILE:-${PODMAN_LOG_FILE:-$DEFAULT_LOG_FILE}}"
    PULL_POLICY="${PULL_POLICY:-${PODMAN_PULL_POLICY:-$DEFAULT_PULL_POLICY}}"
    
    #Set log file to temporary if not specified
    if [[ -z "${LOG_FILE}" ]]; then
        LOG_FILE="$(mktemp)"
    fi
    
    #Export for consistency with original script
    export PODMAN_CONTAINER_NAME="${CONTAINER_NAME}"
    export PODMAN_CONTAINER_IMAGE="${CONTAINER_IMAGE}"
    export PODMAN_ENV_FILE="$(realpath ${ENV_FILE})"
    export PODMAN_LOG_FILE="$(realpath ${LOG_FILE})"
    export PODMAN_PULL_POLICY="${PULL_POLICY}"
}
#Check and configure sudo requirements
check_sudo_requirements() {
    if [[ "${FORCE_NO_SUDO}" == "1" ]]; then
        PODMAN_SUDO=""
        log_debug "Forcing no sudo usage"
    elif [[ "${FORCE_SUDO}" == "1" ]]; then
        PODMAN_SUDO="sudo"
        log_debug "Forcing sudo usage"
    elif [[ -n "${PODMAN_SUDO}" ]]; then
        log_debug "Using PODMAN_SUDO environment variable: '${PODMAN_SUDO}'"
    else
        # Auto-detect sudo requirements
        log_info "Checking if sudo is required for podman operations..."
        if podman version &>/dev/null; then
            PODMAN_SUDO=""
            log_info "Podman works without sudo"
        else
            if sudo podman version &>/dev/null; then
                PODMAN_SUDO="sudo"
                log_info "Podman requires sudo"
                # Check if we can actually use sudo
                if [[ "$(id -u)" -ne 0 ]] && ! sudo -n -l | grep -qi 'NOPASSWD'; then
                    log_error "Podman requires sudo but passwordless sudo is not configured"
                    log_error "READ: https://web.archive.org/web/20230614212916/https://linuxhint.com/setup-sudo-no-password-linux/"
                    exit 1
                fi
            else
                log_error "Podman is not working with or without sudo"
                exit 1
            fi
        fi
    fi
    export PODMAN_SUDO
}
#Validate requirements
validate_requirements() {
    # Check if running as root
    if [[ "$(id -u)" -eq 0 ]]; then
        log_info "USER:$(whoami) Running as root, skipping passwordless Sudo Checks"
    else
        if sudo -n -l | grep -qi 'NOPASSWD'; then
            log_info "Passwordless sudo is configured"
            [[ "${DEBUG}" == "1" ]] && sudo -n -l 2>/dev/null
        else
            log_warn "Passwordless sudo is NOT configured (may still work if docker/podman don't require sudo)"
        fi
    fi

    # Check if podman is installed
    if ! command -v podman &>/dev/null; then
        log_error "Podman is NOT installed/configured"
        log_error "Install ALL dependencies && configure ENV VARS|PATH"
        log_error "READ: https://github.com/pkgforge/devscripts/blob/main/Github/Runners/README.md#additional-notes--refs"
        exit 1
    fi

    # Check environment file
    if [[ ! -s "${ENV_FILE}" ]]; then
        log_error "Empty/Non-existent environment file: ${ENV_FILE}"
        log_error "Create the environment file with required GitHub runner configuration"
        exit 1
    fi
}
#Show current configuration
show_configuration() {
    if [[ "${QUIET}" != "1" ]]; then
        echo
        log_info "Configuration:"
        echo "  Container Name: ${CONTAINER_NAME}"
        echo "  Container Image: ${CONTAINER_IMAGE}"
        echo "  Environment File: ${ENV_FILE}"
        echo "  Log File: ${LOG_FILE}"
        echo "  Pull Policy: ${PULL_POLICY}"
        echo "  Podman Sudo: '${PODMAN_SUDO}'"
        echo "  User: ${USER}"
        echo "  Home: ${HOME}"
        echo "  Working Directory: $(realpath .)"
        echo "  PATH: ${PATH}"
        echo
    fi
}
#Cleanup function
cleanup_containers() {
    log_info "Cleaning up existing containers..."
    ${PODMAN_SUDO} podman stop "${CONTAINER_NAME}" &>/dev/null
    ${PODMAN_SUDO} podman rm "${CONTAINER_NAME}" --force &>/dev/null
    
    if [[ "$ACTION" == "cleanup" ]]; then
        log_info "Removing container image..."
        ${PODMAN_SUDO} podman rmi "${CONTAINER_IMAGE}" --force &>/dev/null
        log_info "Cleanup completed"
        exit 0
    fi
}
#Stop containers
stop_containers() {
    log_info "Stopping running containers..."
    ${PODMAN_SUDO} podman stop "$(${PODMAN_SUDO} podman ps -aqf name=${CONTAINER_NAME})" &>/dev/null &
    wait
    ${PODMAN_SUDO} podman stop "$(${PODMAN_SUDO} podman ps -aqf name=${CONTAINER_NAME})" &>/dev/null && sleep 5
    log_info "Containers stopped"
}
#Show logs
show_logs() {
    local container_id
    container_id="$(${PODMAN_SUDO} podman ps -qf name=${CONTAINER_NAME})"
    
    if [[ -z "${container_id}" ]]; then
        log_error "No running container found with name: ${CONTAINER_NAME}"
        exit 1
    fi
    
    log_info "Showing logs for container: ${CONTAINER_NAME} (${container_id})"
    ${PODMAN_SUDO} podman logs -f "${container_id}"
}
#Show status
show_status() {
    echo
    log_info "Container Status:"
    ${PODMAN_SUDO} podman ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Created}}"
    echo
    log_info "All Running Containers:"
    ${PODMAN_SUDO} podman ps
}
#Pull container image
pull_image() {
    case "${PULL_POLICY}" in
        always)
            log_info "Pulling latest container image..."
            ${PODMAN_SUDO} podman pull "${CONTAINER_IMAGE}"
            ;;
        missing)
            if ! ${PODMAN_SUDO} podman image exists "${CONTAINER_IMAGE}"; then
                log_info "Image not found locally, pulling..."
                ${PODMAN_SUDO} podman pull "${CONTAINER_IMAGE}"
            else
                log_info "Image exists locally, skipping pull"
            fi
            ;;
        never)
            log_info "Pull policy set to 'never', skipping image pull"
            ;;
    esac
}
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Main runner function
run_container() {
    #Cleanup existing containers
    cleanup_containers
    
    #Pull image based on policy
    pull_image
    
    #Create required directories
    ${PODMAN_SUDO} mkdir -p "${DEFAULT_CONTAINER_TMP_VOLUME}" 2>/dev/null
    if [[ ! -d "${DEFAULT_CONTAINER_TMP_VOLUME}" || ! -w "${DEFAULT_CONTAINER_TMP_VOLUME}" ]]; then
        mkdir -p "${FALLBACK_CONTAINER_TMP_VOLUME}" 2>/dev/null
        if [[ ! -d "${FALLBACK_CONTAINER_TMP_VOLUME}" || ! -w "${FALLBACK_CONTAINER_TMP_VOLUME}" ]]; then
           log_error "Failed to create TMP Volume: ${FALLBACK_CONTAINER_TMP_VOLUME}"
           exit 1
        else
           log_warn "Using Fallback TMP Volume: ${FALLBACK_CONTAINER_TMP_VOLUME}"
           CONTAINER_TMP_VOLUME="${FALLBACK_CONTAINER_TMP_VOLUME}"
        fi
    else
        log_info "Using Default TMP Volume: ${DEFAULT_CONTAINER_TMP_VOLUME}"
        CONTAINER_TMP_VOLUME="${DEFAULT_CONTAINER_TMP_VOLUME}"
    fi
    
    #Start container
    log_info "Starting runner container (LOGFILE: ${LOG_FILE})"
    if [[ "${DEBUG}" == "1" ]]; then
        set -x
    fi
    
    nohup ${PODMAN_SUDO} podman run \
        --privileged \
        --network="bridge" \
        --systemd="always" \
        --ulimit="host" \
        --volume="${CONTAINER_TMP_VOLUME}:/tmp" \
        --tz="UTC" \
        --pull="${PULL_POLICY}" \
        --name="${CONTAINER_NAME}" \
        --rm \
        --env-file="${ENV_FILE}" \
        "${CONTAINER_IMAGE}" > "${LOG_FILE}" 2>&1 &
    
    if [[ "${DEBUG}" == "1" ]]; then
        set +x
    fi
    
    log_info "Waiting 30s for container to start..."
    sleep 30
    
    #Get container details
    local container_id
    container_id="$(${PODMAN_SUDO} podman ps -qf name=${CONTAINER_NAME})"
    export PODMAN_ID="${container_id}"
    
    if [[ -z "${container_id}" ]]; then
        log_error "Container failed to start. Check logs: ${LOG_FILE}"
        cat "${LOG_FILE}"
        exit 1
    fi
    
    local log_path
    log_path="$(${PODMAN_SUDO} podman inspect --format='{{.HostConfig.LogConfig.Path}}' ${CONTAINER_NAME} 2>/dev/null || echo "N/A")"
    export PODMAN_LOGPATH="${log_path}"
    
    log_info "Container started successfully"
    log_info "Container ID: ${container_id}"
    log_info "Container Log Path: ${log_path}"
    log_info "Script Log File: ${LOG_FILE}"
    
    #Execute runner manager
    log_info "Executing runner manager..."
    ${PODMAN_SUDO} podman exec --user "runner" --env-file="${ENV_FILE}" "${container_id}" "/usr/local/bin/manager.sh" >> "${LOG_FILE}" 2>&1 &
    
    sleep 10
    
    #Monitor runner process
    log_info "Monitoring runner process..."
    while true; do
        if ! pgrep -f "/usr/local/bin/manager.sh" > /dev/null; then
            log_warn "Runner process has stopped"
            if [[ "${VERBOSE}" == "1" ]]; then
                cat "${LOG_FILE}"
            fi
            ${PODMAN_SUDO} podman stop "${container_id}" --ignore
            break
        fi
        sleep 5
    done
    
    log_info "Runner completed"
}
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Main function
main() {
    #Parse command line arguments
    parse_arguments "$@"
    
    #Set configuration
    set_configuration
    
    #Handle special actions first
    case "${ACTION:-}" in
        cleanup)
            cleanup_containers
            exit 0
            ;;
        stop)
            stop_containers
            exit 0
            ;;
        logs)
            show_logs
            exit 0
            ;;
        status)
            show_status
            exit 0
            ;;
    esac
    
    #Validate requirements
    validate_requirements
    
    #Check sudo requirements
    check_sudo_requirements
    
    #Show configuration
    show_configuration
    
    #Run the container
    run_container
    
    #Final status
    if [[ "${QUIET}" != "1" ]]; then
        echo
        log_info "Runner completed successfully"
        log_info "Log file: ${LOG_FILE}"
        echo
        log_info "Useful commands:"
        echo "  View logs: tail -f ${LOG_FILE}"
        echo "  Container status: ${PODMAN_SUDO} podman ps"
        echo "  Remove all containers: ${PODMAN_SUDO} podman ps -aq | xargs ${PODMAN_SUDO} podman stop 2>/dev/null && ${PODMAN_SUDO} podman rm \"\$(${PODMAN_SUDO} podman ps -aq)\" --force"
        echo "  Remove all images: ${PODMAN_SUDO} podman rmi -f \$(${PODMAN_SUDO} podman images -q) &>/dev/null"
        echo
    fi
}
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Run main function with all arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#Cleanup
popd &>/dev/null || true
#EOF
#------------------------------------------------------------------------------------#