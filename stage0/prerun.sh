#!/bin/bash -e

if [ "$RELEASE" != "${DEB_VER}" ]; then
	echo "WARNING: RELEASE does not match the intended option for this branch."
	echo "         Please check the relevant README.md section."
fi

if [ ! -d "${ROOTFS_DIR}" ]; then
	bootstrap "${RELEASE}" "${ROOTFS_DIR}" http://raspbian.raspberrypi.org/raspbian/
fi
