#!/bin/bash
#shellcheck shell=bash external-sources=false disable=SC1090,SC2164
# DOCKER-INSTALL.SH -- Installation script for the Docker infrastructure on a Raspbian or Ubuntu system
# Usage: source <(curl -s https://raw.githubusercontent.com/wandering-andy/docker-install/dev/docker-install.sh)
#
# Copyright 2021, 2022, Ramon F. Kolb (kx1t)- licensed under the terms and conditions
# of the MIT license. The terms and conditions of this license are included with the Github
# distribution of this package.

clear
echo
echo "Welcome to the Docker Infrastructure installation script"
echo "We will help you install Docker and Docker-compose."
echo "and then help you with your configuration."
echo
echo 'Note - this scripts makes use of "sudo" to install Docker.'
echo "If you haven't added your current login to the \"sudoer\" list,"
echo "you may be asked for your password at various times during the installation."
echo
echo 'This script strongly prefers a "standard" OS setup of Debian Buster or later, including variations like'
echo "Raspberry Pi OS or Ubuntu. It uses \'apt-get\' and \'wget\' to get started, and assumes access to"
echo "the standard package repositories".
echo
echo "If you have an old device usign Debian Stretch, we will try to install the software, but be WARNED that"
echo "Docker for Stretch is deprecated and is no longer actively supported by the Docker community."
echo

if [[ $EUID == 0 ]]; then
	echo 'STOP -- you are running this as an account with superuser privileges (ie: root), but should not be. It is best practice to NOT install Docker services as "root".'
	echo "Instead please log out from this account, log in as a different non-superuser account, and rerun this script."
	echo "If you are unsure of how to create a new user, you can learn how here: https://linuxize.com/post/how-to-create-a-sudo-user-on-debian/"
	echo ""
	exit 1
fi

echo "We'll start by adding your login name, \"${USER}\", to \"sudoers\". This will enable you to use \"sudo\" without having to type your password every time."
echo "You may be asked to enter your password a few times below. We promise, this is the last time."
echo
read -p 'Should we do this now? If you choose "no", you can always to it later by yourself [Y/n] > ' -n 1 text
if [[ ${text,,} != "n" ]]; then
	echo
	echo -n "Adding user \"${USER}\" to the \'sudo\' group... "
	sudo usermod -aG sudo "${USER}"
	echo "done!"
	echo -n "Ensuring that user \"${USER}\" can run \'sudo\' without entering a password... "
	echo "${USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-"${USER}"-privileges >/dev/null
	sudo chmod 0440 /etc/sudoers.d/90-"${USER}"-privileges
	echo "done!"
	echo
	echo "You should be ready to go now. If it continues to ask for a password below, do the following:"
	echo "- press CTRL-c to stop the execution of this install script"
	echo '- type "exit" to log out from your machine'
	echo "- log in again"
	echo "- re-run this script using the same command as you did before"
	echo
fi

echo -n "Updating repositories... "
sudo apt-get update -qq -y >/dev/null && sudo apt-get upgrade -q -y
echo -n "Ensuring dependencies are installed... "
sudo apt-get install -qq -y curl uidmap slirp4netns apt-transport-https ca-certificates curl gnupg2 software-properties-common w3m >/dev/null
echo -n "Getting docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
echo "Installing Docker... "
sudo sh get-docker.sh
echo "Docker installed -- configuring docker..."
sudo usermod -aG docker "${USER}"
sudo mkdir -p /etc/docker
sudo chmod a+rwx /etc/docker
cat >/etc/docker/daemon.json <<EOF
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
sudo chmod u=rw,go=r /etc/docker/daemon.json
echo "export PATH=/usr/bin:$PATH" >>~/.bashrc
export PATH=/usr/bin:$PATH

echo "Installing Docker-compose... "

# new method --get the plugin through apt. This means that it will be maintained through package upgrades in the future
sudo apt install -y docker-compose-plugin
echo 'alias docker-compose="docker compose"' >>~/.bash_aliases
source ~/.bash_aliases

if docker-compose version; then
	echo "Docker-compose was installed successfully."
else
	echo "Docker-compose was not installed correctly - you may need to do this manually."
fi

# Now make sure that libseccomp2 >= version 2.4. This is necessary for Bullseye-based containers
# This is often an issue on Buster and Stretch-based host systems with 32-bits Rasp Pi OS installed pre-November 2021.
# The following code checks and corrects this - see also https://github.com/fredclausen/Buster-Docker-Fixes
OS_VERSION="$(sed -n 's/\(^\s*VERSION_CODENAME=\)\(.*\)/\2/p' /etc/os-release)"
[[ $OS_VERSION == "" ]] && OS_VERSION="$(sed -n 's/^\s*VERSION=.*(\(.*\)).*/\1/p' /etc/os-release)"
OS_VERSION=${OS_VERSION^^}
LIBVERSION_MAJOR="$(apt-cache policy libseccomp2 | grep -e libseccomp2: -A1 | tail -n1 | sed -n 's/.*:\s*\([0-9]*\).\([0-9]*\).*/\1/p')"
LIBVERSION_MINOR="$(apt-cache policy libseccomp2 | grep -e libseccomp2: -A1 | tail -n1 | sed -n 's/.*:\s*\([0-9]*\).\([0-9]*\).*/\2/p')"

if ((LIBVERSION_MAJOR < 2)) || ((LIBVERSION_MAJOR == 2 && LIBVERSION_MINOR < 4)) && [[ ${OS_VERSION} == "BUSTER" ]]; then
	echo "libseccomp2 needs updating. Please wait while we do this."
	sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 04EE7237B7D453EC 648ACFD622F3D138
	echo "deb http://deb.debian.org/debian buster-backports main" | sudo tee -a /etc/apt/sources.list.d/buster-backports.list
	sudo apt update
	sudo apt install -y -q -t buster-backports libseccomp2
elif ((LIBVERSION_MAJOR < 2)) || ((LIBVERSION_MAJOR == 2 && LIBVERSION_MINOR < 4)) && [[ ${OS_VERSION} == "STRETCH" ]]; then
	INSTALL_CANDIDATE=$(curl -qsL http://ftp.debian.org/debian/pool/main/libs/libseccomp/ | w3m -T text/html -dump | sed -n 's/^.*\(libseccomp2_2.5.*armhf.deb\).*/\1/p' | sort | tail -1)
	curl -qsL -o /tmp/"${INSTALL_CANDIDATE}" "http://ftp.debian.org/debian/pool/main/libs/libseccomp/${INSTALL_CANDIDATE}"
	sudo dpkg -i /tmp/"${INSTALL_CANDIDATE}" && rm -f /tmp/"${INSTALL_CANDIDATE}"
fi
# Now make sure all went well
LIBVERSION_MAJOR="$(apt-cache policy libseccomp2 | grep -e libseccomp2: -A1 | tail -n1 | sed -n 's/.*:\s*\([0-9]*\).\([0-9]*\).*/\1/p')"
LIBVERSION_MINOR="$(apt-cache policy libseccomp2 | grep -e libseccomp2: -A1 | tail -n1 | sed -n 's/.*:\s*\([0-9]*\).\([0-9]*\).*/\2/p')"
if ((LIBVERSION_MAJOR > 2)) || ((LIBVERSION_MAJOR == 2 && LIBVERSION_MINOR >= 4)); then
	echo "Your system now uses libseccomp2 version $(apt-cache policy libseccomp2 | sed -n 's/\s*Installed:\s*\(.*\)/\1/p')."
else
	echo "Something went wrong. Your system is using libseccomp2 v$(apt-cache policy libseccomp2 | sed -n 's/\s*Installed:\s*\(.*\)/\1/p'), and it needs to be v2.4 or greater for the ADSB containers to work properly."
	echo "Please follow these instructions to fix this after this install script finishes: https://github.com/fredclausen/Buster-Docker-Fixes"
	read -p "Press ENTER to continue."
fi

echo

# Add some aliases to localhost in `/etc/hosts`. This will speed up recreation of images with docker-compose
if ! grep localunixsocket /etc/hosts >/dev/null 2>&1; then
	echo "Speeding up the recreation of containers when using docker-compose..."
	sudo sed -i 's/^\(127.0.0.1\s*localhost\)\(.*\)/\1\2 localunixsocket localunixsocket.local localunixsocket.home/g' /etc/hosts
fi