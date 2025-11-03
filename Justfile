export IMAGE_REGISTRY := env("IMAGE_REGISTRY", "ghcr.io")
export IMAGE_NAMESPACE := env("IMAGE_NAMESPACE", "washkinazy")
export FEDORA_VERSION := env("FEDORA_VERSION", "43")

[private]
default:
    @just --list

# Build slate base image
[group('Build')]
build-slate tag="latest":
    #!/usr/bin/bash
    set -eoux pipefail

    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "FEDORA_VERSION={{ FEDORA_VERSION }}")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=slate")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR={{ IMAGE_NAMESPACE }}")
    BUILD_ARGS+=("--build-arg" "BUILD_NVIDIA=N")

    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "localhost/slate:{{ tag }}" \
        --tag "{{ IMAGE_REGISTRY }}/{{ IMAGE_NAMESPACE }}/slate:{{ tag }}" \
        --file Containerfile \
        .

    echo "Built: localhost/slate:{{ tag }}"

# Build slate-nvidia-open image
[group('Build')]
build-slate-nvidia tag="latest":
    #!/usr/bin/bash
    set -eoux pipefail

    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "FEDORA_VERSION={{ FEDORA_VERSION }}")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=slate-nvidia-open")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR={{ IMAGE_NAMESPACE }}")
    BUILD_ARGS+=("--build-arg" "BUILD_NVIDIA=Y")

    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "localhost/slate-nvidia-open:{{ tag }}" \
        --tag "{{ IMAGE_REGISTRY }}/{{ IMAGE_NAMESPACE }}/slate-nvidia-open:{{ tag }}" \
        --file Containerfile \
        .

    echo "Built: localhost/slate-nvidia-open:{{ tag }}"

# Build all images
[group('Build')]
build-all tag="latest": (build-slate tag) (build-slate-nvidia tag)

# Clean build artifacts
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    rm -rf _build
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env

# Check Just syntax
[group('Utility')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
        echo "Checking syntax: $file"
        just --unstable --fmt --check -f "$file"
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just syntax
[group('Utility')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
        echo "Fixing syntax: $file"
        just --unstable --fmt -f "$file"
    done
    echo "Fixing syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Lint shell scripts
[group('Utility')]
lint:
    #!/usr/bin/bash
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck not found. Install it to lint shell scripts."
        exit 1
    fi
    find build_files -name "*.sh" -type f -exec shellcheck {} \;

# Generate sigstore signing keypair (run once) - supports cosign or skopeo
[group('Setup')]
generate-signing-key:
    #!/usr/bin/bash
    set -euo pipefail

    # Check if keys already exist
    if [ -f cosign.key ] || [ -f cosign.private ]; then
        echo "ERROR: Signing keys already exist!"
        echo "Remove them first if you want to generate new keys:"
        echo "  rm -f cosign.key cosign.private cosign.pub"
        exit 1
    fi

    # Check which tool is available
    HAS_COSIGN=false
    HAS_SKOPEO=false

    if command -v cosign &> /dev/null; then
        HAS_COSIGN=true
    fi

    if command -v skopeo &> /dev/null; then
        HAS_SKOPEO=true
    fi

    # Generate keys with whichever tool is available
    if [ "$HAS_COSIGN" = true ]; then
        echo "Generating sigstore keypair with cosign..."
        if ! COSIGN_PASSWORD="" cosign generate-key-pair; then
            echo ""
            echo "ERROR: Failed to generate keys!"
            exit 1
        fi
        PRIVATE_KEY="cosign.key"
    elif [ "$HAS_SKOPEO" = true ]; then
        echo "Generating sigstore keypair with skopeo..."
        if ! skopeo generate-sigstore-key --output-prefix cosign; then
            echo ""
            echo "ERROR: Failed to generate keys!"
            exit 1
        fi
        PRIVATE_KEY="cosign.private"
    else
        echo "ERROR: Neither cosign nor skopeo is installed!"
        echo ""
        echo "Install one of the following (either works):"
        echo "  Fedora: sudo dnf install cosign"
        echo "       or: sudo dnf install skopeo"
        echo ""
        echo "More info: https://blue-build.org/how-to/cosign/"
        exit 1
    fi

    # Verify keys were created (handle both possible private key names)
    if [ ! -f cosign.key ] && [ ! -f cosign.private ]; then
        echo ""
        echo "ERROR: Private key was not created successfully!"
        exit 1
    fi

    if [ ! -f cosign.pub ]; then
        echo ""
        echo "ERROR: Public key was not created successfully!"
        exit 1
    fi

    echo ""
    echo "✓ Sigstore keys generated successfully:"
    echo "  - $PRIVATE_KEY (PRIVATE - add to GitHub Secrets as SIGNING_SECRET)"
    echo "  - cosign.pub (PUBLIC - commit to repository)"
    echo ""
    echo "Next steps:"
    echo "  1. Add $PRIVATE_KEY to GitHub Secrets as SIGNING_SECRET:"
    echo "     With gh CLI:"
    echo "       gh secret set SIGNING_SECRET < $PRIVATE_KEY"
    echo "     OR via GitHub Web UI:"
    echo "       Settings → Secrets and variables → Actions → New secret"
    echo ""
    echo "  2. Commit the public key:"
    echo "       git add cosign.pub && git commit -m 'Add sigstore signing key'"
    echo ""
    echo "IMPORTANT: Never commit $PRIVATE_KEY to git!"

# Inspect a built image
[group('Utility')]
inspect image="slate" tag="latest":
    podman inspect localhost/{{ image }}:{{ tag }}

# Show image layers
[group('Utility')]
layers image="slate" tag="latest":
    podman history localhost/{{ image }}:{{ tag }}

# Run shell in image
[group('Utility')]
shell image="slate" tag="latest":
    podman run --rm -it localhost/{{ image }}:{{ tag }} /bin/bash
