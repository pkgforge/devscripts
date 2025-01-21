#!/usr/bin/env bash
#
##DO NOT RUN DIRECTLY
##Self: bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Github/Runners/bootstrap/debian_guix.sh")
#-------------------------------------------------------#

#-------------------------------------------------------#
##Install Guix: https://guix.gnu.org/manual/en/html_node/Installation.html
curl -qfsSL "https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh" -o "./guix-install.sh"
if [[ ! -s "./guix-install.sh" || $(stat -c%s "./guix-install.sh") -le 10 ]]; then
  curl -qfsSL "https://raw.githubusercontent.com/Millak/guix/refs/heads/master/etc/guix-install.sh" -o "./guix-install.sh"
fi
chmod +x "./guix-install.sh" && yes '' | sudo "./guix-install.sh" --uninstall 2>/dev/null
yes '' | sudo "./guix-install.sh" 
#Test
if ! command -v guix &> /dev/null; then
 echo -e "\n[-] guix NOT Found\n"
 export CONTINUE="NO"
 return 1 || exit 1
else
 yes '' | guix install glibc-locales
 export GUIX_LOCPATH="${HOME}/.guix-profile/lib/locale"
 curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/nonguix.channels.scm" | sudo tee "/root/.config/guix/channels.scm"
 GUIX_GIT_REPO="https://git.savannah.gnu.org/git/guix.git"
 ##mirror
 #GUIX_GIT_REPO="https://github.com/Millak/guix"
 GUIX_LATEST_SHA="$(git ls-remote "${GUIX_GIT_REPO}" 'HEAD' | grep -w 'HEAD' | head -n 1 | awk '{print $1}' | tr -d '[:space:]')"
 ##Daemon: https://github.com/metacall/guix/blob/master/scripts/entry-point.sh
 "/root/.config/guix/current/bin/guix-daemon" --build-users-group="guixbuild" &
 DAEMON_PID=$!
 GIT_CONFIG_PARAMETERS="'filter.blob:none.enabled=true'" guix pull --url="${GUIX_GIT_REPO}" --commit="${GUIX_LATEST_SHA}" --cores="$(($(nproc)+1))" --max-jobs="2" --disable-authentication &
 USER_PULL_PID=$!
 sudo GIT_CONFIG_PARAMETERS="'filter.blob:none.enabled=true'" guix pull --url="${GUIX_GIT_REPO}" --commit="${GUIX_LATEST_SHA}" --cores="$(($(nproc)+1))" --max-jobs="2" --disable-authentication &
 ROOT_PULL_PID=$!
 wait "${USER_PULL_PID}" "${ROOT_PULL_PID}" ; guix --version
 rm -rvf "./guix-install.sh" 2>/dev/null
fi
#-------------------------------------------------------#
