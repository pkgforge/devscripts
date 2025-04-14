#!/usr/bin/env bash
#
# REQUIRES: coreutils + perl
# OUTPUT: ${input}.st
# source <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/remove_upx_info.sh")
#set -x
#-------------------------------------------------------#

#-------------------------------------------------------#
##Main
purge_upxh()
{
  ##Enable Debug 
   if [ "${DEBUG}" = "1" ] || [ "${DEBUG}" = "ON" ]; then
      set -x
   fi
  #ENV
   if [[ -z "${SYSTMP+x}" ]] || [[ -z "${SYSTMP##*[[:space:]]}" ]]; then
     SYSTMP="$(dirname "$(mktemp -u)" | tr -d '[:space:]')"
     local SYSTMP="${SYSTMP}"
   fi
   input="$(realpath $1 | tr -d '[:space:]')" ; local input="${input}"
   p_name="$(basename ${input})" ; local p_name="${p_name}"
   c_wd="$(realpath .)" ; local c_wd="${c_wd}"
   input_tmp="${input}.upxtmp" ; local input_tmp="${input_tmp}"
   BIN="${input_tmp}" ; local BIN="${BIN}"
   output="${input}.st" ; local output="${output}"
   rm -f "${BIN}.tmpupx" "${input}.st" "${input}.upxtmp" 2>/dev/null
   cp -f "${input}" "${BIN}"
  #Strip
   if command -v perl &>/dev/null; then
    if [[ -s "${BIN}" ]] && [[ $(stat -c%s "${BIN}") -gt 3 ]]; then
     #Remove Headers: https://github.com/hackerschoice/thc-tips-tricks-hacks-cheat-sheet?tab=readme-ov-file
      echo -e "\n[+] Removing UPX Headers (perl) ${input} <==> ${BIN}"
      perl -i -0777 -pe 's/^(.{64})(.{0,256})UPX!.{4}/$1$2\0\0\0\0\0\0\0\0/s' "${BIN}"
      perl -i -0777 -pe 's/^(.{64})(.{0,256})\x7fELF/$1$2\0\0\0\0/s' "${BIN}"
      cat "${BIN}" \
      | perl -e 'local($/);$_=<>;s/(.*)(\$Info:[^\0]*)(.*)/print "$1";print "\0"x length($2); print "$3"/es;' \
      | perl -e 'local($/);$_=<>;s/(.*)(\$Id:[^\0]*)(.*)/print "$1";print "\0"x length($2); print "$3"/es;' >"${BIN}.tmpupx"
      mv "${BIN}.tmpupx" "${BIN}"
      grep -Eqm1 "PROT_EXEC\|PROT_WRITE" "${BIN}" \
      && cat "${BIN}" | perl -e 'local($/);$_=<>;s/(.*)(PROT_EXEC\|PROT_WRI[^\0]*)(.*)/print "$1";print "\0"x length($2); print "$3"/es;' >"${BIN}.tmpupx" \
      && mv "${BIN}.tmpupx" "${BIN}"
      perl -i -0777 -pe 's/UPX!/\0\0\0\0/sg' "${BIN}"
      #sstrip
       if [[ "${NO_SSTRIP}" != "1" ]]; then
         if ! command -v sstrip &>/dev/null && ! [[ -x "${SYSTMP}/.tmpbin/sstrip" ]]; then
           mkdir -p "${SYSTMP}/.tmpbin"
           curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)-$(uname -s)/sstrip" -o "${SYSTMP}/.tmpbin/sstrip" &&\
           chmod "a+x" "${SYSTMP}/.tmpbin/sstrip" &&\
           local PATH="${SYSTMP}/.tmpbin:${PATH}"
         fi
         if command -v sstrip &>/dev/null; then
           echo "[+] Stripping (sstripping) ==> ${BIN}"
           sstrip --zeroes "${BIN}"
         fi
       fi
      #add-sections
       if [[ "${NO_ADD_SECTION}" != "1" ]]; then
         if ! command -v add-section &>/dev/null && ! [[ -x "${SYSTMP}/.tmpbin/add-section" ]]; then
           mkdir -p "${SYSTMP}/.tmpbin"
           curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)-$(uname -s)/add-section" -o "${SYSTMP}/.tmpbin/add-section" &&\
           chmod "a+x" "${SYSTMP}/.tmpbin/add-section" &&\
           local PATH="${SYSTMP}/.tmpbin:${PATH}"
         fi
         if command -v add-section &>/dev/null; then
           echo "[+] Adding NULL Header (add-section) ==> ${BIN}"
           mkdir -p "${SYSTMP}/.tmpbin"
           cd "${SYSTMP}/.tmpbin" &&\
           add-section --input "${BIN}" --output "${BIN}.tmp" &&\
           mv -f "${BIN}.tmp" "${BIN}"
           cd "${c_wd}"
         fi
       fi
     #Move final executable 
      mv -f "${BIN}" "${output}" && rm -f "${BIN}.tmpupx" "${input}.upxtmp" 2>/dev/null
      if [[ ! -s "${output}" ]] || [[ $(stat -c%s "${output}") -lt 3 ]]; then
        echo "[-] FATAL: Output file (${output}) is probably corrupted"
      else
        echo -e "[+] ${input} [$(stat -c'%s' ${input})] ==> ${output} [$(stat -c'%s' ${output})]\n"
      fi
    fi
   else
     echo "[-] FATAL: Requires perl"
   fi
  ##Cleanup 
   [[ -d "${SYSTMP}/.tmpbin" ]] && rm -rf "${SYSTMP}/.tmpbin" 2>/dev/null
   cd "${c_wd}"
  ##Disable Debug 
   if [ "${DEBUG}" = "1" ] || [ "${DEBUG}" = "ON" ]; then
      set +x
   fi
  }
export -f purge_upxh
#Call func directly if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
   purge_upxh "$@" <&0
fi
#-------------------------------------------------------#
