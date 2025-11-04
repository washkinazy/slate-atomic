# slate - Opinionated atomic desktop based on Fedora Silverblue
ARG FEDORA_VERSION="${FEDORA_VERSION:-43}"
ARG IMAGE_NAME="${IMAGE_NAME:-slate}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-washkinazy}"
ARG BUILD_NVIDIA="${BUILD_NVIDIA:-N}"

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY sys_files /sys_files
COPY just /just

# Get akmods from ublue-os (provides kernel RPMs and base akmods)
FROM ghcr.io/ublue-os/akmods:main-${FEDORA_VERSION} AS akmods

# Get nvidia akmods from ublue-os (always mount, conditionally use)
FROM ghcr.io/ublue-os/akmods-nvidia-open:main-${FEDORA_VERSION} AS akmods_nvidia

# Base Image - Fedora base-atomic
FROM quay.io/fedora-ostree-desktops/base-atomic:${FEDORA_VERSION}

ARG FEDORA_VERSION="${FEDORA_VERSION:-43}"
ARG IMAGE_NAME="${IMAGE_NAME:-slate}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-washkinazy}"
ARG BUILD_NVIDIA="${BUILD_NVIDIA:-N}"

# Labels
LABEL org.opencontainers.image.title="${IMAGE_NAME}"
LABEL org.opencontainers.image.description="Opinionated atomic desktop based on Fedora Silverblue"
LABEL org.opencontainers.image.vendor="${IMAGE_VENDOR}"
LABEL io.artifacthub.package.readme-url="https://github.com/${IMAGE_VENDOR}/slate-atomic/blob/main/README.md"

# Build image following main's pattern
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

# bootc lint
RUN ["bootc", "container", "lint"]
