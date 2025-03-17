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
##Apperance
export TERM="xterm-256color"
export EDITOR="/usr/bin/nano"
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
  USER_AGENT="$(curl -qfsSL 'https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/User-Agents/ua_chrome_macos_latest.txt')" && export USER_AGENT="${USER_AGENT}"
fi
if [[ -z "${SYSTMP+x}" ]] || [[ -z "${SYSTMP##*[[:space:]]}" ]]; then
 SYSTMP="$(dirname $(mktemp -u) | tr -d '[:space:]')"
fi
#Core
export LANGUAGE="${LANGUAGE:-en_US:en}"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-${LANG}}"
BW_INTERFACE="$(ip route | grep -i 'default' | awk '{print $5}' | tr -d '[:space:]')" && export BW_INTERFACE="${BW_INTERFACE}"
current_dir="$(pwd)"
##PATHS (Only Required)
export GOROOT="${HOME}/.go"
export GOPATH="${HOME}/go"
export PATH="${HOME}/.local/share/soar/bin:${HOME}/bin:${HOME}/.cargo/bin:${HOME}/.cargo/env:${HOME}/.go/bin:${HOME}/go/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${HOME}/.local/bin:${HOME}/miniconda3/bin:${HOME}/miniconda3/condabin:/usr/local/zig:/usr/local/zig/lib:/usr/local/zig/lib/include:/usr/local/musl/bin:/usr/local/musl/lib:/usr/local/musl/include:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
#-------------------------------------------------------------------------------#


#-------------------------------------------------------------------------------#
##Aliases
if [[ -f ~/.bash_aliases ]]; then
    . ~/.bash_aliases
fi
alias 7z_archive='7z a -t7z -mx="9" -mmt="$(($(nproc)+1))" -bsp1 -bt $1 $2'
alias apptainer_run='unshare -r apptainer run --allow-setuid --keep-privs --writable'
alias bat='batcat'
alias benchmarkQ='curl -qfsSL bench.sh | bash'
alias benchmarkX='curl -qfsSL yabs.sh | bash -s -- -i'
alias cf_warp_trace='echo ; curl -qfsSL "https://1.1.1.1/cdn-cgi/trace" ; echo'
#alias df='duf'
alias dir='dir --color=auto'
alias docker_purge='docker stop $(docker ps -aq) && docker rm $(docker ps -aq) && docker rmi $(docker images -q) -f'
alias du_dir='du -h --max-depth=1 | sort -h'
alias esort='for file in ./* ; do sort -u "$file" -o "$file"; done'
alias egrep='egrep --color=auto'
alias fdfind='fd'
alias fgrep='fgrep --color=auto'
alias file_size='stat -c "%s" "$1" "$2" | numfmt --to="iec" --suffix="B"'
alias grep='grep --color=auto'
alias history_purge='history -c 2>/dev/null ; rm -rf "$HOME/.bash_history"'
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
alias miniserve_dl='miniserve --port 9977 --title "Files" --header "Miniserved: yes" --color-scheme-dark monokai --hide-theme-selector --qrcode --show-wget-footer --hide-version-footer --verbose'
alias miniserve_up='miniserve --port 9977 --title "Files" --header "Miniserved: yes" --color-scheme-dark monokai --hide-theme-selector --qrcode --show-wget-footer --hide-version-footer --upload-files --verbose'
alias my_ipv4='curl --ipv4 -qfsSL "http://ipv4.whatismyip.akamai.com" ; echo'
alias my_ipv6='curl --ipv6 -qfsSL "http://ipv6.whatismyip.akamai.com" ; echo'
alias podman_purge='podman stop -a && podman rm -a -f && podman rmi -a -f'
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
#Functions
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
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
##Dedupe & Fix Path
if command -v awk &>/dev/null && command -v sed &>/dev/null; then
 PATH="$(echo "${PATH}" | awk 'BEGIN{RS=":";ORS=":"}{gsub(/\n/,"");if(!a[$0]++)print}' | sed 's/:*$//')"
fi
export PATH
#-------------------------------------------------------------------------------#
