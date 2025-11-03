#!/bin/bash

set -ouex pipefail

FRELEASE="$(rpm -E %fedora)"
: "${AKMODNV_PATH:=/tmp/akmods-rpms}"

if ! command -v dnf5 >/dev/null; then
    echo "Requires dnf5... Exiting"
    exit 1
fi

# Disable cisco repo
dnf5 config-manager setopt fedora-cisco-openh264.enabled=0

# Install ublue-os-nvidia-addons (provides repos and nvidia-kmod-common)
dnf5 install -y "${AKMODNV_PATH}"/ublue-os/ublue-os-nvidia-addons-*.rpm

# Enable repos provided by ublue-os-nvidia-addons
dnf5 config-manager setopt fedora-nvidia.enabled=1 nvidia-container-toolkit.enabled=1

# Source nvidia variables
source "${AKMODNV_PATH}"/kmods/nvidia-vars

# Install nvidia drivers and kernel module
dnf5 install -y \
    libva-nvidia-driver \
    nvidia-driver \
    nvidia-settings \
    "${AKMODNV_PATH}"/kmods/kmod-nvidia-"${KERNEL_VERSION}"-"${NVIDIA_AKMOD_VERSION}"."${DIST_ARCH}".rpm

# nvidia-container-toolkit has issues in F43
if [[ "${FRELEASE}" -ne 43 ]]; then
    dnf5 install -y nvidia-container-toolkit
fi

# Disable repos
dnf5 config-manager setopt fedora-nvidia.enabled=0 nvidia-container-toolkit.enabled=0

# Configure nvidia kernel module variant
sed -i "s/^MODULE_VARIANT=.*/MODULE_VARIANT=$KERNEL_MODULE_TYPE/" /etc/nvidia/kernel.conf

# Enable nvidia container toolkit service
systemctl enable ublue-nvctk-cdi.service
semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp

# Universal Blue specific Initramfs fixes
cp /etc/modprobe.d/nvidia-modeset.conf /usr/lib/modprobe.d/nvidia-modeset.conf
# we must force driver load to fix black screen on boot for nvidia desktops
sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
# as we need forced load, also must pre-load intel/amd iGPU else chromium web browsers fail to use hardware acceleration
sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
