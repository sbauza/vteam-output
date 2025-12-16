# How to Apply the Bug #2112373 Fix

This guide explains how to apply the fix for Bug #2112373 to the OpenStack Nova codebase.

## Prerequisites

1. **Clone Nova repository:**
   ```bash
   git clone https://opendev.org/openstack/nova
   cd nova
   ```

2. **Set up development environment:**
   ```bash
   # Create virtual environment
   python3 -m venv .venv
   source .venv/bin/activate

   # Install dependencies
   pip install -r requirements.txt
   pip install -r test-requirements.txt

   # Install Nova in editable mode
   pip install -e .
   ```

3. **Create feature branch:**
   ```bash
   git checkout -b bugfix/2112373-flavor-scsi-model-volume-boot
   ```

## Step 1: Apply Core Fix

### File: `nova/virt/libvirt/driver.py`

**Option A: Manual Application**

1. Open `nova/virt/libvirt/driver.py` in your editor

2. Find the `_get_scsi_controller_model()` method (search for the method name)

3. Replace the entire method with the version from `driver.py.patch`:

```python
def _get_scsi_controller_model(self, image_meta, flavor):
    """Get SCSI controller model from image metadata or flavor extra specs.

    This function implements a priority-based configuration lookup:
    1. Image metadata (highest priority - for image-backed instances)
    2. Flavor extra specs (fallback - for volume-backed instances)
    3. Hardcoded default (last resort)

    Fix for Bug #2112373: Ensure flavor extra specs are honored when
    booting from volumes without image metadata.

    Args:
        image_meta: ImageMeta object containing image properties (may be None)
        flavor: Flavor object containing extra_specs dict

    Returns:
        str: SCSI controller model (e.g., 'virtio-scsi', 'lsilogic')

    Raises:
        None - always returns a valid model (falls back to default)
    """
    # Priority 1: Check image metadata (existing behavior, preserved)
    if image_meta and image_meta.properties:
        hw_scsi_model = image_meta.properties.get('hw_scsi_model')
        if hw_scsi_model:
            LOG.debug("Using SCSI controller model from image metadata: %s",
                     hw_scsi_model)
            return hw_scsi_model

    # Priority 2: Check flavor extra specs (NEW - Bug #2112373 fix)
    if flavor and flavor.extra_specs:
        # Note: Flavor extra specs use 'hw:scsi_model' (colon)
        # while image metadata uses 'hw_scsi_model' (underscore)
        hw_scsi_model = flavor.extra_specs.get('hw:scsi_model')
        if hw_scsi_model:
            LOG.debug("Using SCSI controller model from flavor extra specs: %s",
                     hw_scsi_model)
            return hw_scsi_model

    # Priority 3: Fall back to hardcoded default (existing behavior)
    default_model = 'lsilogic'
    LOG.debug("No SCSI controller model specified in image or flavor, "
             "using default: %s", default_model)
    return default_model
```

4. Find all call sites where `_get_scsi_controller_model()` is called

5. Update each call to pass the `flavor` parameter:

```python
# Before:
scsi_model = self._get_scsi_controller_model(image_meta)

# After:
scsi_model = self._get_scsi_controller_model(image_meta, flavor)
```

**Option B: Using Git Patch (if exact line numbers match)**

```bash
# Apply the patch
patch -p1 < ../artifacts/bugfix/fixes/driver.py.patch

# Check for conflicts
git status
```

**Note:** The patch file uses approximate line numbers. You may need to manually locate and update the code if your Nova version differs.

## Step 2: Apply Test Cases

### File: `nova/tests/unit/virt/libvirt/test_driver.py`

1. Open `nova/tests/unit/virt/libvirt/test_driver.py`

2. Add the new test class from `test_driver.py.patch` to the file:

```bash
# Append the test class to the file
# (See test_driver.py.patch for the complete TestSCSIControllerModel class)
```

Or manually copy the `TestSCSIControllerModel` test class to the appropriate location in the file.

## Step 3: Add Release Notes

### File: `releasenotes/notes/bug-2112373-flavor-scsi-model-volume-boot-<hash>.yaml`

1. Generate a random hash for the filename:
   ```bash
   HASH=$(openssl rand -hex 4)
   ```

2. Create the release note file:
   ```bash
   cp ../artifacts/bugfix/fixes/release-note.yaml \
      releasenotes/notes/bug-2112373-flavor-scsi-model-volume-boot-$HASH.yaml
   ```

## Step 4: Run Tests

### Unit Tests

```bash
# Run specific test class
tox -e py39 -- nova.tests.unit.virt.libvirt.test_driver.TestSCSIControllerModel

# Run all libvirt driver tests
tox -e py39 -- nova.tests.unit.virt.libvirt.test_driver

# Run full unit test suite (may take 30+ minutes)
tox -e py39
```

### Functional Tests

```bash
# Run libvirt functional tests
tox -e functional-py39 -- nova.tests.functional.libvirt

# Full functional test suite (may take hours)
tox -e functional-py39
```

### Code Quality

```bash
# Run PEP8 style checks
tox -e pep8

# Run linters
tox -e pylint
```

## Step 5: Verify the Fix

### Manual Verification (Optional)

If you have a DevStack or OpenStack development environment:

1. **Deploy the patched Nova:**
   ```bash
   # Copy files to Nova installation
   sudo cp nova/virt/libvirt/driver.py /usr/lib/python3/dist-packages/nova/virt/libvirt/
   sudo systemctl restart devstack@n-cpu
   ```

2. **Create test flavor:**
   ```bash
   openstack flavor create \
     --ram 2048 --vcpus 2 --disk 0 \
     test-virtio-scsi

   openstack flavor set test-virtio-scsi \
     --property hw:scsi_model=virtio-scsi \
     --property hw:disk_bus=scsi
   ```

3. **Create bootable volume:**
   ```bash
   openstack volume create \
     --image cirros-0.6.0 \
     --size 10 --bootable \
     test-boot-vol
   ```

4. **Boot instance from volume:**
   ```bash
   openstack server create \
     --flavor test-virtio-scsi \
     --network private \
     --volume test-boot-vol \
     test-instance
   ```

5. **Verify SCSI controller model:**
   ```bash
   # On compute node:
   sudo virsh dumpxml instance-XXXXXXXX | grep -A 5 "controller type='scsi'"

   # Expected output:
   # <controller type='scsi' index='0' model='virtio-scsi'>
   ```

## Step 6: Commit Changes

```bash
# Stage all changes
git add nova/virt/libvirt/driver.py
git add nova/tests/unit/virt/libvirt/test_driver.py
git add releasenotes/notes/bug-2112373-*.yaml

# Commit with proper format
git commit -m "Fix flavor extra specs for SCSI model on volume boot

When booting instances from volumes without image metadata, the
libvirt driver now honors the hw:scsi_model flavor extra spec
instead of falling back to the hardcoded default (lsilogic).

This allows operators to enforce consistent SCSI controller
standards for volume-backed instances via flavors, improving
performance (virtio-scsi) and operational flexibility.

Priority order for SCSI controller model configuration:
1. Image metadata (hw_scsi_model) - highest priority
2. Flavor extra specs (hw:scsi_model) - fallback
3. Hardcoded default (lsilogic) - last resort

Closes-Bug: #2112373
Change-Id: I$(git log -1 --format=%H | sha1sum | cut -c1-40)
"
```

## Step 7: Submit for Review

### OpenStack Gerrit Submission

1. **Set up Gerrit remote:**
   ```bash
   git remote add gerrit https://review.opendev.org/openstack/nova
   ```

2. **Install git-review:**
   ```bash
   pip install git-review
   git review -s
   ```

3. **Submit patch for review:**
   ```bash
   git review
   ```

4. **Monitor review:**
   - Visit https://review.opendev.org/
   - Watch for CI/CD results (Zuul)
   - Address reviewer feedback

### Alternative: GitHub Pull Request (Unofficial Mirror)

**Note:** OpenStack uses Gerrit, not GitHub PRs. This is for reference only.

```bash
git remote add github https://github.com/openstack/nova
git push github bugfix/2112373-flavor-scsi-model-volume-boot
```

Then create a PR on GitHub (but official review happens on Gerrit).

## Troubleshooting

### Test Failures

**Issue:** Unit tests fail with "AttributeError: 'Flavor' object has no attribute 'extra_specs'"

**Solution:** Ensure mock Flavor objects include `extra_specs`:
```python
flavor = objects.Flavor(extra_specs={'hw:scsi_model': 'virtio-scsi'})
```

### Import Errors

**Issue:** `ImportError: cannot import name 'LibvirtDriver'`

**Solution:** Ensure you're running tests from the Nova root directory and the virtual environment is activated.

### PEP8 Violations

**Issue:** `E501 line too long`

**Solution:** Break long lines:
```python
# Before:
LOG.debug("Using SCSI controller model from flavor extra specs: %s", hw_scsi_model)

# After:
LOG.debug("Using SCSI controller model from flavor extra specs: %s",
         hw_scsi_model)
```

### Merge Conflicts

**Issue:** Patch doesn't apply cleanly due to code changes

**Solution:** Manually apply the fix by:
1. Understanding the change (read implementation-notes.md)
2. Locating the equivalent code in your Nova version
3. Applying the same logical changes

## Rollback

If you need to undo the changes:

```bash
# Discard uncommitted changes
git reset --hard HEAD

# Or revert a committed change
git revert <commit-hash>
```

## Next Steps

After successful merge:

1. **Backporting:** Consider backporting to stable branches (discuss with Nova team)
2. **Documentation:** Update OpenStack user guide with examples
3. **Related Bugs:** Apply similar fix to Bug #1759420 (hw:disk_bus=sata)
4. **Follow-up:** Audit other hardware properties for similar issues

## Support

- **Bug Tracker:** https://bugs.launchpad.net/nova/+bug/2112373
- **Mailing List:** openstack-discuss@lists.openstack.org
- **IRC:** #openstack-nova on OFTC
- **Gerrit:** https://review.opendev.org/

---

**Last Updated:** 2025-12-16
**Status:** Ready for Application
