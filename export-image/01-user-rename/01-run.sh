#!/bin/bash -e

# Check if DISABLE_FIRST_BOOT_USER_RENAME is disabled
if [[ "${DISABLE_FIRST_BOOT_USER_RENAME}" == "0" ]]; then
    # If not disabled, rename the user
	on_chroot <<- EOF
		SUDO_USER="${FIRST_USER_NAME}" rename-user -f -s
	EOF
else
    # If disabled, remove the piwiz.desktop file from autostart
	rm -f "${ROOTFS_DIR}/etc/xdg/autostart/piwiz.desktop"
fi
