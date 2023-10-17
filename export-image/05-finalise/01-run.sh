#!/bin/bash -e

# Sets variables for IMG_FILE and INFO_FILE names
IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"
INFO_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.info"

# Modifies update-initramfs.conf file by replacing any line that starts with 'update_initramfs=' with 'update_initramfs=all'.
sed -i 's/^update_initramfs=.*/update_initramfs=all/' "${ROOTFS_DIR}/etc/initramfs-tools/update-initramfs.conf"

# The following block of code is executed in a chroot environment.
# Updates the initramfs. The '-u' option means it's updating an existing initramfs.
# Checks if the /etc/init.d/fake-hwclock script is executable. If it is, it stops the fake-hwclock.
# This command checks if the 'hardlink' command exists. If it does, it runs the hardlink command on the /usr/share/doc directory.

on_chroot << EOF
update-initramfs -u
if [ -x /etc/init.d/fake-hwclock ]; then
	/etc/init.d/fake-hwclock stop
fi

if hash hardlink 2>/dev/null; then
	hardlink -t /usr/share/doc
fi
EOF

# Checks if the .config directory exists in the home directory of the
# first user. If it does, it changes its permissions to 700.
if [ -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config" ]; then
	chmod 700 "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config"
fi

# Removes the qemu-arm-static binary from the /usr/bin directory.
rm -f "${ROOTFS_DIR}/usr/bin/qemu-arm-static"

# Unless USE_QEMU variable is set to 1, checks if the file
# ld.so.preload.disabled exists in the /etc directory. If it does,
# it renames it to ld.so.preload.
if [ "${USE_QEMU}" != "1" ]; then
	if [ -e "${ROOTFS_DIR}/etc/ld.so.preload.disabled" ]; then
		mv "${ROOTFS_DIR}/etc/ld.so.preload.disabled" "${ROOTFS_DIR}/etc/ld.so.preload"
	fi
fi

# Removes old network interfaces file
rm -f "${ROOTFS_DIR}/etc/network/interfaces.dpkg-old"

# Removes old apt sources list and trusted gpg files
rm -f "${ROOTFS_DIR}/etc/apt/sources.list~"
rm -f "${ROOTFS_DIR}/etc/apt/trusted.gpg~"

# Removes backup user and group files
rm -f "${ROOTFS_DIR}/etc/passwd-"
rm -f "${ROOTFS_DIR}/etc/group-"
rm -f "${ROOTFS_DIR}/etc/shadow-"
rm -f "${ROOTFS_DIR}/etc/gshadow-"
rm -f "${ROOTFS_DIR}/etc/subuid-"
rm -f "${ROOTFS_DIR}/etc/subgid-"

# Removes old debconf cache and dpkg files
rm -f "${ROOTFS_DIR}"/var/cache/debconf/*-old
rm -f "${ROOTFS_DIR}"/var/lib/dpkg/*-old

# Removes old icon theme cache
rm -f "${ROOTFS_DIR}"/usr/share/icons/*/icon-theme.cache

# Removes old dbus machine id
rm -f "${ROOTFS_DIR}/var/lib/dbus/machine-id"

# Resets machine-id
true > "${ROOTFS_DIR}/etc/machine-id"

# Links /proc/mounts to /etc/mtab
ln -nsf /proc/mounts "${ROOTFS_DIR}/etc/mtab"

# Clears all log files in /var/log
find "${ROOTFS_DIR}/var/log/" -type f -exec cp /dev/null {} \;

# Removes old VNC private key and updateid files
rm -f "${ROOTFS_DIR}/root/.vnc/private.key"
rm -f "${ROOTFS_DIR}/etc/vnc/updateid"

# Updating the issue file with the current image name
update_issue "$(basename "${EXPORT_DIR}")"

# Installing the updated issue file to the boot firmware directory
install -m 644 "${ROOTFS_DIR}/etc/rpi-issue" "${ROOTFS_DIR}/boot/firmware/issue.txt"

# Copying the updated issue file to the info file
# Copy the updated issue file to the info file
cp "$ROOTFS_DIR/etc/rpi-issue" "$INFO_FILE"

# Create a new block to append to the info file
{
	# Check if the changelog file exists
	if [ -f "$ROOTFS_DIR/usr/share/doc/raspberrypi-kernel/changelog.Debian.gz" ]; then
		# Extract the firmware version from the changelog file
		firmware=$(zgrep "firmware as of" \
			"$ROOTFS_DIR/usr/share/doc/raspberrypi-kernel/changelog.Debian.gz" | \
			head -n1 | sed  -n 's|.* \([^ ]*\)$|\1|p')
		# Print the firmware version with the corresponding GitHub link
		printf "\nFirmware: https://github.com/raspberrypi/firmware/tree/%s\n" "$firmware"

		# Retrieve and print the kernel version from the firmware repository
		kernel="$(curl -s -L "https://github.com/raspberrypi/firmware/raw/$firmware/extra/git_hash")"
		printf "Kernel: https://github.com/raspberrypi/linux/tree/%s\n" "$kernel"

		# Retrieve and print the uname string from the firmware repository
		uname="$(curl -s -L "https://github.com/raspberrypi/firmware/raw/$firmware/extra/uname_string7")"
		printf "Uname string: %s\n" "$uname"
	fi

	# Print a separator
	printf "\nPackages:\n"
	
	# List all installed packages
	dpkg -l --root "$ROOTFS_DIR"
} >> "$INFO_FILE"

# Create the deployment directory if it doesn't exist
mkdir -p "${DEPLOY_DIR}"

# Remove any existing archive files
rm -f "${DEPLOY_DIR}/${ARCHIVE_FILENAME}${IMG_SUFFIX}.*"

# Remove any existing image files
rm -f "${DEPLOY_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

# Move the info file to the deployment directory
mv "$INFO_FILE" "$DEPLOY_DIR/"

# Get the root device
ROOT_DEV="$(mount | grep "${ROOTFS_DIR} " | cut -f1 -d' ')"

# Unmount the root file system directory
unmount "${ROOTFS_DIR}"

# Zero out the free space on the root device to save space
zerofree "${ROOT_DEV}"

# Unmount the image file
unmount_image "${IMG_FILE}"

# Depending on the DEPLOY_COMPRESSION variable, choose the compression method for the image file
case "${DEPLOY_COMPRESSION}" in
zip)
    # If the compression method is zip, navigate to the working directory
    pushd "${STAGE_WORK_DIR}" > /dev/null
    # Use zip to compress the image file with the specified compression level
    zip -"${COMPRESSION_LEVEL}" \
    "${DEPLOY_DIR}/${ARCHIVE_FILENAME}${IMG_SUFFIX}.zip" "$(basename "${IMG_FILE}")"
    # Navigate back to the previous directory
    popd > /dev/null
    ;;
gz)
    pigz --force -"${COMPRESSION_LEVEL}" "$IMG_FILE" --stdout > \
    "${DEPLOY_DIR}/${ARCHIVE_FILENAME}${IMG_SUFFIX}.img.gz"
    ;;
xz)
    xz --compress --force --threads 0 --memlimit-compress=50% -"${COMPRESSION_LEVEL}" \
    --stdout "$IMG_FILE" > "${DEPLOY_DIR}/${ARCHIVE_FILENAME}${IMG_SUFFIX}.img.xz"
    ;;
none | *)
    # If no compression method is specified or the method is not recognized, simply copy the image file to the deploy directory
    cp "$IMG_FILE" "$DEPLOY_DIR/"
;;
esac
