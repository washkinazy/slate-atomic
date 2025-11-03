# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

slate-atomic is an opinionated atomic desktop based on Fedora and Universal Blue. The repository is currently in its initial setup phase.

## Working Guidelines

**IMPORTANT: When the user asks a question or wants to discuss something, DO NOT make changes immediately.**

- If the user says "I want to discuss...", "Can we talk about...", or asks a question, respond with analysis and suggestions ONLY
- Wait for explicit confirmation before making any file changes
- Present options and ask which approach they prefer
- Only make changes when the user clearly requests them (e.g., "do it", "make that change", "update the file")

## Architecture

### Atomic Desktop Fundamentals
This project builds upon the Universal Blue project, which provides atomic desktop variants of Fedora. Key concepts:

- **Immutable Base Image**: System files are read-only and managed as container images
- **Atomic Updates**: System updates are transactional - either fully applied or rolled back
- **Layering**: Customizations are layered on top of base images
- **bootc**: Tool for managing bootable container images (`bootc status`, `bootc switch`, `bootc upgrade`)
- **rpm-ostree**: Traditional tool for managing ostree-based systems and rebasing

### Image Hierarchy
Images in the atomic desktop ecosystem typically follow this structure:
1. **Fedora Atomic Base** (e.g., `quay.io/fedora-ostree-desktops/base-atomic`)
2. **Universal Blue Main** (`ghcr.io/ublue-os/base-main`) - Fedora + common enhancements
3. **Desktop Variants** (Aurora, Bluefin, Bazzite) - Built on main with specific customizations
4. **Custom Images** (like slate-atomic) - Built on any of the above

## Build Approach

slate-atomic uses the **Containerfile approach** (not BlueBuild) for maximum control and transparency.

**Build variants controlled by single ARG:**
- `BUILD_NVIDIA=N` → slate (base image)
- `BUILD_NVIDIA=Y` → slate-nvidia-open (base + nvidia drivers)

Both variants built from same Containerfile with conditional nvidia-install.sh execution.

## Containerfile Build Context

The build uses multi-stage approach with several mounts:

**Stage 1 - ctx (scratch):** Holds build assets
- `/ctx/` - build_files scripts
- `/ctx/sys_files/` - system files to install
- `/ctx/just/` - sjust recipes

**Stage 2 - akmods:** ublue-os base packages and signed kernel
- `/tmp/akmods-rpms/` - ublue-os base packages (mounted from ghcr.io/ublue-os/akmods:main-43)
- `/tmp/kernel-rpms/` - signed kernel RPMs

**Stage 3 - akmods_nvidia:** Nvidia kernel modules
- `/tmp/akmods-nv-rpms/` - nvidia kmods and packages (mounted from ghcr.io/ublue-os/akmods-nvidia-open:main-43)

**Persistent caches:**
- `/var/cache` - rpm-ostree, libdnf5 cache (speeds up rebuilds)
- `/var/log` - build logs

## Image Signing

Images are signed with sigstore for security and verification.

**Key formats:**
- `cosign.pub` - Public key (committed to repo, used for verification)
- `cosign.private` or `cosign.key` - Private key (NEVER commit, stored in GitHub Secrets as SIGNING_SECRET)

The GitHub Actions workflow (build.yml:86-94) signs images after building and verifies the signature.

## CI/CD with GitHub Actions

**Triggers:** (build.yml:3-12)
- Push to `main` branch
- Pull requests (build only, no publish)
- Weekly schedule (Sundays at midnight)
- Manual workflow dispatch

**Build strategy:** Matrix builds both images in parallel
- slate: `BUILD_NVIDIA=N`
- slate-nvidia-open: `BUILD_NVIDIA=Y`

**Publishing:**
- Images pushed to `ghcr.io/washkinazy/<image>:latest`
- Signed with cosign using SIGNING_SECRET
- Signature verified before workflow completes

## User-Facing Tools (sjust)

On installed systems, users interact with just recipes via the `sjust` command (slate-just):
- Just recipes in `just/` directory become `sjust` commands
- Installed via import in `/usr/share/ublue-os/just/60-custom.just`
- Follow naming convention: `verb-noun` (e.g., `rebase-slate`, `set-nvidia-kargs`)
- All slate commands are in the `[group('slate')]` group

## Reference Repositories

Examples in `/home/washkinazy/dev/reference-atomic/`:
- **main** - Universal Blue base image
- **aurora** - KDE-based desktop (Containerfile approach)
- **wayblue** - Wayland compositor images (BlueBuild approach)
- **image-template** - Universal Blue's official Containerfile template
- **template** - BlueBuild template system

## Testing Locally Built Images

After building with `just build-slate` or `just build-slate-nvidia`:

```bash
# Inspect the built image
just inspect slate
just layers slate  # View image layers

# Test in a shell
just shell slate

# Rebase running system to local build (on existing atomic system)
rpm-ostree rebase ostree-unverified-registry:localhost/slate:latest
# OR for nvidia variant
rpm-ostree rebase ostree-unverified-registry:localhost/slate-nvidia-open:latest

# Reboot to test
systemctl reboot

# Check status
rpm-ostree status
```

## Build Documentation

**IMPORTANT**: Keep `BUILD.md` up to date with how the build process works and what the components do. When changing the Containerfile or build scripts, update BUILD.md to reflect those changes. The documentation should be specific to this repository's implementation.

## This Repository Structure

slate-atomic uses the **Containerfile approach** with direct Fedora base images:

```
slate-atomic/
├── .github/workflows/
│   └── build.yml           # CI/CD pipeline (matrix builds both images)
├── build_files/
│   ├── install.sh          # Main installation (sys_files, kernel, sjust setup)
│   ├── nvidia-install.sh   # Nvidia driver installation (conditional, BUILD_NVIDIA=Y)
│   ├── initramfs.sh        # Placeholder (rpm-ostree handles initramfs)
│   └── post-install.sh     # Cleanup and ostree commit
├── just/
│   └── 60-slate.just       # sjust commands (available as 'sjust' on installed systems)
├── sys_files/              # Files to copy to / (currently empty, use as needed)
├── BUILD.md                # Build process documentation (keep up to date!)
├── Containerfile           # Build definition with BUILD_NVIDIA conditional
├── Justfile                # Development commands (build, inspect, lint, etc.)
├── cosign.pub              # Public signing key (commit to repo)
├── cosign.private          # Private signing key (NEVER commit, add to GitHub Secrets)
├── .gitignore              # Ignore private keys and build artifacts
├── CLAUDE.md               # This file
└── README.md               # User-facing documentation
```

### Build Script Flow

The Containerfile executes scripts in a single RUN command with multiple mounts:
1. `install.sh` - Copies sys_files, installs dnf5, applies F43 rpm-ostree fix, installs ublue-os packages, swaps to signed kernel from akmods, versionlocks kernel, installs sjust recipes
2. `nvidia-install.sh` - (if BUILD_NVIDIA=Y) Installs nvidia drivers from akmods-nvidia and configures dracut
3. `initramfs.sh` - Placeholder (rpm-ostree handles initramfs automatically)
4. `post-install.sh` - Cleans up /tmp, /usr/etc, /boot, /var, runs ostree commit

### Images Built

- **slate**: Base GNOME image on Fedora Silverblue 43
- **slate-nvidia-open**: slate + Nvidia open drivers (Turing+ GPUs)

### Key Design Decisions

1. **Base**: Fedora Silverblue 43 (not Universal Blue main) - `quay.io/fedora/fedora-silverblue:43`
2. **Kernel**: Uses ublue-os signed kernel from akmods (required for nvidia kmod compatibility)
3. **Nvidia**: ublue-os akmods-nvidia-open + negativo17 repos (Turing+ GPUs, open drivers only)
4. **User commands**: `sjust` (slate just) instead of `ujust` - installed via /usr/share/ublue-os/just/60-custom.just import
5. **Build approach**: Single Containerfile with BUILD_NVIDIA conditional (following ublue-os/main pattern)
6. **No BlueBuild dependency**: Maximum control and transparency
7. **F43 workaround**: Uses patched rpm-ostree from ublue-os/staging COPR to fix upstream package layering bug

### Critical Implementation Details

**Kernel Management (install.sh:27-58):**
- Swaps base Fedora kernel for ublue-os signed kernel matching akmods
- Creates kernel-install shims during build to prevent dracut/rpm-ostree errors
- Uses `--allowerasing` flag to force kernel replacement
- Versionlocks kernel packages to prevent drift from akmods

**sjust Integration (install.sh:59-64):**
- Copies just recipes to `/usr/share/slate/just/`
- Imports into `/usr/share/ublue-os/just/60-custom.just`
- Available as `sjust` command on installed systems

**Nvidia Configuration (nvidia-install.sh:48-52):**
- Forces nvidia driver load in dracut to fix black screen on boot
- Pre-loads intel/amd iGPU drivers for Chromium hardware acceleration
- Modifies `/usr/lib/dracut/dracut.conf.d/99-nvidia.conf`

## slate-atomic Development Commands

### First-Time Setup

**Note:** Signing keys are already generated for this repository.

If you fork this repo and want to use your own signing keys:

```bash
# Remove existing keys
rm -f cosign.pub cosign.private

# Install either cosign or skopeo (both generate compatible sigstore keys)
sudo dnf install cosign
# OR
sudo dnf install skopeo

# Generate signing keys (only once!)
# Auto-detects cosign or skopeo
just generate-signing-key

# Add private key to GitHub Secrets:
# (cosign creates cosign.key, skopeo creates cosign.private)
gh secret set SIGNING_SECRET < cosign.key
# OR if using skopeo:
gh secret set SIGNING_SECRET < cosign.private

# Commit public key to repository:
git add cosign.pub
git commit -m "Add sigstore signing key"
```

### Building Images Locally

```bash
# Build slate base image
just build-slate

# Build slate-nvidia-open
just build-slate-nvidia

# Build all images
just build-all

# Build with specific tag
just build-slate testing
```

### Testing Images

```bash
# Inspect built image
just inspect slate
just inspect slate-nvidia-open

# View image layers
just layers slate

# Run shell in image for debugging
just shell slate
```

### Maintenance

```bash
# Clean build artifacts
just clean

# Lint shell scripts
just lint

# Check Just syntax
just check

# Fix Just syntax
just fix
```

### CI/CD Publishing

Images automatically published to:
- `ghcr.io/washkinazy/slate:latest`
- `ghcr.io/washkinazy/slate-nvidia-open:latest`

Triggers: push to main, PRs (build only), weekly, or manual dispatch

Users install via:
```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/washkinazy/slate:latest
```

## End User Commands (sjust)

On installed slate systems, users can run:

```bash
# Show all slate commands
sjust slate-help

# System information
sjust system-info

# Update system
sjust update

# Rebase between images
sjust rebase-slate
sjust rebase-slate-nvidia

# Nvidia-specific (nvidia image only)
sjust set-nvidia-kargs
sjust configure-nvidia-optimus
```

## Adding Packages

Edit `build_files/install.sh` (after dnf5 is installed):

```bash
# Add after the ublue-os package installation section
dnf5 -y install package-name another-package

# For COPR packages
dnf5 -y copr enable username/repo-name
dnf5 -y install package-from-copr
dnf5 -y copr disable username/repo-name  # Always disable after installing
```

## Adding System Files

Place files in `sys_files/` matching the target path:
- `sys_files/usr/local/bin/myscript` → `/usr/local/bin/myscript`
- `sys_files/usr/share/applications/app.desktop` → `/usr/share/applications/app.desktop`

Files are copied via `rsync -rvK /ctx/sys_files/ /` in install.sh:1-6

## Adding sjust Recipes

Edit `just/60-slate.just` with new commands:

```just
# Description of command
[group('slate')]
my-command:
    echo "Running my command"
    # command implementation
```
