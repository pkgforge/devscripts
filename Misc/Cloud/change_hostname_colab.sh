#!/usr/bin/env bash
# https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/Cloud/change_hostname_colab.sh
#Get the current hostname
  unset hostname
  hostname="$(cat '/etc/hostname')"
  new_hostname="pkgforge-dev"
#/etc/hostname  
  sudo cp -fv "/etc/hostname" "/tmp/hostname.tmp"
  sudo sed -i "s/${hostname}/${new_hostname}/g" "/tmp/hostname.tmp"
  sudo cat "/tmp/hostname.tmp" > "/etc/hostname"
#/etc/hosts  
  sudo cp "/etc/hosts" "/tmp/hosts.tmp"
  sudo sed -i "s/${hostname}/${new_hostname}/g" "/tmp/hosts.tmp"
  sudo cat "/tmp/hosts.tmp" > "/etc/hosts"
 #hostname
  sudo hostname "${new_hostname}"
#EOF
