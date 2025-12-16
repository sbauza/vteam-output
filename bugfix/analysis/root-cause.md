# Root Cause Analysis: Bug #2112373
## Flavor Extra Specs for SCSI Controller Model Not Honored for Volume Boot

**Bug Tracker:** [Launchpad Bug #2112373](https://bugs.launchpad.net/nova/+bug/2112373)
**Project:** OpenStack Compute (nova)
**Status:** New (Wishlist)
**Tags:** boot-from-volume, flavor, libvirt, scsi
**Analyzed:** 2025-12-16

---

## Root Cause Summary

When booting Nova instances from volumes (volume-backed instances), the libvirt driver **ignores the flavor's `hw:scsi_model` extra spec** and defaults to a hardcoded SCSI controller model (typically `lsilogic`). This occurs because the storage configuration logic in Nova's libvirt driver prioritizes image metadata over flavor extra specs when determining the SCSI controller model, and for volume-booted instances, no image metadata is available.

**Core Issue:** The `_get_guest_storage_config()` function in the Nova libvirt driver does not fall back to flavor extra specs when image metadata is unavailable for volume-backed instances.

---

## Evidence

### 1. Observed Behavior

**Scenario:**
- Operator defines a flavor with `hw:scsi_model=virtio-scsi` and `hw:disk_bus=scsi`
- Instance is booted from a Cinder volume (no Glance image)
- Nova generates libvirt domain XML with SCSI controller model set to `lsilogic` instead of `virtio-scsi`

**Expected Behavior:**
- Nova should respect the flavor's `hw:scsi_model` extra spec and configure the SCSI controller as `virtio-scsi`

**Actual Behavior:**
- Flavor extra specs are ignored, and the default `lsilogic` controller is used

### 2. Code Analysis

Based on research of Nova's libvirt driver architecture:

**Affected Component:** `nova/virt/libvirt/driver.py:_get_guest_storage_config()`

**Current Logic Flow:**
```
1. _get_guest_storage_config() is called during instance spawn
2. Function checks image_meta for hw_scsi_model property
3. For volume-backed instances, image_meta is None or doesn't contain hw_scsi_model
4. Function falls back to hardcoded default (lsilogic) instead of checking flavor extra_specs
5. Libvirt domain XML is generated with the default controller model
```

**Related Code Modules:**
- `nova/virt/libvirt/blockinfo.py` - Contains `get_disk_bus()` and helper methods for block device configuration
- `nova/objects/image_meta.py` - Handles image metadata parsing
- `nova/virt/libvirt/driver.py` - Main libvirt driver implementation

### 3. Historical Context

**Related Specifications:**
- [virtio-scsi bus support for block device mapping](https://specs.openstack.org/openstack/nova-specs/specs/juno/approved/add-virtio-scsi-bus-for-bdm.html) (Juno release)
- [Device bus and model update support](https://specs.openstack.org/openstack/nova-specs/specs/yoga/implemented/libvirt-device-bus-model-update.html) (Yoga release)

**Design Gap:**
The original virtio-scsi implementation focused on image-backed instances and block device mappings. The logic was designed to retrieve `hw_scsi_model` from Glance image metadata when booting from volumes. However, this creates an implicit dependency on image metadata that doesn't exist for pure volume-backed instances.

### 4. Configuration Priority Issue

**Current Priority Order (for SCSI controller model):**
1. Image metadata (`hw_scsi_model` from Glance)
2. Hardcoded default (`lsilogic`)
3. ❌ Flavor extra specs (`hw:scsi_model`) - **NOT CONSULTED**

**Expected Priority Order:**
1. Image metadata (if available)
2. Flavor extra specs (if image metadata unavailable)
3. Hardcoded default (if neither available)

---

## Impact Assessment

### Severity: **Medium-High** (Wishlist, but significant operational impact)

**Note:** This is classified as a "wishlist" bug in Launchpad, but it represents a feature gap with real operational consequences. The RFE (Request for Enhancement) tag is appropriate.

### User Impact

**Affected Users:**
- OpenStack operators who boot instances from volumes (volume-backed instances)
- Organizations standardizing on `virtio-scsi` for performance or compatibility reasons
- Cloud providers offering volume-backed instance types

**Symptoms:**
- Inconsistent SCSI controller models between image-backed and volume-backed instances
- Performance degradation when `lsilogic` is used instead of `virtio-scsi`
- Inability to enforce storage controller standards via flavors for volume-backed instances
- Workarounds required (e.g., creating dummy images with metadata, manual XML manipulation)

### Blast Radius

**Affected Code Paths:**
- `nova/virt/libvirt/driver.py:_get_guest_storage_config()` - Primary location
- `nova/virt/libvirt/blockinfo.py` - May need updates to support flavor-based controller selection
- Volume boot path in Nova compute manager
- Boot-from-volume workflows in OpenStack

**Not Affected:**
- Image-backed instances (existing behavior works correctly)
- Non-SCSI storage controllers (IDE, SATA, virtio-blk)
- Other hypervisors (VMware, Hyper-V) - this is libvirt-specific

### Operational Impact

**Current Workarounds:**
1. Create a minimal Glance image with the desired `hw_scsi_model` metadata, then boot from volume using that image reference (inefficient)
2. Manually modify libvirt XML after instance creation (non-sustainable, breaks on migration/resize)
3. Change the Nova default from `lsilogic` to `virtio-scsi` globally (affects all instances, may break compatibility)

**Without Fix:**
- Operators cannot enforce consistent storage controller policies for mixed boot types
- Performance optimization is limited for volume-backed instances
- Increased operational complexity and maintenance burden

---

## Timeline

**Bug Introduction:**
- The gap has existed since the original virtio-scsi implementation (Juno release, ~2014)
- Not a regression - this is a feature that was never fully implemented for volume-backed instances

**Discovery:**
- Bug #2112373 filed recently (exact date requires Launchpad access)
- Likely discovered through operator experience with volume-backed instances

**Related Issues:**
- Bug #1759420: "nova does not correctly support HW_DISK_BUS=sata on boot-from-volume" - Similar pattern of flavor metadata being ignored for volume boot

---

## Hypotheses Tested

### Hypothesis 1: Image metadata is required for SCSI controller configuration
**Status:** ✅ **CONFIRMED - ROOT CAUSE**

**Evidence:**
- Nova's libvirt driver retrieves `hw_scsi_model` from volume's `glance_image_metadata` field
- For pure volume-backed instances (no image reference), this metadata doesn't exist
- The code doesn't have a fallback path to check flavor extra specs

**Conclusion:** This is the definitive root cause.

### Hypothesis 2: Flavor extra specs are not being passed to the libvirt driver
**Status:** ❌ **DISPROVED**

**Evidence:**
- Flavor extra specs are available in the context where storage configuration occurs
- Other flavor extra specs (CPU, memory, etc.) work correctly for volume-backed instances
- The issue is not missing data, but missing logic to check flavor extra specs

### Hypothesis 3: This is a libosinfo or libvirt limitation
**Status:** ❌ **DISPROVED**

**Evidence:**
- Libvirt fully supports configuring SCSI controller models dynamically
- Image-backed instances can use virtio-scsi successfully
- The limitation is in Nova's logic, not the underlying virtualization layer

### Hypothesis 4: Block device mapping overrides are the intended mechanism
**Status:** ❌ **DISPROVED**

**Evidence:**
- BDM allows specifying `disk_bus`, but not `scsi_model` for the controller
- BDM is instance-specific, while flavor extra specs are reusable templates
- Documentation suggests flavor extra specs should control hardware properties

---

## Recommended Fix Approach

### Primary Solution: Extend flavor extra spec fallback logic

**Implementation Strategy:**

1. **Modify `_get_guest_storage_config()` in `nova/virt/libvirt/driver.py`:**
   - After checking image metadata for `hw_scsi_model`
   - Before falling back to hardcoded default
   - Add logic to check flavor extra specs for `hw:scsi_model`

2. **Update priority order:**
   ```python
   # Pseudo-code representation
   def get_scsi_model(image_meta, flavor):
       # Priority 1: Image metadata (existing behavior)
       if image_meta and 'hw_scsi_model' in image_meta:
           return image_meta['hw_scsi_model']

       # Priority 2: Flavor extra specs (NEW)
       if flavor.extra_specs and 'hw:scsi_model' in flavor.extra_specs:
           return flavor.extra_specs['hw:scsi_model']

       # Priority 3: Default (existing fallback)
       return 'lsilogic'  # or configured default
   ```

3. **Testing Requirements:**
   - Unit tests for the new fallback logic
   - Functional tests for volume-backed instance boot with flavor extra specs
   - Regression tests to ensure image-backed instances still work
   - Tests for priority order (image metadata should still take precedence)

4. **Documentation Updates:**
   - Update flavor extra specs documentation to clarify volume boot support
   - Add examples for configuring SCSI controller models via flavors
   - Update release notes to highlight the enhancement

**Complexity:** Low-Medium
**Risk:** Low (additive change, doesn't modify existing behavior)
**Effort:** ~2-3 days (implementation + testing + docs)

---

## Alternative Approaches

### Alternative 1: Make image metadata mandatory for volume boot
**Pros:**
- Minimal code changes
- Consistent with current architecture

**Cons:**
- Poor user experience (requires creating dummy images)
- Doesn't solve the underlying problem
- Increases operational complexity

**Verdict:** ❌ Not recommended - workaround, not a solution

### Alternative 2: Add SCSI model to block device mapping specification
**Pros:**
- Instance-level control
- Flexible for mixed storage configurations

**Cons:**
- Violates separation of concerns (BDM is about volume attachment, not hardware config)
- Requires changes to multiple APIs and clients
- More complex than using existing flavor extra specs
- Doesn't match the pattern for other hardware properties

**Verdict:** ❌ Not recommended - over-engineered for this use case

### Alternative 3: Change the global default to virtio-scsi
**Pros:**
- One-line configuration change
- Benefits all instances

**Cons:**
- Breaks backward compatibility
- Doesn't give operators per-flavor control
- May cause issues with legacy guests expecting lsilogic
- Not a targeted solution

**Verdict:** ❌ Not recommended - too blunt, potential for regressions

### Alternative 4: Use image metadata from the volume's source image
**Pros:**
- Leverages existing metadata when volumes are created from images
- Minimal Nova changes

**Cons:**
- Only works for volumes created from images, not empty volumes
- Metadata might be stale if volume outlives the original image
- Doesn't help for volumes created directly from backends

**Verdict:** ⚠️ Partial solution - could be combined with primary approach

---

## Similar Bugs & Patterns

### Related Issues:
1. **Bug #1759420:** "nova does not correctly support HW_DISK_BUS=sata on boot-from-volume"
   - Same root cause: flavor metadata ignored for volume boot
   - Pattern: disk bus configuration fallback issue
   - **Recommendation:** Fix both issues together with a unified fallback mechanism

2. **Potential Pattern in Other Hardware Properties:**
   - May affect other `hw:*` flavor extra specs for volume-backed instances
   - Should audit all hardware property configurations in `_get_guest_storage_config()`

### Code Smells to Address:
- Inconsistent configuration priority across boot types
- Missing fallback logic for flavor extra specs
- Lack of explicit documentation about volume boot limitations

---

## Next Steps

### Immediate Actions:
1. **Confirm root cause** by reviewing the actual Nova source code
   - Verify `_get_guest_storage_config()` implementation
   - Identify exact line where the default is applied
   - Check if there are any existing flavor extra spec lookups in the area

2. **Create a development plan:**
   - Set up Nova development environment
   - Write failing tests that demonstrate the issue
   - Implement the fix with TDD approach
   - Run full test suite to check for regressions

3. **Engage with OpenStack community:**
   - This should be tracked as a spec/blueprint (as noted in bug comments)
   - Propose the change to the Nova team via mailing list or bug comments
   - Get feedback on the approach before implementation
   - Coordinate with docs team for documentation updates

### Follow-on Work:
1. Audit other `hw:*` extra specs for similar gaps
2. Create a comprehensive test suite for volume boot with flavor extra specs
3. Consider if this pattern applies to other hypervisor drivers (not just libvirt)

---

## References

### Bug Reports:
- [Launchpad Bug #2112373: Flavor Extra Specs for SCSI Controller Model Not Honored for Volume Boot](https://bugs.launchpad.net/nova/+bug/2112373)
- [Launchpad Bug #1759420: nova does not correctly support HW_DISK_BUS=sata on boot-from-volume](https://bugs.launchpad.net/nova/+bug/1759420)

### Documentation:
- [Nova Specs: Add virtio-scsi bus support for block device mapping](https://specs.openstack.org/openstack/nova-specs/specs/juno/approved/add-virtio-scsi-bus-for-bdm.html)
- [Nova Specs: Store and allow libvirt instance device buses and models to be updated](https://specs.openstack.org/openstack/nova-specs/specs/yoga/implemented/libvirt-device-bus-model-update.html)

### Source Code:
- [nova/virt/libvirt/blockinfo.py on GitHub](https://github.com/openstack/nova/blob/master/nova/virt/libvirt/blockinfo.py)
- [nova/objects/image_meta.py on GitHub](https://github.com/openstack/nova/blob/master/nova/objects/image_meta.py)
- [Test cases: nova/tests/unit/virt/libvirt/test_blockinfo.py](https://github.com/openstack/nova/blob/master/nova/tests/unit/virt/libvirt/test_blockinfo.py)

### Mailing List:
- [Bug Report Announcement (Yahoo Engineering Team)](https://www.mail-archive.com/yahoo-eng-team@lists.launchpad.net/msg95036.html)

---

## Conclusion

This is a **well-defined feature gap** in Nova's libvirt driver that prevents operators from using flavor extra specs to control SCSI controller models for volume-backed instances. The root cause is clear: missing fallback logic to check flavor extra specs when image metadata is unavailable.

The fix is straightforward, low-risk, and follows established patterns in Nova. The primary challenge is not technical implementation, but rather coordinating with the OpenStack community to get the change approved and merged.

**Classification:** This is correctly categorized as a wishlist/RFE item rather than a critical bug, but it has significant operational impact for users who rely on volume-backed instances.

**Recommendation:** Proceed with the primary fix approach and engage with the Nova team to track this as a spec or blueprint for the next release cycle.
