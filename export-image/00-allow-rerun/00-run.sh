#!/bin/bash -e

# Check if qemu-arm-static executable does not exist in the specified directory
if [ ! -x "${ROOTFS_DIR}/usr/bin/qemu-arm-static" ]; then
    # If it does not exist, copy it from /usr/bin/ to the specified directory
	cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"
fi

# Check if the ld.so.preload file exists in the specified directory
if [ -e "${ROOTFS_DIR}/etc/ld.so.preload" ]; then
    # If it exists, rename it to ld.so.preload.disabled
	mv "${ROOTFS_DIR}/etc/ld.so.preload" "${ROOTFS_DIR}/etc/ld.so.preload.disabled"
fi
