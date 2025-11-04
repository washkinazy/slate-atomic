# GitHub Workflows Documentation

This document explains the automated CI/CD workflows for slate-atomic.

## Overview

slate-atomic uses a **hybrid workflow strategy** combining:
- **Path filtering** for code changes (skip non-build file changes)
- **Smart detection** for upstream image updates (detect Fedora/akmods changes)

This approach minimizes CI usage while keeping images current with upstream security updates.

## Workflows

### 1. `build.yml` - Build on Code Changes

**Purpose:** Build and publish images when repository code changes

**Triggers:**
- Push to `main` branch (with path filtering)
- Pull requests to `main` (with path filtering)
- Manual workflow dispatch

**Path Filtering:**
Only triggers when these files change:
- `Containerfile`
- `build_files/**`
- `sys_files/**`
- `just/**`
- `.github/workflows/**`
- `Justfile`

**Jobs:**
1. **validate** - Fast validation checks
   - Check for accidentally committed secrets
   - Lint Containerfile with hadolint
   - Lint shell scripts with shellcheck
   - Validate Just syntax
2. **build** - Build both image variants (slate, slate-nvidia-open)
3. **check** - Verify all builds succeeded

**Publishing:**
- Only publishes on push to `main` (not on PRs)
- Signs images with cosign
- Verifies signatures

### 2. `update-check.yml` - Check for Upstream Updates

**Purpose:** Detect and rebuild when upstream images update (Fedora, akmods, nvidia)

**Triggers:**
- Schedule: Daily at 6 AM UTC
- Manual workflow dispatch

**Jobs:**
1. **check-upstream** - Smart detection
   - Fetches current digests from upstream images
   - Compares with stored digests in `image-versions.yaml`
   - Determines if rebuild is needed
2. **build** - Builds images if upstream changed
3. **update-versions-file** - Commits updated `image-versions.yaml` to repo
4. **check** - Verify workflow succeeded

**Publishing:**
- Always publishes when it builds (no PR context)
- Signs images with cosign
- Verifies signatures

## Workflow Behavior Matrix

| Trigger | Path/Detection | Builds? | Publishes? | Example |
|---------|----------------|---------|------------|---------|
| **PR: README.md changed** | Path filter → Skip | No | No | Doc fixes don't waste CI time |
| **PR: Containerfile changed** | Path filter → Match | Yes | No | Test build before merge |
| **PR: build_files/ changed** | Path filter → Match | Yes | No | Validate build changes |
| **Push to main: just/ changed** | Path filter → Match | Yes | Yes | Deploy sjust recipe changes |
| **Push to main: README.md changed** | Path filter → Skip | No | No | Skip rebuild for docs |
| **Push to main: LICENSE changed** | Path filter → Skip | No | No | Skip rebuild for non-code |
| **Daily schedule: No upstream changes** | Smart detection → Skip | No | No | Save CI time |
| **Daily schedule: Fedora updated** | Smart detection → Changed | Yes | Yes | Auto-deploy security updates |
| **Daily schedule: Akmods updated** | Smart detection → Changed | Yes | Yes | Auto-deploy kernel updates |
| **Daily schedule: Nvidia drivers updated** | Smart detection → Changed | Yes | Yes | Auto-deploy driver updates |
| **Manual trigger: build.yml** | Always | Yes | No* | Test build manually |
| **Manual trigger: update-check.yml** | Always | Yes | Yes | Force rebuild with publish |

\* Manual trigger on `build.yml` only publishes if triggered from `main` branch

## Image Variants

Both workflows build two image variants:

| Variant | BUILD_NVIDIA | Contents |
|---------|--------------|----------|
| **slate** | N | Base GNOME image on Fedora Silverblue 43 |
| **slate-nvidia-open** | Y | slate + Nvidia open drivers (Turing+ GPUs) |

## Publishing Behavior

### build.yml
```
Push to main + code change → Publish
PR + code change           → Build only (no publish)
Manual from main           → Publish
Manual from branch         → Build only (no publish)
```

### update-check.yml
```
Always publishes when it builds (runs on schedule or manual trigger only)
```

## Smart Detection Details

### Tracked Upstream Images

`image-versions.yaml` tracks digests for:

1. **Fedora Silverblue 43**
   - Source: `quay.io/fedora/fedora-silverblue:43`
   - Contains: Base Fedora system, GNOME desktop

2. **ublue-os Akmods**
   - Source: `ghcr.io/ublue-os/akmods:main-43`
   - Contains: Kernel modules, signed kernel

3. **ublue-os Nvidia Akmods**
   - Source: `ghcr.io/ublue-os/akmods-nvidia-open:main-43`
   - Contains: Nvidia open kernel modules, drivers

### How Smart Detection Works

1. Daily at 6 AM UTC, `update-check.yml` runs
2. Fetches current digest (SHA256 hash) from each upstream image
3. Compares with stored digests in `image-versions.yaml`
4. If any digest changed:
   - Builds both image variants
   - Publishes to ghcr.io
   - Signs with cosign
   - Updates `image-versions.yaml` via commit
5. If no digests changed:
   - Workflow completes in ~30 seconds
   - No build triggered

### What Triggers Upstream Changes

- **Fedora releases security updates** → Base digest changes
- **New kernel version in Fedora** → Akmods rebuilds → Akmods digest changes
- **Nvidia releases new drivers** → Nvidia akmods rebuilds → Nvidia digest changes
- **ublue-os updates akmods packages** → Digest changes

## Validation Checks (build.yml only)

Fast checks that run before building:

1. **Secrets check** - Ensures no private keys committed
2. **Containerfile lint** - hadolint validation
3. **Shell script lint** - shellcheck on all .sh files
4. **Just syntax** - Validates Justfile and .just recipes

If validation fails → Build is skipped

## Registry and Signing

**Registry:** `ghcr.io/washkinazy`

**Images:**
- `ghcr.io/washkinazy/slate:latest`
- `ghcr.io/washkinazy/slate-nvidia-open:latest`

**Signing:**
- All published images are signed with cosign
- Public key: `cosign.pub` (in repository root)
- Private key: `SIGNING_SECRET` (GitHub secret)
- Signatures verified after signing

## Concurrency

Both workflows use concurrency groups to prevent conflicts:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref || github.run_id }}
  cancel-in-progress: true
```

- Multiple runs of same workflow on same branch → Cancel older run
- Prevents wasted CI time on rapid pushes

## Manual Workflow Triggers

### To manually test a build without publishing:
1. Go to Actions → "Build on code changes"
2. Click "Run workflow"
3. Select your branch
4. Images will build but not publish (unless on `main`)

### To force rebuild and publish (e.g., after fixing workflow):
1. Go to Actions → "Check for upstream updates"
2. Click "Run workflow"
3. Select `main` branch
4. Images will always build and publish

## Monitoring

### Check if upstream changed recently:
```bash
# View image-versions.yaml history
git log -p image-versions.yaml
```

### Check current upstream digests manually:
```bash
# Fedora Silverblue
skopeo inspect docker://quay.io/fedora/fedora-silverblue:43 | jq -r .Digest

# Akmods
skopeo inspect docker://ghcr.io/ublue-os/akmods:main-43 | jq -r .Digest

# Nvidia Akmods
skopeo inspect docker://ghcr.io/ublue-os/akmods-nvidia-open:main-43 | jq -r .Digest
```

## Files Modified by Workflows

| File | Modified By | When | Purpose |
|------|-------------|------|---------|
| `image-versions.yaml` | update-check.yml | After detecting upstream changes | Track upstream digests for next comparison |

## Related Documentation

- [BUILD.md](../BUILD.md) - Build process details
- [README.md](../README.md) - User documentation
