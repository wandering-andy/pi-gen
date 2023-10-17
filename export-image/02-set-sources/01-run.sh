#!/bin/bash -e

# This command finds and deletes all files in the specified directory
find "${ROOTFS_DIR}/var/lib/apt/lists/" -type f -delete

# Starts a chroot environment, updates the package lists for upgrades and new package
# installations, upgrades the system by removing and purging unnecessary packages,
# cleans the local repository of retrieved package files leaving everything clean
on_chroot << EOF
apt-get update
apt-get -y dist-upgrade --auto-remove --purge
apt-get clean
EOF
