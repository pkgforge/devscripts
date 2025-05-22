#!/usr/bin/env bash

#-------------------------------------------------------#
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Install & Setup: https://github.com/stal-ix/ix
## use GIT_REPO="https://github.com/pg83/ix" for edge
###-----------------------------------------------------###

#-------------------------------------------------------#
##Enable Debug?
 if [[ "${DEBUG}" = "1" ]] || [[ "${DEBUG}" = "ON" ]]; then
   set -x
 fi
##SYSTMP
 if [[ -z "${SYSTMP+x}" ]] || [[ -z "${SYSTMP##*[[:space:]]}" ]]; then
   SYSTMP="$(dirname "$(mktemp -u)" | tr -d '[:space:]')"
   [[ ! -d "${SYSTMP}" ]] && mkdir -p "${SYSTMP}"
   export SYSTMP
 fi
 mkdir -p "${SYSTMP}/emtpy"
##Track Time 
 echo -e "\n==> [+] Started Initiating at :: $(TZ='UTC' date +'%A, %Y-%m-%d (%I:%M:%S %p)') UTC\n"
 START_TIME="$(date '+%s')"
 export START_TIME
#-------------------------------------------------------#

#-------------------------------------------------------#
##Setup Deps
 if [[ "$(id -u)" -ne 0 ]]; then
  echo -e "\n[✗] FATAL: This must be run as ROOT\n"
  exit 1
 fi
 if command -v apk &>/dev/null; then
   apk update ; apk upgrade --no-interactive 2>/dev/null
   apk add 7zip bash binutils build-base coreutils fakeroot findutils file g++ gcompat git grep \
     jq libc-dev linux-headers lld llvm moreutils parted python3 rsync sudo tar tree util-linux xz zstd --latest --upgrade --no-interactive 2>/dev/null
 elif command -v apt &>/dev/null; then
   export DEBIAN_FRONTEND="noninteractive"
   apt update -y -qq ; apt upgrade -y -qq
   apt install bash binutils build-essential coreutils curl findutils file g++ git grep jq libc-dev \
     moreutils patchelf python3 rsync sed sudo strace tar tree xz-utils zstd -y -qq 2>/dev/null
 fi
##Check
 yes "y" | sudo bash -c "whoami" &>/dev/null
 hash -r &>/dev/null
 for DEP_CMD in find g++ rsync sudo tar xz; do
    case "$(command -v "${DEP_CMD}" 2>/dev/null)" in
        "") echo -e "\n[✗] FATAL: ${DEP_CMD} is NOT INSTALLED\n"
           exit 1 ;;
    esac
 done
#-------------------------------------------------------#

#-------------------------------------------------------#
##Setup ENV
 if [[ -z "${USER+x}" ]] || [[ -z "${USER##*[[:space:]]}" ]]; then
  USER="$(whoami 2>/dev/null | tr -d '[:space:]')"
 fi
 if [[ -z "${HOME+x}" ]] || [[ -z "${HOME##*[[:space:]]}" ]]; then
  HOME="$(getent passwd "${USER}" 2>/dev/null | awk -F':' 'NF >= 6 {print $6}' | tr -d '[:space:]')"
 fi
 export USER HOME
 if [[ ! -d "${HOME}" ]]; then
  mkdir -p "${HOME}"
 fi
#-------------------------------------------------------#

#-------------------------------------------------------#
##Install: https://stal-ix.github.io/IX.html
#        : https://stal-ix.github.io/IX_standalone
 if [[ -d "${HOME}" ]]; then
    pushd "${HOME}" &>/dev/null && \
    sudo rm -rvf "/ix" 2>/dev/null
    rm -rvf "${HOME}/ix" 2>/dev/null
    git clone --depth="1" --filter="blob:none" --quiet "${GIT_REPO:-https://github.com/stal-ix/ix}"
    if [[ -d "${HOME}/ix" ]] && [[ "$(du -s "${HOME}/ix" | cut -f1)" -gt 10 ]]; then
       if [[ -s "${HOME}/ix/ix" ]]; then
         chmod 'a+x' "${HOME}/ix/ix"
         echo '#!/usr/bin/env bash' | sudo tee "/usr/local/bin/ix"
         echo -e "\nc_wd=\"\$(realpath .)\"" | sudo tee -a "/usr/local/bin/ix"
         echo -e "export PATH=\"\${PATH}:/ix/realm/boot/bin\"" | sudo tee -a "/usr/local/bin/ix"
         echo "cd ~/ix && \\" | sudo tee -a "/usr/local/bin/ix"
         echo "sudo --non-interactive \"$(realpath ${HOME}/ix/ix)\" \$@" | sudo tee -a "/usr/local/bin/ix"
         echo "cd \"\${c_wd}\"" | sudo tee -a "/usr/local/bin/ix"
         sudo chmod '+x' "/usr/local/bin/ix"
       else
         echo -e "\n[✗] FATAL: '${HOME}/ix/ix' does NOT exist\n"
         exit 1
       fi
    else
      echo -e "\n[✗] FATAL: '${HOME}/ix' does NOT exist\n"
      exit 1
    fi
    hash -r &>/dev/null
 else
   echo -e "\n[✗] FATAL: '\${HOME}' does NOT exist\n"
   exit 1
 fi
#-------------------------------------------------------#

#-------------------------------------------------------#
##Setup  
 if command -v ix &>/dev/null; then
   pushd "${HOME}/ix" &>/dev/null
   (
     while true; do
       if [[ -d "/ix/trash" ]]; then
         echo -e "\n[BG] Purging '/ix/trash'"
         du -sh "/ix/trash" 2>/dev/null ; echo -e "\n"
         find "/ix/trash" -mindepth 1 -delete &>/dev/null
       fi
       sleep 120
     done
   ) &
   bg_pid=$!
   ix mut "bin/ix"
   #echo -e "\n" && ix gc lnk url
   #Check Dir Size
    if [[ -d "/ix" ]] && [[ "$(du -s "/ix" | cut -f1)" -gt 1000 ]]; then
      du -sh "/ix"
    else
      echo -e "\n[✗] FATAL: '/ix' is probably Broken\n"
      exit 1
    fi
   #Install a dummy pkg & Check
    ix run "bin/nano" -- nano --version ||\
     {
      echo -e "\n[✗] FATAL: 'ix' is probably Broken\n" ; exit 1
     }
 else
   echo -e "\n[✗] FATAL: 'ix' is NOT Installed\n"
   exit 1
 fi
#-------------------------------------------------------#

#-------------------------------------------------------#
##Cleanup
 sudo kill -9 "${bg_pid}" 2>/dev/null
 if [[ -d "/ix/trash" ]]; then
   echo -e "\n[BG] Purging '/ix/trash'\n"
   find "/ix/trash" -mindepth 1 -delete &>/dev/null
 fi
##Calc Time
 END_TIME="$(date '+%s')"
 ELAPSED_TIME="$(date -u -d@"$((END_TIME - START_TIME))" "+%H(Hr):%M(Min):%S(Sec)")"
 echo -e "\n[+] Completed Initiating Stal/IX :: ${ELAPSED_TIME}"
 echo -e "==> [+] Finished Initiating at :: $(TZ='UTC' date +'%A, %Y-%m-%d (%I:%M:%S %p)') UTC\n"
##Denote Status
 echo "INITIALIZED" > "${SYSTMP}/INITIALIZED"
##Disable Debug? 
 if [[ "${DEBUG}" = "1" ]] || [[ "${DEBUG}" = "ON" ]]; then
   set -x
 fi
#-------------------------------------------------------#