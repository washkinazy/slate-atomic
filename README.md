# slate-atomic

Opinionated atomic desktop based on Fedora Silverblue with zero maintenance included.

## What is slate?

slate is a custom atomic desktop image built directly on Fedora Silverblue 43, providing:

- **Immutable base system** with atomic updates
- **Curated package selection** for modern development and productivity
- **sjust commands** for easy system management
- **Nvidia support** with open drivers (slate-nvidia-open variant)

## Available Images

- **slate**: Base GNOME image on Fedora Silverblue 43
- **slate-nvidia-open**: slate + Nvidia open drivers (Turing and newer GPUs)

## Installation

### Prerequisites

You must be running an existing atomic Fedora installation (Silverblue, Kinoite, etc.).

### Rebase to slate

1. First, rebase to the unsigned image to get the signing keys:
   ```bash
   rpm-ostree rebase ostree-unverified-registry:ghcr.io/washkinazy/slate:latest
   systemctl reboot
   ```

2. After reboot, rebase to the signed image:
   ```bash
   rpm-ostree rebase ostree-image-signed:docker://ghcr.io/washkinazy/slate:latest
   systemctl reboot
   ```

### Rebase to slate-nvidia-open

Follow the same process but use `slate-nvidia-open` instead of `slate`:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/washkinazy/slate-nvidia-open:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/washkinazy/slate-nvidia-open:latest
systemctl reboot
```

### Post-Install for Nvidia

After installing slate-nvidia-open, set the required kernel arguments:

```bash
sjust set-nvidia-kargs
systemctl reboot
```

For Optimus laptops, also run:
```bash
sjust configure-nvidia-optimus
systemctl reboot
```

## Using slate

### System Management

```bash
# Show available slate commands
sjust slate-help

# Show system information
sjust system-info

# Update system
sjust update

# Switch between images
sjust rebase-slate
sjust rebase-slate-nvidia
```

### Updates

slate images are rebuilt weekly and when changes are pushed. To update:

```bash
sjust update
systemctl reboot
```

## What's Included

### Base Image
- Fedora Silverblue 43 with GNOME
- Atomic updates and immutable base system

### Nvidia (slate-nvidia-open only)
- Nvidia open kernel modules from ublue-os akmods
- Nvidia drivers and tools from negativo17
- Configured for DRM modesetting

## Development

See [BUILD.md](BUILD.md) for detailed build process documentation.

### Prerequisites
- podman or docker
- just (`dnf install just`)
- cosign or skopeo (either works for signing)
  - `dnf install cosign` OR `dnf install skopeo`

### Quick start
```bash
# Generate signing keys (first time only)
just generate-signing-key

# Add signing key to GitHub:
gh secret set SIGNING_SECRET < cosign.key  # or cosign.private if using skopeo

# Build images locally
just build-slate
just build-nvidia

# Build all
just build-all
```

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Built on [Fedora Silverblue](https://fedoraproject.org/silverblue/)
- Nvidia drivers from [ublue-os akmods](https://github.com/ublue-os/akmods) and [negativo17](https://negativo17.org/)
- Inspired by [Universal Blue](https://universal-blue.org/)
