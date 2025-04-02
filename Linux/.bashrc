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
##Is Interactive?
export BASH_IS_INTERACTIVE="0"
case $- in
   *i*) export BASH_IS_INTERACTIVE="1";;
esac
##Is Passwordless?
if sudo -n true 2>/dev/null; then
  export PASSWORDLESS_SUDO="1"
else
  export PASSWORDLESS_SUDO="0"
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
if [[ -z "${USER_AGENT}" ]]; then
  USER_AGENT="$(curl -qfsSL 'https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/User-Agents/ua_chrome_macos_latest.txt')"
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
alias bat='batcat'
alias benchmarkQ='curl -qfsSL bench.sh | bash'
alias benchmarkX='curl -qfsSL yabs.sh | bash -s -- -i'
alias cf_warp_trace='echo ; curl -qfsSL "https://1.1.1.1/cdn-cgi/trace" ; echo'
alias clean_buildenv='unset AR AS CC CFLAGS CPP CXX CPPFLAGS CXXFLAGS DLLTOOL HOST_CC HOST_CXX LD LDFLAGS LIBS NM OBJCOPY OBJDUMP RANLIB READELF SIZE STRINGS STRIP SYSROOT'
#alias df='duf'
alias dir='dir --color=auto'
alias docker_purge='docker stop $(docker ps -aq) && docker rm $(docker ps -aq) && docker rmi $(docker images -q) -f'
alias du_dir='du -h --max-depth=1 | sort -h'
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
##Functions
function 7z_archive()
{
  7z a -t7z -mx="9" -mmt="$(($(nproc)+1))" -bsp1 -bt "$1" "$2"
}
export -f 7z_archive
function install_soar()
{
  if [[ ! -d "${HOME}/bin" ]]; then
   mkdir -p "${HOME}/bin"
  fi
  bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/soar/refs/heads/main/install.sh")
  command -v soar &>/dev/null || return 1
  if [[ ! -s "${HOME}/.config/soar/config.toml" ]]; then
     soar defconfig --external
  fi
  soar sync
}
export -f install_soar
function decode_base64()
{
  if [[ -f "$1" ]]; then
    base64 -d "$1"
  else
    echo "${1:-$(cat)}" | base64 -d
  fi
}
export -f decode_base64
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
function encode_base64()
{
  if [[ -f "$1" ]]; then
    base64 -w0 "$1"
  else  
    echo "${1:-$(cat)}" | base64 -w0
  fi
}
export -f encode_base64
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
function install_soar_force()
{
  if [[ ! -d "${HOME}/bin" ]]; then
     mkdir -p "${HOME}/bin"
  fi
  if [[ ! -d "${HOME}/.local/bin" ]]; then
     mkdir -p "${HOME}/.local/bin"
  fi
  rm -rvf "${HOME}/.config/soar" "${HOME}/.local/share/soar" 2>/dev/null
  bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/soar/refs/heads/main/install.sh")
  command -v soar &>/dev/null || return 1
  soar defconfig --external
  soar sync
}
export -f install_soar_force
function nixbuild_cleanup() 
{
  nix-collect-garbage
  nix-store --gc
}
export -f nixbuild_cleanup
function nixbuild_info()
{
  echo -e "\n"
  nix-instantiate --eval --expr "builtins.toJSON (with import <nixpkgs> {}; $1.meta)" --quiet 2>/dev/null | jq -r fromjson 2>/dev/null
  echo -e "\n"
}
export -f nixbuild_info
function nixbuild_static()
{
  nix-build '<nixpkgs>' --impure --attr "pkgsStatic.$1" --cores "$(($(nproc)+1))" --max-jobs "$(($(nproc)+1))" --log-format bar-with-logs --out-link "./NIX_BUILD"
}
export -f nixbuild_static
function refreshenv()
{
  source "$(realpath "${HOME}/.bashrc" | tr -d '[:space:]')"
}
export -f refreshenv
function strip_debug()
{
  objcopy --remove-section=".comment" --remove-section=".note.*" "$1" 2>/dev/null
  strip --strip-debug --strip-dwo --strip-unneeded "$1" 2>/dev/null
}
export -f strip_debug
function strip_space_stdin()
{
  if [[ -f "$1" ]]; then
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$1"
  else  
    echo "${1:-$(cat)}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
  fi
}
export -f strip_space_stdin
function strip_space_tr()
{
  echo "${1:-$(cat)}" | tr -d '"'\''[:space:]'
}
export -f strip_space_tr
function url_decode_py()
{
  if command -v python &>/dev/null; then
    echo "${1:-$(cat)}" | python -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))'
  elif command -v python3 &>/dev/null; then
    echo "${1:-$(cat)}" | python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))'
  fi
}
export -f url_decode_py
function url_encode_jq()
{
  echo "${1:-$(cat)}" | jq -sRr '@uri' | tr -d '[:space:]'
}
export -f url_encode_jq
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
     export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
     #export FZF_DEFAULT_OPTS='--no-height --color=bg+:#343d46,gutter:-1,pointer:#ff3c3c,info:#0dbc79,hl:#0dbc79,hl+:#23d18b'
     export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND}"
     export FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :50 {}'"
     export FZF_ALT_C_COMMAND='fd --type d "." --hidden --exclude .git'
     export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -50'"
     eval "$(fzf --bash)"
  fi
elif [[ "${NO_FZF}" == 1 ]]; then
   disable_fzf &>/dev/null
fi
#-------------------------------------------------------------------------------#
