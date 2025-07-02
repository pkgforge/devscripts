#!/usr/bin/env bash

##Helper Script to auto run self-hosted runners
#SELF: bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Github/Runners/run_linux.sh")

#------------------------------------------------------------------------------------#
#Requires passwordless sudo (only if needed for docker/podman)
if [ "$(id -u)" -eq 0 ]; then
    echo -e "\n[+] USER:$(whoami) Running as root, skipping passwordless Sudo Checks"
else
    if sudo -n -l | grep -qi 'NOPASSWD'; then
       echo -e "\n[+] Passwordless sudo is Configured"
       sudo -n -l 2>/dev/null
    else
       echo -e "\n[+] Passwordless sudo is NOT Configured (may still work if docker/podman don't require sudo)"
    fi
fi
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Sanity Check & Sudo Detection
if ! command -v podman &>/dev/null; then
   echo -e "\n[-] Podman is NOT Installed/Configured"
   echo -e "[-] Install ALL Dependencies && Configure ENV VARS|PATH\n"
   echo -e "\n[-] READ: https://github.com/pkgforge/devscripts/blob/main/Github/Runners/README.md#additional-notes--refs\n"
   exit 1
fi

#Determine if sudo is needed for podman
echo -e "\n[+] Checking if sudo is required for podman operations..."
if podman version &>/dev/null; then
    PODMAN_SUDO=""
    echo -e "[+] Podman works without sudo"
else
    if sudo podman version &>/dev/null; then
        PODMAN_SUDO="sudo"
        echo -e "[+] Podman requires sudo"
        # Check if we can actually use sudo
        if [ "$(id -u)" -ne 0 ] && ! sudo -n -l | grep -qi 'NOPASSWD'; then
            echo -e "\n[-] Podman requires sudo but passwordless sudo is not configured"
            echo -e "\n[-] READ: https://web.archive.org/web/20230614212916/https://linuxhint.com/setup-sudo-no-password-linux/\n"
            exit 1
        fi
    else
        echo -e "\n[-] Podman is not working with or without sudo"
        exit 1
    fi
fi
export PODMAN_SUDO
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##ENV
 SYSTMP="$(dirname $(mktemp -u))" && export SYSTMP="$SYSTMP"
 USER="$(whoami)" && export USER="${USER}"
 HOME="$(getent passwd ${USER} | cut -d: -f6)" && export HOME="${HOME}" ; pushd "${HOME}" &>/dev/null
 echo -e "\n[+] USER = ${USER}"
 echo -e "[+] HOME = ${HOME}"
 echo -e "[+] WORKDIR = $(realpath .)"
 echo -e "[+] PATH = ${PATH}"
 echo -e "[+] PODMAN_SUDO = '${PODMAN_SUDO}'\n"
#Cleanup Existing Containers
if [ -z "${PODMAN_CONTAINER_NAME}" ]; then
 echo -e "\n[+] Setting Default Container Name: self-hosted-$(uname -m)"
  export PODMAN_CONTAINER_NAME="self-hosted-$(uname -m)"
  ${PODMAN_SUDO} podman stop "${PODMAN_CONTAINER_NAME}" &>/dev/null
  ${PODMAN_SUDO} podman rm "${PODMAN_CONTAINER_NAME}" --force &>/dev/null
else
 export PODMAN_CONTAINER_NAME="${PODMAN_CONTAINER_NAME}"
  echo -e "\n[+] Setting Default Container Name: ${PODMAN_CONTAINER_NAME}"
  ${PODMAN_SUDO} podman stop "${PODMAN_CONTAINER_NAME}" &>/dev/null
  ${PODMAN_SUDO} podman rm "${PODMAN_CONTAINER_NAME}" --force &>/dev/null
fi
#Image
if [ -z "${PODMAN_CONTAINER_IMAGE}" ]; then
 echo -e "\n[+] Setting Default Container Image: pkgforge/gh-runner-aarch64-ubuntu"
  export PODMAN_CONTAINER_IMAGE="pkgforge/gh-runner-aarch64-ubuntu"
  ${PODMAN_SUDO} podman rmi "${PODMAN_CONTAINER_IMAGE}" --force &>/dev/null
  ${PODMAN_SUDO} podman pull "${PODMAN_CONTAINER_IMAGE}"
else
 export PODMAN_CONTAINER_IMAGE="${PODMAN_CONTAINER_IMAGE}"
 echo -e "\n[+] Setting Default Container Image: ${PODMAN_CONTAINER_IMAGE}"
 ${PODMAN_SUDO} podman rmi "${PODMAN_CONTAINER_IMAGE}" --force &>/dev/null
 ${PODMAN_SUDO} podman pull "${PODMAN_CONTAINER_IMAGE}"
fi
#Env File
if [ -z "${PODMAN_ENV_FILE}" ]; then
 echo -e "\n[+] Setting Default Container Env File: ${HOME}/.config/gh-runner/.env"
  export PODMAN_ENV_FILE="${HOME}/.config/gh-runner/.env"
     if ! [[ -s "${PODMAN_ENV_FILE}" ]]; then
         echo -e "\n[-] Fatal: Empty/Non Existent ${PODMAN_ENV_FILE} file!"
       exit 1
     fi    
else
 export PODMAN_ENV_FILE="${PODMAN_ENV_FILE}"
 echo -e "\n[+] Setting Default Container Env File: ${PODMAN_ENV_FILE}"
      if ! [[ -s "${PODMAN_ENV_FILE}" ]]; then
         echo -e "\n[-] Fatal: Empty/Non Existent ${PODMAN_ENV_FILE} file!"
       exit 1
     fi 
fi
#Log File
if [ -z "${PODMAN_LOG_FILE}" ]; then
 PODMAN_LOG_FILE="$(mktemp)" && export PODMAN_LOG_FILE="${PODMAN_LOG_FILE}"
 echo -e "\n[+] Setting Default Container LOG File: ${PODMAN_LOG_FILE}"
 echo -e "[+] View Logs: tail -f ${PODMAN_LOG_FILE}\n"
else
 export PODMAN_LOG_FILE="${PODMAN_LOG_FILE}"
 echo -e "\n[+] Setting Default Container LOG File:${PODMAN_LOG_FILE}"
 echo -e "[+] View Logs: tail -f ${PODMAN_LOG_FILE}\n" 
fi
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Stop Existing
echo -e "\n[+] Cleaning PreExisting Container\n"
${PODMAN_SUDO} podman stop "$(${PODMAN_SUDO} podman ps -aqf name=${PODMAN_CONTAINER_NAME})" &>/dev/null &
wait
${PODMAN_SUDO} podman stop "$(${PODMAN_SUDO} podman ps -aqf name=${PODMAN_CONTAINER_NAME})" &>/dev/null && sleep 5
#RUN
echo -e "\n[+] Starting Runner Container (LOGFILE: ${PODMAN_LOG_FILE})\n"
${PODMAN_SUDO} mkdir -p "/var/lib/containers/tmp"
set -x && nohup ${PODMAN_SUDO} podman run --privileged --network="bridge" --systemd="always" --ulimit="host" --volume="/var/lib/containers/tmp:/tmp" --tz="UTC" --pull="always" --name="${PODMAN_CONTAINER_NAME}" --rm --env-file="${PODMAN_ENV_FILE}" "${PODMAN_CONTAINER_IMAGE}" > "${PODMAN_LOG_FILE}" 2>&1 &
set +x && echo -e "[+] Waiting 30s..." && sleep 30
#Get logs
PODMAN_ID="$(${PODMAN_SUDO} podman ps -qf name=${PODMAN_CONTAINER_NAME})" && export PODMAN_ID="${PODMAN_ID}"
PODMAN_LOGPATH="$(${PODMAN_SUDO} podman inspect --format='{{.HostConfig.LogConfig.Path}}' ${PODMAN_CONTAINER_NAME})" && export PODMAN_LOGPATH="${PODMAN_LOGPATH}"
echo -e "\n[+] Writing Logs to ${PODMAN_LOGPATH} (${PODMAN_CONTAINER_NAME} :: ${PODMAN_ID})\n"
${PODMAN_SUDO} podman exec --user "runner" --env-file="${PODMAN_ENV_FILE}" "${PODMAN_ID}" "/usr/local/bin/manager.sh" >> "${PODMAN_LOG_FILE}" 2>&1 &
set +x && echo -e "[+] Waiting 10s..." && sleep 10
#${PODMAN_SUDO} jq -r '.log' "${PODMAN_LOGPATH}""
#Monitor & Stop on Exit
set +x && echo -e "[+] Executing Runner..."
while true; do
    if ! pgrep -f "/usr/local/bin/manager.sh" > /dev/null; then
        cat "${PODMAN_LOG_FILE}"
      ${PODMAN_SUDO} podman stop "${PODMAN_ID}" --ignore
      exit 0
    fi
    sleep 5
done
#------------------------------------------------------------------------------------#
#END
popd &>/dev/null
echo -e "\n\n[+] Completed Runner ${PODMAN_CONTAINER_NAME} (LOGFILE: ${PODMAN_LOG_FILE})\n\n"
sed '/^$/d' "${PODMAN_LOG_FILE}"
echo -e "\n\n[+] Listing All Running Containers\n"
${PODMAN_SUDO} podman ps ; echo
echo -e "RUN (Remove ALL Containers): ${PODMAN_SUDO} podman ps -aq | xargs ${PODMAN_SUDO} podman stop 2>/dev/null && ${PODMAN_SUDO} podman rm \"\$(${PODMAN_SUDO} podman ps -aq)\" --force" && echo
echo -e "RUN (Remove ALL Images): ${PODMAN_SUDO} podman rmi -f \$(${PODMAN_SUDO} podman images -q) &>/dev/null" && echo
#EOF
#------------------------------------------------------------------------------------#