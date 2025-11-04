#!/usr/bin/bash

set -ouex pipefail

# Load COPR helper functions
#shellcheck source=build_files/copr-helpers.sh
source /ctx/copr-helpers.sh

PACKAGES_YAML="/ctx/packages.yaml"

# Validate packages.yaml exists and is valid YAML
if [[ ! -f "$PACKAGES_YAML" ]]; then
    echo "ERROR: packages.yaml not found at $PACKAGES_YAML"
    exit 1
fi

# Test that yq can parse the file (try to read any key)
if ! yq eval '.' "$PACKAGES_YAML" >/dev/null 2>&1; then
    echo "ERROR: packages.yaml contains syntax errors and cannot be parsed"
    yq eval '.' "$PACKAGES_YAML" 2>&1 || true
    exit 1
fi

echo "Installing packages from packages.yaml..."

# ============================================================================
# FEDORA PACKAGES (installed first, safe from COPR injection)
# ============================================================================

FEDORA_PACKAGES=()

# Add packages for all versions
if yq -e '.fedora_packages.all' "$PACKAGES_YAML" >/dev/null 2>&1; then
    readarray -t ALL_PKGS < <(yq -r '.fedora_packages.all[]' "$PACKAGES_YAML")
    FEDORA_PACKAGES+=("${ALL_PKGS[@]}")
fi

# Add version-specific packages
VERSION_KEY="version_${FEDORA_VERSION}"
if yq -e ".fedora_packages.${VERSION_KEY}" "$PACKAGES_YAML" >/dev/null 2>&1; then
    readarray -t VERSION_PKGS < <(yq -r ".fedora_packages.${VERSION_KEY}[]" "$PACKAGES_YAML")
    FEDORA_PACKAGES+=("${VERSION_PKGS[@]}")
fi

# Install Fedora packages in bulk
if [[ "${#FEDORA_PACKAGES[@]}" -gt 0 ]]; then
    echo "Installing ${#FEDORA_PACKAGES[@]} packages from Fedora repos..."
    dnf5 -y install "${FEDORA_PACKAGES[@]}"
else
    echo "No Fedora packages to install."
fi

# ============================================================================
# COPR PACKAGES (installed with isolated repo enablement)
# ============================================================================

if yq -e '.copr_packages' "$PACKAGES_YAML" >/dev/null 2>&1; then
    echo "Installing COPR packages with isolated repo enablement..."

    # Get list of COPR repo names
    readarray -t COPR_REPOS < <(yq -r '.copr_packages | keys[]' "$PACKAGES_YAML")

    for copr in "${COPR_REPOS[@]}"; do
        # Get packages for this COPR
        readarray -t COPR_PKGS < <(yq -r ".copr_packages[\"$copr\"][]" "$PACKAGES_YAML")

        if [[ "${#COPR_PKGS[@]}" -gt 0 ]]; then
            copr_install_isolated "$copr" "${COPR_PKGS[@]}"
        fi
    done
else
    echo "No COPR packages to install."
fi

# ============================================================================
# THIRD-PARTY REPOSITORIES
# ============================================================================

if yq -e '.third_party_repos' "$PACKAGES_YAML" >/dev/null 2>&1; then
    echo "Installing third-party repository packages..."

    # Get list of third-party repo names
    readarray -t THIRDPARTY_REPOS < <(yq -r '.third_party_repos | keys[]' "$PACKAGES_YAML")

    for repo in "${THIRDPARTY_REPOS[@]}"; do
        # Get repo URL
        REPO_URL=$(yq -r ".third_party_repos[\"$repo\"].url" "$PACKAGES_YAML")

        # Get packages for this repo
        readarray -t REPO_PKGS < <(yq -r ".third_party_repos[\"$repo\"].packages[]" "$PACKAGES_YAML")

        if [[ "${#REPO_PKGS[@]}" -gt 0 ]]; then
            repo_add_and_install "$repo" "$REPO_URL" "${REPO_PKGS[@]}"
        fi
    done
else
    echo "No third-party repositories to install."
fi

# ============================================================================
# PACKAGE EXCLUSIONS
# ============================================================================

if yq -e '.exclude' "$PACKAGES_YAML" >/dev/null 2>&1; then
    readarray -t EXCLUDED_PACKAGES < <(yq -r '.exclude[]' "$PACKAGES_YAML")

    if [[ "${#EXCLUDED_PACKAGES[@]}" -gt 0 ]]; then
        # Check which excluded packages are actually installed
        readarray -t INSTALLED_EXCLUDED < <(rpm -qa --queryformat='%{NAME}\n' "${EXCLUDED_PACKAGES[@]}" 2>/dev/null || true)

        if [[ "${#INSTALLED_EXCLUDED[@]}" -gt 0 ]]; then
            echo "Removing ${#INSTALLED_EXCLUDED[@]} excluded packages..."
            dnf5 -y remove "${INSTALLED_EXCLUDED[@]}"
        else
            echo "No excluded packages found to remove."
        fi
    fi
else
    echo "No packages to exclude."
fi

echo "Package installation complete."
