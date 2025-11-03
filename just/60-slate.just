# vim: set ft=make :
########################
### 60-slate.just
### slate-specific recipes for end users
### Available as 'sjust <command>' on installed systems
########################

# Show all available sjust commands
[group('slate')]
slate-help:
    @echo "slate - Opinionated atomic desktop"
    @echo ""
    @echo "Available sjust commands:"
    @sjust --list

# Show system information
[group('slate')]
system-info:
    @echo "slate System Information"
    @echo "======================="
    @fastfetch || neofetch || echo "Install fastfetch for detailed system info"
    @echo ""
    @echo "Image Information:"
    @rpm-ostree status | head -20

# Update the system
[group('slate')]
update:
    @echo "Updating slate system..."
    rpm-ostree update
    @echo ""
    @echo "Update downloaded. Reboot to apply changes:"
    @echo "  systemctl reboot"

# Rebase to slate stable
[group('slate')]
rebase-slate:
    rpm-ostree rebase ostree-image-signed:docker://ghcr.io/washkinazy/slate:latest

# Rebase to slate-nvidia-open
[group('slate')]
rebase-slate-nvidia:
    rpm-ostree rebase ostree-image-signed:docker://ghcr.io/washkinazy/slate-nvidia-open:latest

# Configure nvidia for optimus laptops (nvidia image only)
[group('slate')]
configure-nvidia-optimus:
    #!/usr/bin/bash
    if ! rpm -q nvidia-driver &>/dev/null; then
        echo "ERROR: Nvidia drivers not installed. This command is only for slate-nvidia-open."
        exit 1
    fi
    echo "Configuring Nvidia Optimus..."
    sudo cp -f /usr/share/ublue-os/nvidia-vfio/nvidia-*.rules /etc/udev/rules.d/
    echo "Optimus configuration complete. Reboot for changes to take effect."

# Set nvidia kernel arguments (nvidia image only)
[group('slate')]
set-nvidia-kargs:
    #!/usr/bin/bash
    if ! rpm -q nvidia-driver &>/dev/null; then
        echo "ERROR: Nvidia drivers not installed. This command is only for slate-nvidia-open."
        exit 1
    fi
    echo "Setting Nvidia kernel arguments..."
    sudo rpm-ostree kargs \
        --append-if-missing=rd.driver.blacklist=nouveau \
        --append-if-missing=modprobe.blacklist=nouveau \
        --append-if-missing=nvidia-drm.modeset=1 \
        --append-if-missing=nvidia-drm.fbdev=1
    echo "Kernel arguments set. Reboot for changes to take effect."
