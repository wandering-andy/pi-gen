#!/bin/bash -e

# Define the image file path using the stage work directory and image filename variables
IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

# Retrieve the image ID by reading the image file
IMGID="$(dd if="${IMG_FILE}" skip=440 bs=1 count=4 2>/dev/null | xxd -e | cut -f 2 -d' ')"

# Define the boot and root part UUIDs using the image ID
BOOT_PARTUUID="${IMGID}-01"
ROOT_PARTUUID="${IMGID}-02"

# Replace the placeholder BOOTDEV in the fstab file with the boot part UUID
sed -i "s/BOOTDEV/PARTUUID=${BOOT_PARTUUID}/" "${ROOTFS_DIR}/etc/fstab"
# Replace the placeholder ROOTDEV in the fstab file with the root part UUID
sed -i "s/ROOTDEV/PARTUUID=${ROOT_PARTUUID}/" "${ROOTFS_DIR}/etc/fstab"
# Replace the placeholder ROOTDEV in the cmdline.txt file with the root part UUID
sed -i "s/ROOTDEV/PARTUUID=${ROOT_PARTUUID}/" "${ROOTFS_DIR}/boot/firmware/cmdline.txt"