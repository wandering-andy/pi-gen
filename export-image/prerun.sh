#!/bin/bash -e

# Sets image name, unmount image if it's already mounted, and deletes the image file.
IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

unmount_image "${IMG_FILE}"

rm -f "${IMG_FILE}"

# Remove and recreate the root file system directory
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

# Set boot size and calculate root size
BOOT_SIZE="$((512 * 1024 * 1024))"
ROOT_SIZE=$(du --apparent-size -s "${EXPORT_ROOTFS_DIR}" --exclude var/cache/apt/archives --exclude boot/firmware --block-size=1 | cut -f 1)

# All partition sizes and starts will be aligned to this size
ALIGN="$((4 * 1024 * 1024))"

# Add this much space to the calculated file size. This allows for
# some overhead (since actual space usage is usually rounded up to the
# filesystem block size) and gives some free space on the resulting
# image.
ROOT_MARGIN="$(echo "($ROOT_SIZE * 0.2 + 200 * 1024 * 1024) / 1" | bc)"

BOOT_PART_START=$((ALIGN))
BOOT_PART_SIZE=$(((BOOT_SIZE + ALIGN - 1) / ALIGN * ALIGN))
ROOT_PART_START=$((BOOT_PART_START + BOOT_PART_SIZE))
ROOT_PART_SIZE=$(((ROOT_SIZE + ROOT_MARGIN + ALIGN  - 1) / ALIGN * ALIGN))
IMG_SIZE=$((BOOT_PART_START + BOOT_PART_SIZE + ROOT_PART_SIZE))

# Creates an image file of size IMG_SIZE, and then creates a boot (fat32) and a root partition (ext4)
truncate -s "${IMG_SIZE}" "${IMG_FILE}"

parted --script "${IMG_FILE}" mklabel msdos
parted --script "${IMG_FILE}" unit B mkpart primary fat32 "${BOOT_PART_START}" "$((BOOT_PART_START + BOOT_PART_SIZE - 1))"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${ROOT_PART_START}" "$((ROOT_PART_START + ROOT_PART_SIZE - 1))"

# This block of code is creating a loop device for the image file
cnt=0
until ensure_next_loopdev && LOOP_DEV="$(losetup --show --find --partscan "$IMG_FILE")"; do
	if [ $cnt -lt 5 ]; then
		cnt=$((cnt + 1))
		echo "Error in losetup.  Retrying..."
		sleep 5
	else
				echo "ERROR: losetup failed; exiting"
		exit 1
	fi
done

BOOT_DEV="${LOOP_DEV}p1"
ROOT_DEV="${LOOP_DEV}p2"

# Checks for certain features in /etc/mke2fs.conf
# if they exist, adds them to the ROOT_FEATURES variable
ROOT_FEATURES="^huge_file"
for FEATURE in 64bit; do
if grep -q "$FEATURE" /etc/mke2fs.conf; then
	ROOT_FEATURES="^$FEATURE,$ROOT_FEATURES"
fi
done

# Create filesystems on the boot and root partitions of the loop device and mount them
mkdosfs -n bootfs -F 32 -s 4 -v "$BOOT_DEV" > /dev/null
mkfs.ext4 -L rootfs -O "$ROOT_FEATURES" "$ROOT_DEV" > /dev/null
mount -v "$ROOT_DEV" "${ROOTFS_DIR}" -t ext4
mkdir -p "${ROOTFS_DIR}/boot/firmware"
mount -v "$BOOT_DEV" "${ROOTFS_DIR}/boot/firmware" -t vfat

# Copy the contents of the root filesystem, excluding certain directories, to the newly created filesystems
rsync -aHAXx --exclude /var/cache/apt/archives --exclude /boot/firmware "${EXPORT_ROOTFS_DIR}/" "${ROOTFS_DIR}/"
rsync -rtx "${EXPORT_ROOTFS_DIR}/boot/firmware/" "${ROOTFS_DIR}/boot/firmware/"
