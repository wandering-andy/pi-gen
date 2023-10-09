#!/bin/bash -e

on_chroot << EOF
curl -fsSL https://tailscale.com/install.sh | sh
EOF
