#-------------------------------------------------------------------------------#
##DL
# curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/.bashrc"
##Loc:
# "$HOME/.bashrc"
# "/root/.bashrc"
# "/etc/bash.bashrc"
##REF: 
# https://github.com/bluz71/dotfiles/blob/master/bashrc
# https://github.com/liskin/dotfiles/tree/home/.bashrc.d
# https://github.com/ashishb/dotfiles
# https://github.com/yorevs/homesetup/tree/master/dotfiles/bash
# https://github.com/fnichol/bashrc/blob/master/bashrc
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
#shellcheck disable=SC1090,SC1091,SC2034,SC2142,SC2148
export BASHRC_SRC_VER="v0.0.3"
##Is Interactive?
export BASH_IS_INTERACTIVE="0"
case $- in
   *i*) export BASH_IS_INTERACTIVE="1";;
esac
##Where is bash?
function _which_bash()
{
  BASH_BIN_PATH="$(realpath $(command -v bash))"
  if [[ -s "${BASH_BIN_PATH}" ]]; then
     export BASH_BIN_PATH
  else
     unset BASH_BIN_PATH
  fi
}
export -f _which_bash
_which_bash
##Is Passwordless?
if command -v sudo &>/dev/null; then
 export SUDO_CMD_PREFIX="sudo"
  if sudo -n true 2>/dev/null; then
    export PASSWORDLESS_SUDO="1"
  else
    export PASSWORDLESS_SUDO="0"
  fi
fi
##Has curl
if ! command -v curl &>/dev/null; then
   export HAS_CURL="0"
   echo "[-] WARNING: curl is not Installed (A lot of things will Break)"
else
   export HAS_CURL="1"
fi
##Is on Colab?
IS_ON_COLAB="0"
command -v colab_diagnose_me &>/dev/null && IS_ON_COLAB="1"
command -v colab-fileshim.py &>/dev/null && IS_ON_COLAB="1"
[[ -S "/tmp/colab_runtime.sock" ]] && IS_ON_COLAB="1"
export IS_ON_COLAB
##Is on WSL?
IS_ON_WSL="0"
[[ -n "${WSLENV+x}" ]] && IS_ON_WSL="1"
[[ -s "/etc/wsl.conf" ]] && IS_ON_WSL="1"
export IS_ON_WSL
##Where are we
OWD_PATH="$(realpath "." 2>/dev/null | tr -d '[:space:]')"
if [[ -d "${OWD_PATH}" ]]; then
   export OWD_PATH
else
   unset OWD_PATH
fi
##Apperance
if [[ "$(tput colors 2>/dev/null | tr -d '[:space:]')" -eq 256 ]]; then
   export TERM="xterm-256color"
fi
if command -v micro &>/dev/null; then
   EDITOR="$(realpath "$(command -v micro)" | tr -d '[:space:]')"
elif command -v nano &>/dev/null; then
   EDITOR="$(realpath "$(command -v nano)" | tr -d '[:space:]')"
fi
export EDITOR
#Colours
txtblk='\[\e[0;30m\]' # Black - Regular
txtred='\[\e[0;31m\]' # Red
txtgrn='\[\e[0;32m\]' # Green
txtylw='\[\e[0;33m\]' # Yellow
txtblu='\[\e[0;34m\]' # Blue
txtpur='\[\e[0;35m\]' # Purple
txtcyn='\[\e[0;36m\]' # Cyan
txtwht='\[\e[0;37m\]' # White
bldblk='\[\e[1;30m\]' # Black - Bold
bldred='\[\e[1;31m\]' # Red
bldgrn='\[\e[1;32m\]' # Green
bldylw='\[\e[1;33m\]' # Yellow
bldblu='\[\e[1;34m\]' # Blue
bldpur='\[\e[1;35m\]' # Purple
bldcyn='\[\e[1;36m\]' # Cyan
bldwht='\[\e[1;37m\]' # White
unkblk='\[\e[4;30m\]' # Black - Underline
undred='\[\e[4;31m\]' # Red
undgrn='\[\e[4;32m\]' # Green
undylw='\[\e[4;33m\]' # Yellow
undblu='\[\e[4;34m\]' # Blue
undpur='\[\e[4;35m\]' # Purple
undcyn='\[\e[4;36m\]' # Cyan
undwht='\[\e[4;37m\]' # White
bakblk='\[\e[40m\]'   # Black - Background
bakred='\[\e[41m\]'   # Red
badgrn='\[\e[42m\]'   # Green
bakylw='\[\e[43m\]'   # Yellow
bakblu='\[\e[44m\]'   # Blue
bakpur='\[\e[45m\]'   # Purple
bakcyn='\[\e[46m\]'   # Cyan
bakwht='\[\e[47m\]'   # White
txtrst='\[\e[0m\]'    # Text Reset
#Prompt colours
atC="${txtgrn}"
nameC="${txtgrn}"
hostC="${txtgrn}"
pathC="${txtblu}"
pointerC="${bldwht}"
normalC="${txtwht}"
#Red name for root
if [ "${UID}" -eq "0" ]; then 
  nameC="${txtred}" 
fi
#Prompt
export PS1="${nameC}\u${atC}@${hostC}\h${normalC}:${pathC}\w${pointerC}$ ${normalC}"
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##ENV VARS
if [[ -z "${USER+x}" ]] || [[ -z "${USER##*[[:space:]]}" ]]; then
 USER="$(whoami | tr -d '[:space:]')"
fi
if [[ -z "${HOME+x}" ]] || [[ -z "${HOME##*[[:space:]]}" ]]; then
 HOME="$(getent passwd "${USER}" | awk -F':' 'NF >= 6 {print $6}' | tr -d '[:space:]')"
fi
if [[ -z "${HOMETMP+x}" ]] || [[ -z "${HOMETMP##*[[:space:]]}" ]]; then
 HOMETMP="${HOME}/tmp" ; mkdir -p "${HOMETMP}"
fi
if [[ -z "${HOST_TRIPLET}" ]] || [[ -z "${HOST_TRIPLET##*[[:space:]]}" ]]; then
  _HOST_TRIPLET="$(uname -m)-$(uname -s)"
  HOST_TRIPLET="$(echo "${_HOST_TRIPLET}" | tr -d '[:space:]')"
  export HOST_TRIPLET
fi
if [[ -z "${USER_AGENT}" ]]; then
 [[ "${HAS_CURL}" == 1 ]] && USER_AGENT="$(curl -qfsSL 'https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/User-Agents/ua_chrome_macos_latest.txt')"
fi
if [[ -z "${SYSTMP+x}" ]] || [[ -z "${SYSTMP##*[[:space:]]}" ]]; then
 SYSTMP="$(dirname "$(mktemp -u)" | tr -d '[:space:]')"
fi
export USER HOME HOMETMP USER_AGENT SYSTMP
#Core
export BASH_SILENCE_DEPRECATION_WARNING="1"
export LANGUAGE="${LANGUAGE:-en_US:en}"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-${LANG}}" 2>/dev/null
export TMOUT="0"
BW_INTERFACE="$(ip route show '0/0' | grep -i 'default' | grep -oP 'dev\s+\K\S+' | head -n 1 | tr -d '"'\''[:space:]')" 
export BW_INTERFACE
current_dir="$(pwd)"
##PATHS (Only Required)
if [[ -z "${GOROOT}" && -d "${HOME}/.go" ]]; then
   export GOROOT="${HOME}/.go"
fi
if [[ -z "${GOPATH}" && -d "${HOME}/go" ]]; then
   export GOPATH="${HOME}/go"
fi
if [[ ! -d "${HOME}/bin" ]]; then
   mkdir -p "${HOME}/bin"
fi
if [[ ! -d "${HOME}/.local/bin" ]]; then
   mkdir -p "${HOME}/.local/bin"
fi
export PATH="${HOME}/.local/share/soar/bin:${HOME}/bin:${HOME}/.cargo/bin:${HOME}/.cargo/env:${HOME}/.go/bin:${HOME}/go/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${HOME}/.local/bin:${HOME}/miniconda3/bin:${HOME}/miniconda3/condabin:/usr/local/zig:/usr/local/zig/lib:/usr/local/zig/lib/include:/usr/local/musl/bin:/usr/local/musl/lib:/usr/local/musl/include:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##Aliases
if [[ -f "${HOME}/.bash_aliases" ]]; then
    . "${HOME}/.bash_aliases"
fi
alias apptainer_run='unshare -r apptainer run --allow-setuid --keep-privs --writable'
alias bashrc_version='echo "${BASHRC_SRC_VER}"'
alias bat='batcat'
alias benchmarkQ='curl -qfsSL bench.sh | bash'
alias benchmarkX='curl -qfsSL yabs.sh | bash -s -- -i'
alias cf_warp_trace='echo ; curl -qfsSL "https://1.1.1.1/cdn-cgi/trace" ; echo'
alias clean_buildenv='unset AR AS CC CFLAGS CPP CXX CPPFLAGS CXXFLAGS DLLTOOL HOST_CC HOST_CXX LD LDFLAGS LIBS NM OBJCOPY OBJDUMP RANLIB READELF SIZE STRINGS STRIP SYSROOT'
#alias df='duf'
alias dir='dir --color=auto'
alias docker_purge='docker stop $(docker ps -aq) && docker rm $(docker ps -aq) && docker rmi $(docker images -q) -f'
alias du_dir='du -h --max-depth=1 | sort -h'
alias edit_bashrc='eval "${SUDO_CMD_PREFIX}" "${EDITOR}" "$(realpath "${HOME}/.bashrc" | tr -d "[:space:]")"'
alias esort='find "." -maxdepth 1 -type f -exec sort -u "{}" -o "{}" \;'
alias egrep='egrep --color=auto'
alias fdfind='fd'
alias fgrep='fgrep --color=auto'
alias file_size='stat -c "%s" "$1" "$2" | numfmt --to="iec" --suffix="B"'
alias grep='grep --color=auto'
alias history_purge='history -c 2>/dev/null ; rm -rf "${HOME}/.bash_history"'
alias history_purge_root='sudo history -c 2>/dev/null ; sudo rm -rf "/root/.bash_history" 2>/dev/null'
alias ip_ifconfig='ip -a -d -h -p -s address'
alias ip_ifconfig_resolve='ip -a -d -h -p -r -s address'
alias ip_ifconfig_netconf='ip -a -d -h -p -s netconf'
alias ip_quality='bash <(curl -qfskSL "https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh") -l en'
alias ls='ls -lh --color=auto'
alias ls_ports='sudo netstat -lntup'
alias ls_ports_hosts='sudo lsof -i -l -R'
alias ls_ports_progs='sudo netstat -atulpen'
alias ls_ports_ip='sudo lsof -i -l -R -n'
alias list_ports_netstat='sudo netstat -atulpen'
alias list_procs='sudo ps aux'
alias max_procs='echo "$(($(nproc)+1))"'
alias max_threads='echo "$(($(nproc)+1))"'
alias miniserve_dl='miniserve --port 9977 --title "Files" --header "Miniserved: yes" --color-scheme-dark monokai --hide-theme-selector --qrcode --show-wget-footer --hide-version-footer --verbose'
alias miniserve_up='miniserve --port 9977 --title "Files" --header "Miniserved: yes" --color-scheme-dark monokai --hide-theme-selector --qrcode --show-wget-footer --hide-version-footer --upload-files --verbose'
alias my_ipv4='curl --ipv4 -qfsSL "http://ipv4.whatismyip.akamai.com" ; echo'
alias my_ipv6='curl --ipv6 -qfsSL "http://ipv6.whatismyip.akamai.com" ; echo'
alias nmap_ipv4='sudo nmap -A -p1-65535 -Pn -v --min-rate 2000 -4 $1'
alias nmap_ipv4_10k='sudo nmap -A -p1-65535 -Pn -v --min-rate 10000 -4 $1'
alias nmap_ipv6='sudo nmap -A -p1-65535 -Pn -v --min-rate 2000 -6 $1'
alias nmap_ipv6_10k='sudo nmap -A -p1-65535 -Pn -v --min-rate 10000 -6 $1'
alias podman_purge='podman stop -a && podman rm -a -f && podman rmi -a -f'
alias repology_helper='source <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/metadata/refs/heads/main/soarpkgs/scripts/repology_fetcher.sh")'
alias ssh_logs='grep -rsh "ssh" "/var/log" | grep -i "auth" | sort | less'
alias rdp_logs='grep -rsh "rdp" "/var/log" | sort | less'
alias tail_log='tail -f -n +1'
alias tmpdir='cd $(mktemp -d)'
alias tmpdir_du='du -h --max-depth="1" "/tmp" 2>/dev/null | sort -hr'
alias tmpdir_push='pushd "$(mktemp -d)" &>/dev/null'
alias tmpdir_pop='popd &>/dev/null'
alias update_bashrc='declare -F refresh_bashrc &>/dev/null && refresh_bashrc'
alias scb='xclip -selection c'
alias vdir='vdir --color=auto'
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##Completions
if [[ -f "/etc/bash_completion" ]] && ! shopt -oq posix; then
    . "/etc/bash_completion"
fi
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
###Functions
##Archive to 7z
function 7z_archive()
{
  7z a -t7z -mx="9" -mmt="$(($(nproc)+1))" -bsp1 -bt "$1" "$2"
}
export -f 7z_archive
##Install Soar
function install_soar()
{
  if [[ ! -d "${HOME}/bin" ]]; then
   mkdir -p "${HOME}/bin"
  fi
  [[ "${HAS_CURL}" == 1 ]] && bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/soar/refs/heads/main/install.sh")
  command -v soar &>/dev/null || return 1
  if [[ ! -s "${HOME}/.config/soar/config.toml" ]]; then
     soar defconfig --external
  fi
  soar sync
}
export -f install_soar
##Decode base64
function decode_base64()
{
  if [[ -f "$1" ]]; then
    base64 -d "$1"
  else
    echo "${1:-$(cat)}" | base64 -d
  fi
}
export -f decode_base64
##Disable fzf
function disable_fzf()
{
  unset "$(set | grep -o '^_fzf[^=]*' | tr '\n' ' ')" 2>/dev/null
  unset "$(set | grep -o '^__fzf[^=]*' | tr '\n' ' ')" 2>/dev/null
  unset "$(declare -F | grep -o '_fzf[^ ]*' | tr '\n' ' ')" 2>/dev/null
  unset -f "$(declare -F | grep -o '_fzf[^ ]*' | tr '\n' ' ')" 2>/dev/null
  unset "$(declare -F | grep -o '__fzf[^ ]*' | tr '\n' ' ')" 2>/dev/null
  unset -f "$(declare -F | grep -o '__fzf[^ ]*' | tr '\n' ' ')" 2>/dev/null
  bind '"\C-r": reverse-search-history'
  bind '"\t": complete'
  if [[ -f "/etc/inputrc" ]]; then
     bind -f "/etc/inputrc"
  fi
}
export -f disable_fzf
##Encode to base64
function encode_base64()
{
  if [[ -f "$1" ]]; then
    base64 -w0 "$1"
  else  
    echo "${1:-$(cat)}" | base64 -w0
  fi
}
export -f encode_base64
##Fix jsonl
function fix_validate_jsonl()
{
  if ! awk --version 2>&1 | grep -qi "busybox"; then
    if [[ -f "$1" ]]; then
      awk '/^\s*{\s*$/ {flag=1;buffer="{\n";next} /^\s*}\s*$/ {if(flag){print buffer"}\n"};flag=0;next} flag{buffer=buffer$0"\n"} /^\{.*\}$/ {print $0"\n"}' "$1"
    else  
      echo "${1:-$(cat)}" | awk '/^\s*{\s*$/ {flag=1;buffer="{\n";next} /^\s*}\s*$/ {if(flag){print buffer"}\n"};flag=0;next} flag{buffer=buffer$0"\n"} /^\{.*\}$/ {print $0"\n"}'
    fi
  else
    echo "BusyBox awk Detected, Install GnuAWK(gawk)"
  fi
}
export -f fix_validate_jsonl
##Generate Random String
function gen_random_string()
{
  local R_LIMIT="${1:-32}"
  local X="X"
  local T_IN_T=$(printf '%s' "${X}$(printf '%.0sX' $(seq 1 "${R_LIMIT}"))")
  local T_IN="$(echo "${T_IN_T}" | head -c 251 | tr -d '[:space:]')"
  local T_OUT=$(mktemp -u "${T_IN}XXXX")
  echo "${T_OUT}" | tr -d "[:space:]" | head -c "${R_LIMIT}"
}
export -f gen_random_string
##Generate Random string with date
function gen_random_string_date()
{
  echo "$(gen_random_string ${1:-2})-$(date --utc +'%Y-%m-%dT%H-%M-%SZ%2N_%p_UTC')" | tr -d '[:space:]'
}
export -f gen_random_string_date
##Initialize fzf
function init_fzf()
{
  if [[ "$(command -v bat)" && "$(command -v fd)" && "$(command -v fzf)" && "$(command -v tree)" ]]; then
     export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
     #export FZF_DEFAULT_OPTS='--no-height --color=bg+:#343d46,gutter:-1,pointer:#ff3c3c,info:#0dbc79,hl:#0dbc79,hl+:#23d18b'
     export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND}"
     export FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :50 {}'"
     export FZF_ALT_C_COMMAND='fd --type d "." --hidden --exclude .git'
     export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -50'"
     eval "$(fzf --bash)"
  fi
}
export -f init_fzf
##Reinstall soar
function install_soar_force()
{
  if [[ ! -d "${HOME}/bin" ]]; then
     mkdir -p "${HOME}/bin"
  fi
  if [[ ! -d "${HOME}/.local/bin" ]]; then
     mkdir -p "${HOME}/.local/bin"
  fi
  rm -rvf "${HOME}/.config/soar" "${HOME}/.local/share/soar" 2>/dev/null
  [[ "${HAS_CURL}" == 1 ]] && bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/soar/refs/heads/main/install.sh")
  command -v soar &>/dev/null || return 1
  soar defconfig --external
  soar sync
}
export -f install_soar_force
##Cleanup using Nix
function nixbuild_cleanup() 
{
  nix-collect-garbage
  nix-store --gc
}
export -f nixbuild_cleanup
##Print PKGINFO using nix
function nixbuild_info()
{
  echo -e "\n"
  nix-instantiate --eval --expr "builtins.toJSON (with import <nixpkgs> {}; $1.meta)" --quiet 2>/dev/null | jq -r fromjson 2>/dev/null
  echo -e "\n"
}
export -f nixbuild_info
##Statically Build using nix
function nixbuild_static()
{
  nix-build '<nixpkgs>' --impure --attr "pkgsStatic.$1" --cores "$(($(nproc)+1))" --max-jobs "$(($(nproc)+1))" --log-format bar-with-logs --out-link "./NIX_BUILD"
}
export -f nixbuild_static
##Pack files with upx + remove upx headers + wrappe
function pack_exe()
{
  if [[ "$(command -v awk)" &&\
        "$(command -v file)" &&\
        "$(command -v grep)" &&\
        "$(command -v sed)" &&\
        "$(command -v strip)" &&\
        "$(command -v upx)" &&\
        "$(command -v wrappe)" ]]; then
    if [[ -f "$1" ]]; then
      local input="$(realpath $1 | tr -d '[:space:]')"
      local p_name="$(basename ${input})"
      local c_wd="$(realpath .)"
      rm -fv "${input}.upx" "${input}.st" "${input}.wp" 2>/dev/null
      chmod 'a+x' "${input}"
      upx --best --ultra-brute "${input}" -f --force-overwrite -o"${input}.upx"
     #Remove Headers
       if command -v perl &>/dev/null; then
         #NO_SSTRIP=1 --> Don't use sstrip
         #NO_ADD_SECTION=1 --> Don't try to insert a null header
         "${BASH_BIN_PATH}" <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/remove_upx_info.sh") "${input}.upx"
         if [[ -s "${input}.upx.st" ]] && [[ $(stat -c%s "${input}.upx.st") -gt 3 ]]; then
           mv -fv "${input}.upx.st" "${input}.st"
         fi
         if upx -d "${input}.st" --force-overwrite -o"/dev/null" 2>&1 | grep -qi "not[[:space:]]*packed"; then
           echo "[+] ${input} ==> ${input}.upx (UPXed) ==> ${input}.st (UPXed + Stealth)"
         else
           echo "[-] Removal of UPX Headers likely Failed"
         fi
       fi
     #Pack as WRAPPE
      if command -v wrappe &>/dev/null; then
        pushd "$(mktemp -d)" &>/dev/null &&\
          cp "${input}" "./${p_name}" &&\
          wrappe --current-dir "command" --compression "22" --show-information "none" --unpack-directory ".${p_name}" --unpack-target "local" --cleanup "." "./${p_name}" "${input}.wp"
        popd &>/dev/null && cd "${c_wd}"
        echo "[+] ${input} ==> ${input}.wp (Wrappe ZSTD 22)"
      fi  
     #Print Info
      cd "${c_wd}" && file "${input}" && du -b "${input}"
      [[ -s "${input}.upx" ]] && file "${input}.upx" && du -b "${input}.upx"
      [[ -s "${input}.st" ]] && file "${input}.st" && du -b "${input}.st"
      [[ -s "${input}.wp" ]] && file "${input}.wp" && du -b "${input}.wp"
    else
      echo "[-] Directly Specify a File"
    fi
  else
     echo "[-] Install: awk file grep sed strip upx wrappe"
  fi
}
export -f pack_exe
##Source the bashrc file & reload env
function refreshenv()
{
  hash -r &>/dev/null
  local BASHRC_FILE="$(realpath "${HOME}/.bashrc" | tr -d '[:space:]')"
  if [[ -f "${BASHRC_FILE}" ]]; then
   source "${BASHRC_FILE}"
   if command -v sed &>/dev/null; then
     sed -n '/^\s*export\s\+BASHRC_SRC_VER=/s/^\s*export\s\+//p' "${BASHRC_FILE}"
   elif command -v grep &>/dev/null; then
     grep -oP '^\s*export\s+\K(BASHRC_SRC_VER="[^"]+")' "${BASHRC_FILE}"
   fi
  fi
}
export -f refreshenv
##Pull new bashrc from remote & resource
function refresh_bashrc()
{
  local BASHRC_SRC_URL_TMP="https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/.bashrc?$(gen_random_string_date || mktemp -u)=$(gen_random_string_date || mktemp -u)"
  local BASHRC_SRC_URL="$(echo "${BASHRC_SRC_URL_TMP}" | tr -d '[:space:]')"
  if [[ "${PASSWORDLESS_SUDO}" == 1 ]]; then
   if [[ "${HAS_CURL}" == 1 ]]; then
     sudo curl -qfsSL "${BASHRC_SRC_URL}" -H "Cache-Control: no-cache" -H "Pragma: no-cache" -H "Expires: 0" -o "/etc/bash.bashrc" &&\
     curl -qfsSL "${BASHRC_SRC_URL}" -w "(SRC) <== %{url}\n" -I
     if [[ -f "/etc/bash.bashrc" ]]; then
       sudo ln -fs "/etc/bash.bashrc" "/root/.bashrc" 2>/dev/null
       sudo ln -fs "/etc/bash.bashrc" "${HOME}/.bashrc" 2>/dev/null
       sudo ln -fs "/etc/bash.bashrc" "/etc/bash/bashrc" 2>/dev/null
     fi
   fi
  elif [[ -w "${HOME}" ]]; then
   if [[ "${HAS_CURL}" == 1 ]]; then
     curl -qfsSL "${BASHRC_SRC_URL}" -H "Cache-Control: no-cache" -H "Pragma: no-cache" -H "Expires: 0" -o "${HOME}/.bashrc" &&\
     curl -qfsSL "${BASHRC_SRC_URL}" -w "(SRC) <== %{url}\n" -I
   fi
  fi
  refreshenv
}
export -f refresh_bashrc
##Setup fzf
function setup_fzf()
{
  if [[ -d "${HOME}/.local/bin" ]] && [[ -w "${HOME}/.local/bin" ]]; then
    if [[ "${HAS_CURL}" == 1 ]]; then
      curl -w "(DL) <== %{url}\n" -qfsSL "https://bin.pkgforge.dev/${HOST_TRIPLET}/bat" -o "${HOME}/.local/bin/bat"
      curl -w "(DL) <== %{url}\n" -qfsSL "https://bin.pkgforge.dev/${HOST_TRIPLET}/fd" -o "${HOME}/.local/bin/fd"
      curl -w "(DL) <== %{url}\n" -qfsSL "https://bin.pkgforge.dev/${HOST_TRIPLET}/fzf" -o "${HOME}/.local/bin/fzf"
      curl -w "(DL) <== %{url}\n" -qfsSL "https://bin.pkgforge.dev/${HOST_TRIPLET}/tree" -o "${HOME}/.local/bin/tree"
      chmod 'a+x' "${HOME}/.local/bin/bat" "${HOME}/.local/bin/fd" "${HOME}/.local/bin/fzf" "${HOME}/.local/bin/tree"
      init_fzf && fzf --version && fzf
    fi
  fi
}
export -f setup_fzf
##Strip ELF
function strip_debug()
{
  objcopy --remove-section=".comment" --remove-section=".note.*" "$1" 2>/dev/null
  strip --strip-debug --strip-dwo --strip-unneeded "$1" 2>/dev/null
}
export -f strip_debug
##Strip space from each line
function strip_space_stdin()
{
  if [[ -f "$1" ]]; then
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$1"
  else  
    echo "${1:-$(cat)}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
  fi
}
export -f strip_space_stdin
##Strip space from stdin for single input
function strip_space_tr()
{
  echo "${1:-$(cat)}" | tr -d '"'\''[:space:]'
}
export -f strip_space_tr
##Decode URL encoded string
function url_decode_py()
{
  if command -v python &>/dev/null; then
    echo "${1:-$(cat)}" | python -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))'
  elif command -v python3 &>/dev/null; then
    echo "${1:-$(cat)}" | python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))'
  fi
}
export -f url_decode_py
##URL encode string
function url_encode_jq()
{
  echo "${1:-$(cat)}" | jq -sRr '@uri' | tr -d '[:space:]'
}
export -f url_encode_jq
##zapper path
function _zap_get_self()
{
  if [[ -z "${_ZAP_BIN_PATH+x}" ]] || [[ -z "${_ZAP_BIN_PATH##*[[:space:]]}" ]]; then
    if command -v zapper-stealth &>/dev/null; then
       _ZAP_BIN_PATH="$(realpath $(command -v zapper))"
    elif command -v zapper &>/dev/null; then
       _ZAP_BIN_PATH="$(realpath $(command -v zapper))"
    fi
  fi
  if [[ -n "${_ZAP_BIN_PATH+x}" ]] && [[ -s "${_ZAP_BIN_PATH}" ]]; then
    if [[ ! -x "${_ZAP_BIN_PATH}" ]]; then
       chmod '+x' "${_ZAP_BIN_PATH}" &>/dev/null
    fi
    if [[ -x "${_ZAP_BIN_PATH}" ]]; then
       _Z_BPATH="${_ZAP_BIN_PATH}"
    fi
    unset _ZAP_BIN_PATH
  fi
}
export -f _zap_get_self
##Zap Proc name & Env
# _zap_proc "${PROCESS_NAME}" "${CMD_NAME}" "${CMD_ARGS}" #otherwise chosen at random
function _zap_proc()
{
  _zap_get_self &>/dev/null
  [[ ! -s "${BASH_BIN_PATH}" ]] && _which_bash &>/dev/null
  if [[ -n "${_Z_BPATH+x}" ]] && [[ -s "${_Z_BPATH}" ]]; then
    if declare -F "$1" &>/dev/null; then
       func_name="$1"
       local -f "${func_name}"
       unset p_name
    elif declare -F "$2" &>/dev/null; then
       func_name="$2"
       local -f "${func_name}"
       local p_name="${1:-}"
    else
       local p_name="${1:-}"
    fi
    shift
     if [[ -z "${p_name+x}" ]] || [[ -z "${p_name##*[[:space:]]}" ]]; then
       p_name_kw=("[kworker/1:2-cgroup_destroy]" "[rcu_tasks_rude_kthread_max]" "[rcu_tasks_rude_kthread_min]" "[rcu_tasks_trace_kthread_max]" "[rcu_tasks_trace_kthread_min]" "[kworker/1:1]" "[kworker/2:2]")
       p_name_systemd=("/usr/lib/systemd/systemd-hibernate-resume-idle" "/usr/lib/systemd/systemd-boot-check-no-reset" "/usr/lib/systemd/systemd-modules-load-fs" "/usr/lib/systemd/systemd-networkd-resume-online")
       p_name_dbus=("/usr/bin/dbus-broker --log 2" "/usr/bin/dbus-broker-launch" "/usr/bin/dbus-cleanup-sockets" "/usr/sbin/cups-browsed")
       if command -v ps &>/dev/null && command -v grep &>/dev/null; then
          if [[ "$(ps aux 2>/dev/null | grep -i 'systemd-' | wc -l)" -gt 3 ]]; then
            local p_name="${p_name_systemd[$((RANDOM % ${#p_name_systemd[@]}))]}"
          elif [[ "$(ps aux 2>/dev/null | grep -Ei '\[kworker|\[rcu_' | wc -l)" -gt 3 ]]; then
            local p_name="${p_name_kw[$((RANDOM % ${#p_name_kw[@]}))]}"
          else
            local p_name="${p_name_dbus[$((RANDOM % ${#p_name_dbus[@]}))]}"
          fi
       else
          local p_name="${p_name_dbus[$((RANDOM % ${#p_name_dbus[@]}))]}"
       fi
     fi
     unset stdin_args ; read -t 0 && read -ra stdin_args
     if [[ -n "${func_name+x}" ]]; then
       local cmd_str_tmp="${func_name} $*"
       [[ ${#stdin_args[@]} -gt 0 ]] && cmd_str_tmp+=" ${stdin_args[*]}"
       cmd_str="$(echo "${cmd_str_tmp}" | awk '{for(i=1;i<=NF;i++)if(!(a[$i]++)||system("[ -f \""$i"\" ]")==0)printf $i" ";print""}')"
       export cmd_str
       zap_proc=("${_Z_BPATH}" -f -a "${p_name}" "${BASH_BIN_PATH}" -c "${cmd_str}")
     else
       zap_proc=("${_Z_BPATH}" -f -a "${p_name}" "$@" "${stdin_args[@]}")
     fi
     "${zap_proc[@]}"
     unset cmd_str cmd_str_tmp func_name stdin_args zap_proc _Z_BPATH
  fi
}
export -f _zap_proc
##Zap the shell itself with a process
# _zap_self_proc "${PROCESS_NAME}" #otherwise no name at all
function _zap_self_proc()
{
  unset p_name zap_self _Z_BPATH
  _zap_get_self &>/dev/null
  if [[ -n "${_Z_BPATH+x}" ]] && [[ -s "${_Z_BPATH}" ]]; then
     local p_name="${1:-}"
     shift
     if [[ -n "${p_name+x}" ]] && [[ "${p_name}" =~ ^[^[:space:]]+$ ]]; then
       zap_self=(exec "${_Z_BPATH}" -f -a "${p_name}" "$@")
     else
       zap_self=(exec "${_Z_BPATH}" -f -a- "$@")
     fi
     "${zap_self[@]}" &>/dev/null
     unset p_name zap_self _Z_BPATH
  fi
}
export -f _zap_self_proc
##Zap the shell itself with bash -il
# _zap_self_bash "${PROCESS_NAME}" #otherwise no name at all
function _zap_self_bash()
{
  _zap_self_proc "${BASH_BIN_PATH}" &>/dev/null
  [[ ! -s "${BASH_BIN_PATH}" ]] && _which_bash &>/dev/null
  if [[ -n "${_Z_BPATH+x}" ]] && [[ -s "${_Z_BPATH}" ]]; then
    if [[ -n "${BASH_BIN_PATH+x}" ]] && [[ -s "${BASH_BIN_PATH}" ]]; then
     local p_name="${1:-}"
     shift
     if [[ -n "${p_name+x}" ]] && [[ "${p_name}" =~ ^[^[:space:]]+$ ]]; then
       _zap_self_proc "${p_name}" "${BASH_BIN_PATH}" -il
     else
       _zap_self_proc "${BASH_BIN_PATH}" -il
     fi
    fi
  fi
}
export -f _zap_self_bash
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##GIT
if [[ "${BASH_IS_INTERACTIVE}" == 0 ]]; then
   export GH_PAGER=""
   export GIT_TERMINAL_PROMPT="0"
   export GIT_ASKPASS="/bin/echo"
fi
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##Misc
#don't put duplicate lines or lines starting with space in the history.
export HISTCONTROL=ignoreboth:erasedups
#History Size
export HISTSIZE=999999
export HISTFILESIZE=9999999
#append to the history file, don't overwrite it
shopt -s histappend
#Setting history format: Index [<User>, <Date> <Time>] command
export HISTTIMEFORMAT="[${USER}, %F %T]  "
#Check the window size after each command and, if necessary,
#update the values of LINES and COLUMNS.
shopt -s checkwinsize
#Turn on ../**/*.ext Globs
shopt -q -s extglob
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##Nix
if [[ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]]; then
   source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" &>/dev/null
   if command -v nix &>/dev/null; then
     export NIXPKGS_ALLOW_BROKEN="1"
     export NIXPKGS_ALLOW_UNFREE="1"
     export NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM="1"
   fi
fi
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##Dedupe & Fix Path
if command -v awk &>/dev/null && command -v sed &>/dev/null; then
 PATH="$(echo "${PATH}" | awk 'BEGIN{RS=":";ORS=":"}{gsub(/\n/,"");if(!a[$0]++)print}' | sed 's/:*$//')"
fi
export PATH
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##FZF
if [[ "${NO_FZF}" != 1 ]]; then
  if [[ "${PASSWORDLESS_SUDO}" == 1 ]]; then
    if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
      sudo ln -s "$(realpath "$(command -v batcat)")" "${HOME}/.local/bin/bat"
    fi
    if command -v fd-find &>/dev/null && ! command -v fd &>/dev/null; then
      sudo ln -s "$(realpath "$(command -v fd-find)")" "${HOME}/.local/bin/fd"
    fi
  fi
  if [[ "$(command -v bat)" && "$(command -v fd)" && "$(command -v fzf)" && "$(command -v tree)" ]]; then
     init_fzf
  fi
elif [[ "${NO_FZF}" == 1 ]]; then
   disable_fzf &>/dev/null
fi
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##CWD
#Change to safe dir
if [[ -z "${OWD_PATH+x}" ]] || [[ -z "${OWD_PATH##*[[:space:]]}" ]]; then
  if [[ -d "${HOME}" ]]; then
   cd "${HOME}" && OWD_PATH="$(realpath "." | tr -d '[:space:]')"
   export OWD_PATH
  else
   cd "$(mktemp -d)" && OWD_PATH="$(realpath "." | tr -d '[:space:]')"
   export OWD_PATH
  fi
fi
if [[ "${OWD_PATH}" == */mnt/c/Users/* && "${IS_ON_WSL}" == "1" ]]; then
  if [[ -d "${HOMETMP}" ]]; then
     cd "${HOMETMP}"
  elif [[ -d "${SYSTMP}" ]]; then
     cd "${SYSTMP}"
  fi
elif [[ "${OWD_PATH}" == "/" || $(stat -c '%u' "${OWD_PATH}") -eq 0 ]]; then
  if [[ -d "${HOME}" ]]; then
     cd "${HOME}"
  elif [[ -d "${SYSTMP}" ]]; then
     cd "${SYSTMP}"
  fi
fi
#-------------------------------------------------------------------------------#
