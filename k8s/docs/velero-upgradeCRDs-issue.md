# Velero upgradeCRDs Job Issue - TLDR

## What is upgradeCRDs?

**Purpose:** A Helm hook job that installs/updates Velero CRDs (Custom Resource Definitions) before the main Velero deployment starts.

**Why it exists:**
- Helm installs CRDs on first deployment
- Helm **does NOT** update CRDs on upgrades (by design - too dangerous)
- `velero-upgrade-crds` job works around this limitation

## The Problem (ARM64 Compatibility)

**Job fails with:**
```
/tmp/sh: error while loading shared libraries: libreadline.so.8: cannot open shared object file
```

**Root cause:**
1. Job uses init container to copy `sh` and `kubectl` binaries
2. Bitnami kubectl image = Photon OS (different libc)
3. Velero container = Debian/distroless
4. Binary incompatibility → libraries don't match → crash

**Additional issues:**
- Bitnami kubectl lacks ARM64 support for specific version tags
- Rancher kubectl is also distroless (no `/bin/sh`)
- Velero image is distroless (no shell or kubectl)

## GitHub Issues

This is a **known widespread issue**:
- [Issue #559](https://github.com/vmware-tanzu/helm-charts/issues/559): Velero CRD upgrade job failures
- [Issue #4627](https://github.com/vmware-tanzu/velero/issues/4627): AMD64-only container breaks ARM
- [Issue #7462](https://github.com/vmware-tanzu/velero/issues/7462): GLIBC version mismatch
- [Issue #339](https://github.com/vmware-tanzu/helm-charts/issues/339): Request for multi-arch kubectl image

**Affects:** Anyone using ARM64 (Raspberry Pi, Mac M1/M2, ARM servers) or mismatched OS versions

## Our Solution

**Disable the problematic job** (k0sctl.yaml:164-165):
```yaml
velero:
  upgradeCRDs: false  # Disable the job
  cleanUpCRDs: false
```

**Why this works:**
- ✅ We're doing a **first install**, not an upgrade
- ✅ Helm automatically installs CRDs from the `crds/` directory on first install
- ✅ No job needed for initial deployment
- ⚠️ Future upgrades: Re-enable and fix kubectl image, OR manually apply CRD updates

## For Future Upgrades

When upgrading Velero version (e.g., 7.2.1 → 7.3.0):

**Option 1: Manually update CRDs**
```bash
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/helm-charts/main/charts/velero/crds/
```

**Option 2: Find ARM64-compatible kubectl image**
```yaml
kubectl:
  image:
    repository: <some-alpine-based-image>
    tag: <arm64-tag>
```

**Option 3: Keep upgradeCRDs disabled**
- CRDs rarely change between minor versions
- Check release notes for CRD changes
- Manually update only when necessary

## Key Takeaway

**CRD Management in Helm:**
- First install → Helm handles CRDs automatically ✅
- Upgrades → Helm skips CRDs (safety) → Job needed ⚠️
- Our case → First install → Job not needed → Disabled to avoid ARM64 bug ✅

## Related Files

- **k0sctl config**: `k8s/k0sctl.yaml` (lines 164-165)
- **CRD location**: Embedded in Velero Helm chart `crds/` directory
- **Applied to**: `/var/lib/k0s/manifests/velero/` on node
