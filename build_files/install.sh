#!/usr/bin/bash

set -ouex pipefail

# Copy System Files onto root
rsync -rvK /ctx/sys_files/ /

# Install dnf5 if not installed
if ! rpm -q dnf5 >/dev/null; then
    rpm-ostree install dnf5 dnf5-plugins
fi

# mitigate upstream bug with rpm-ostree failing to layer packages in F43.
# can be removed when rpm-ostree's libdnf submodule is 8eadf440 or newer
if [[ "$(rpm -E %fedora)" -gt 41 ]]; then
    dnf5 -y copr enable ublue-os/staging
    dnf5 -y swap --repo='copr:copr.fedorainfracloud.org:ublue-os:staging' \
        rpm-ostree rpm-ostree
    dnf5 versionlock add rpm-ostree
    dnf5 -y copr disable ublue-os/staging
fi

# Install ublue-os base packages
dnf5 -y install /tmp/akmods-rpms/*.rpm

# Use Signed Kernel and Versionlock (prevents kernel version mismatch with akmods)
KERNEL_VERSION="$(find /tmp/kernel-rpms/kernel-core-*.rpm -prune -printf "%f\n" | sed 's/kernel-core-//g;s/.rpm//g')"

KERNEL_RPMS=(
    "/tmp/kernel-rpms/kernel-${KERNEL_VERSION}.rpm"
    "/tmp/kernel-rpms/kernel-core-${KERNEL_VERSION}.rpm"
    "/tmp/kernel-rpms/kernel-modules-${KERNEL_VERSION}.rpm"
    "/tmp/kernel-rpms/kernel-modules-core-${KERNEL_VERSION}.rpm"
    "/tmp/kernel-rpms/kernel-modules-extra-${KERNEL_VERSION}.rpm"
)

# Create shims to bypass kernel-install triggering dracut/rpm-ostree during container build
cd /usr/lib/kernel/install.d \
&& mv 05-rpmostree.install 05-rpmostree.install.bak \
&& mv 50-dracut.install 50-dracut.install.bak \
&& printf '%s\n' '#!/bin/sh' 'exit 0' > 05-rpmostree.install \
&& printf '%s\n' '#!/bin/sh' 'exit 0' > 50-dracut.install \
&& chmod +x 05-rpmostree.install 50-dracut.install

# Remove existing kernels then install new ones in single transaction
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    rpm --erase $pkg --nodeps
done

dnf5 -y install --allowerasing "${KERNEL_RPMS[@]}"

# Restore kernel-install scripts
mv -f 05-rpmostree.install.bak 05-rpmostree.install \
&& mv -f 50-dracut.install.bak 50-dracut.install
cd -

dnf5 versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

# Install packages from packages.yaml
/ctx/packages.sh

# Install sjust (slate just) recipes for end users
mkdir -p /usr/share/slate/just
cp -r /ctx/just/* /usr/share/slate/just/
mkdir -p /usr/share/ublue-os/just
echo 'import "/usr/share/slate/just/60-slate.just"' >> /usr/share/ublue-os/just/60-custom.just
