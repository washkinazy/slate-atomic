# Build Process

This document describes how slate-atomic images are built.

## Image Variants

Two images are built from a single Containerfile using the `BUILD_NVIDIA` argument:

- **slate**: Base image (`BUILD_NVIDIA=N`)
- **slate-nvidia-open**: Base image + Nvidia open drivers (`BUILD_NVIDIA=Y`)

## Base Image

Both variants build from:
```
quay.io/fedora/fedora-silverblue:43
```

## Build Arguments

- `FEDORA_VERSION`: Fedora version (default: 43)
- `IMAGE_NAME`: Output image name (slate or slate-nvidia-open)
- `IMAGE_VENDOR`: Vendor identifier (default: washkinazy)
- `BUILD_NVIDIA`: Whether to install nvidia drivers (Y or N, default: N)

## Build Stages

### Stage 1: Context (scratch)
Copies build assets into a scratch container for mounting:
- `build_files/` → `/` (build scripts)
- `sys_files/` → `/sys_files` (system files to install)
- `just/` → `/just` (sjust recipes for end users)

### Stage 2: Akmods
Pulls pre-built kernel modules and signed kernel from ublue-os:

**akmods (base):**
```
ghcr.io/ublue-os/akmods:main-43
```
Provides:
- `/rpms/ublue-os/` → mounted at `/tmp/akmods-rpms` (ublue-os base packages)
- `/kernel-rpms/` → mounted at `/tmp/kernel-rpms` (signed kernel matching akmods)

**akmods-nvidia-open (nvidia drivers):**
```
ghcr.io/ublue-os/akmods-nvidia-open:main-43
```
Provides:
- `/rpms/` → mounted at `/tmp/akmods-nv-rpms` (nvidia kernel modules and packages)

### Stage 3: Main Build
Single RUN command with multiple scripts chained:

```dockerfile
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=bind,from=akmods,src=/rpms/ublue-os,dst=/tmp/akmods-rpms \
    --mount=type=bind,from=akmods,src=/kernel-rpms,dst=/tmp/kernel-rpms \
    --mount=type=bind,from=akmods_nvidia,src=/rpms,dst=/tmp/akmods-nv-rpms \
    /ctx/install.sh && \
    if [ "${BUILD_NVIDIA}" == "Y" ]; then \
        AKMODNV_PATH=/tmp/akmods-nv-rpms /ctx/nvidia-install.sh \
    ; fi && \
    /ctx/initramfs.sh && \
    /ctx/post-install.sh
```

#### Mounts
- `/ctx`: Build context (scripts and assets)
- `/var/cache`: Persistent cache (rpm-ostree, libdnf5)
- `/var/log`: Persistent logs
- `/tmp`: Temporary filesystem
- `/tmp/akmods-rpms`: ublue-os base packages (from akmods stage)
- `/tmp/kernel-rpms`: Signed kernel RPMs (from akmods stage)
- `/tmp/akmods-nv-rpms`: Nvidia kernel modules and packages (from akmods_nvidia stage)

## Build Scripts

Scripts execute in order within a single RUN command:

### 1. install.sh
Runs for all images.

**Actions:**
- Copies `sys_files/` to `/` using `rsync -rvK`
- Installs dnf5 and dnf5-plugins using rpm-ostree
- **F43 Fix:** Swaps rpm-ostree with patched version from ublue-os/staging COPR to fix upstream package layering bug
- Installs ublue-os base packages from `/tmp/akmods-rpms/`
- Removes base kernel packages (kernel, kernel-core, kernel-modules, etc.) using `rpm --erase --nodeps`
- Detects kernel version from `/tmp/kernel-rpms/kernel-core-*.rpm`
- Creates kernel-install shims (disables dracut/rpm-ostree during container build to prevent initramfs errors)
- Installs signed kernel RPMs matching akmods with `--allowerasing` flag
- Restores kernel-install scripts
- Versionlocks kernel packages to prevent version drift
- Creates `/usr/share/slate/just/`
- Copies sjust recipes from `/ctx/just/`
- Creates `/usr/share/ublue-os/just/` if needed
- Imports slate just recipes into ublue-os just system

### 2. nvidia-install.sh
Runs only when `BUILD_NVIDIA=Y`.

**Actions:**
- Disables cisco repo
- Installs ublue-os-nvidia-addons from `$AKMODNV_PATH/ublue-os/` (provides repos and nvidia-kmod-common)
- Enables fedora-nvidia and nvidia-container-toolkit repos
- Sources nvidia variables from `$AKMODNV_PATH/kmods/nvidia-vars`
- Installs nvidia drivers: libva-nvidia-driver, nvidia-driver, nvidia-settings
- Installs nvidia kernel module: kmod-nvidia-${KERNEL_VERSION}-${NVIDIA_AKMOD_VERSION}
- Installs nvidia-container-toolkit (skipped on F43 due to known issues)
- Disables fedora-nvidia and nvidia-container-toolkit repos
- Configures nvidia kernel module variant in `/etc/nvidia/kernel.conf`
- Enables ublue-nvctk-cdi.service
- Installs SELinux policy for nvidia-container
- Copies `/etc/modprobe.d/nvidia-modeset.conf` to `/usr/lib/modprobe.d/` for initramfs
- Modifies `/usr/lib/dracut/dracut.conf.d/99-nvidia.conf` (installed by nvidia-driver) to force-load drivers
- Adds intel/amd iGPU drivers to early load for chromium hardware acceleration compatibility

### 3. initramfs.sh
Placeholder script. Initramfs regeneration is handled automatically by rpm-ostree.

### 4. post-install.sh
Cleanup and finalization.

**Actions:**
- Removes `/tmp/*`
- Removes `/usr/etc`
- Removes and recreates `/boot`
- Cleans `/var/*` except `cache` and `log`
- Cleans `/var/cache/*` except `libdnf5`
- Creates `/var/tmp` with 1777 permissions
- Runs `ostree container commit`

### 5. bootc container lint
Final validation step after RUN completes.

## Build Artifacts

### System Files
Files placed in `sys_files/usr/` are copied to `/usr/` in the final image via `install.sh`.

### sjust Recipes
Files in `just/` are:
1. Copied to `/usr/share/slate/just/`
2. Imported into `/usr/share/ublue-os/just/60-custom.just`
3. Available to users as `sjust <command>`

## Local Build Commands

Build images locally using just:

```bash
just build-slate              # Builds slate (BUILD_NVIDIA=N)
just build-slate-nvidia       # Builds slate-nvidia-open (BUILD_NVIDIA=Y)
just build-all                # Builds both images
```

## CI/CD Build

GitHub Actions builds both images in parallel using a matrix strategy:

```yaml
matrix:
  image:
    - slate
    - slate-nvidia-open
  include:
    - image: slate
      build_nvidia: "N"
    - image: slate-nvidia-open
      build_nvidia: "Y"
```

Each build:
1. Checks out repository
2. Builds image with appropriate `BUILD_NVIDIA` value
3. Pushes to `ghcr.io/washkinazy/<image>:latest`
4. Signs with cosign using `SIGNING_SECRET`

## Image Signing

Images are signed with cosign using a private key stored in GitHub Secrets:
- Secret name: `SIGNING_SECRET`
- Public key: `cosign.pub` (committed to repository)
- Private key: `cosign.key` or `cosign.private` (never committed)
