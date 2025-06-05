#!/usr/bin/env bash

#-------------------------------------------------------#
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Install & Setup Nix
###-----------------------------------------------------###

#-------------------------------------------------------#
##ENV
if [[ -z "${USER+x}" ]] || [[ -z "${USER##*[[:space:]]}" ]]; then
 USER="$(whoami | tr -d '[:space:]')"
fi
if [[ -z "${HOME+x}" ]] || [[ -z "${HOME##*[[:space:]]}" ]]; then
 HOME="$(getent passwd "${USER}" | awk -F':' 'NF >= 6 {print $6}' | tr -d '[:space:]')"
fi
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
#-------------------------------------------------------#

#-------------------------------------------------------#
##Install
cd "${TEMP_DIR}"
sudo rm -rf "/etc/bash.bashrc.backup-before-nix" "/etc/nix" "/nix" "/etc/nix/nix.conf" "${HOME}/.config/nix/nix.conf" "${HOME}/.nix-profile" "${HOME}/.nix-defexpr" "${HOME}/.nix-channels" "${HOME}/.local/state/nix" "${HOME}/.cache/nix" 2>/dev/null
if [[ "$(uname -m | tr -d '[:space:]')" == "riscv64" ]]; then
 #Install Officially
  curl -qfsSL "https://nixos.org/nix/install" | bash -s -- --no-daemon
  [[ -f "${HOME}/.bash_profile" ]] && source "${HOME}/.bash_profile"
  [[ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]] && source "${HOME}/.nix-profile/etc/profile.d/nix.sh"
 #Enable Experimental Features
  sudo mkdir -p "/etc/nix"
  echo "experimental-features = nix-command flakes" | sudo tee -a "/etc/nix/nix.conf"
  mkdir -p "${HOME}/.config"
  ln -fsv "/etc/nix/nix.conf" "${HOME}/.config/nix/nix.conf"
else
 ##https://github.com/DeterminateSystems/nix-installer
  "/nix/nix-installer" uninstall --no-confirm 2>/dev/null
  #curl -qfsSL "https://install.determinate.systems/nix" | bash -s -- install linux --init none --no-confirm
  curl -qfsSL "https://install.determinate.systems/nix" | bash -s -- install linux --init none --extra-conf "filter-syscalls = false" --no-confirm
  source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  #Fix perms: could not set permissions on '/nix/var/nix/profiles/per-user' to 755: Operation not permitted
  #sudo chown --recursive "${USER}" "/nix"
  sudo chown --recursive "${USER}" "/nix"
  echo "root    ALL=(ALL:ALL) ALL" | sudo tee -a "/etc/sudoers"
fi
##Test
hash -r &>/dev/null
if ! command -v nix &> /dev/null; then
  echo -e "\n[-] nix NOT Found\n"
 exit 1
else
  #Add Env vars
   export NIXPKGS_ALLOW_BROKEN="1" 
   export NIXPKGS_ALLOW_UNFREE="1"
   export NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM="1"
  #Update Channels
   nix --version && nix-channel --list && nix-channel --update
  #Seed Local Data 
   nix derivation show "nixpkgs#hello" --impure --refresh --quiet
  #Build Bash (triggers bootstrap)
   nix-build '<nixpkgs>' --impure --attr "pkgsStatic.bash" --cores "$(($(nproc)+1))" --max-jobs "$(($(nproc)+1))" --log-format bar-with-logs
  #Exit 
   sudo ldconfig 2>/dev/null || true
fi
#-------------------------------------------------------#