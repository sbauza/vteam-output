# Feature Specification: Nova IOThreads Support

**Feature Branch**: `001-nova-iothreads`
**Created**: 2025-12-15
**Status**: Draft
**Input**: User description: "Add IOThreads support to Nova compute service to enable I/O parallelization for virtualized guest instances. This feature will allow operators to configure dedicated I/O processing threads for virtual disk devices (virtio-blk and virtio-scsi) through flavor extra specs and image metadata. Implementation will follow a three-phase approach: Phase 1 focuses on basic IOThread support with automatic device assignment, Phase 2 adds CPU pinning and NUMA-aware placement integration, and Phase 3 provides advanced management and observability features. The feature targets QEMU/KVM hypervisor environments and aims to improve storage IOPS by 2-3x for I/O-intensive workloads while maintaining backward compatibility and graceful degradation for unsupported configurations."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Basic IOThread Configuration for High-Performance Workloads (Priority: P1)

As a cloud operator, I need to create instance flavors with IOThread support so that database administrators can deploy high-performance database instances that achieve better storage I/O throughput without understanding low-level virtualization details.

**Why this priority**: This is the foundation of the entire feature. Without basic IOThread configuration, none of the advanced capabilities matter. This delivers immediate value by enabling 2-3x IOPS improvements for storage-intensive workloads.

**Independent Test**: Can be fully tested by creating a flavor with IOThread configuration, launching an instance, and measuring storage IOPS improvements (30-300% increase expected). Delivers tangible performance value even without CPU pinning or advanced management.

**Acceptance Scenarios**:

1. **Given** a cloud operator managing OpenStack flavors, **When** they create a flavor with IOThread count specification, **Then** the flavor validates successfully and accepts the configuration
2. **Given** a flavor configured with 4 IOThreads, **When** a user launches an instance with that flavor, **Then** the instance is created with 4 dedicated I/O processing threads assigned to storage devices
3. **Given** an instance running with IOThreads enabled, **When** storage benchmarks are performed, **Then** IOPS measurements show 2-3x improvement compared to non-IOThread instances for high-concurrency workloads
4. **Given** a workload image with IOThread recommendations in metadata, **When** an instance is launched with that image and a compatible flavor, **Then** the IOThread configuration from both sources is properly merged

---

### User Story 2 - Automatic Compatibility Handling (Priority: P1)

As a cloud user, I need the system to automatically handle IOThread compatibility so that my instances launch successfully regardless of whether the hypervisor supports IOThreads, without requiring me to understand hypervisor capabilities.

**Why this priority**: Without graceful degradation, IOThread configuration would create operational fragility. Users shouldn't need to know which compute nodes support IOThreads. This is critical for mixed-version deployments and smooth rollouts.

**Independent Test**: Can be tested by attempting to launch IOThread-configured instances on both supported (QEMU 2.1+) and unsupported hypervisors. On unsupported systems, instances should launch normally with a warning logged, not fail.

**Acceptance Scenarios**:

1. **Given** a compute node running QEMU 2.0 (pre-IOThread support), **When** a user launches an instance with IOThread configuration, **Then** the instance launches successfully without IOThreads and a warning is logged
2. **Given** an instance with virtio-blk devices, **When** the instance is created with IOThread configuration, **Then** IOThreads are applied to compatible virtio devices
3. **Given** an instance with mixed device types (virtio-blk and IDE), **When** IOThreads are configured, **Then** only virtio devices receive IOThread assignment and incompatible devices use standard processing
4. **Given** a user attempting to create a flavor with IOThread configuration, **When** the configuration is validated, **Then** clear error messages indicate any invalid settings before instance creation

---

### User Story 3 - Instance Migration with IOThread Preservation (Priority: P2)

As a cloud operator, I need to migrate instances with IOThread configuration to different compute nodes so that I can perform maintenance and rebalancing without losing performance optimizations.

**Why this priority**: Instance migration is essential for operational flexibility, but it's not required for the basic value proposition. Users can get performance benefits from Phase 1 even without migration support initially.

**Independent Test**: Can be tested by live-migrating or cold-migrating an IOThread-enabled instance between compatible compute nodes and verifying that IOThread configuration is preserved and performance characteristics remain consistent.

**Acceptance Scenarios**:

1. **Given** an instance running with 4 IOThreads on compute node A, **When** the instance is migrated to compute node B (which supports IOThreads), **Then** the instance continues running with 4 IOThreads after migration
2. **Given** an instance with IOThreads on compute node A, **When** migration to compute node B is attempted but B doesn't support IOThreads, **Then** the migration is blocked with a clear error message explaining the incompatibility
3. **Given** an instance with IOThread configuration, **When** the instance is resized to a different flavor with different IOThread settings, **Then** the new IOThread configuration is applied after resize and reboot
4. **Given** multiple instances with IOThreads on a compute node, **When** resource availability is checked before migration, **Then** the scheduler correctly accounts for IOThread resource requirements on the target node

---

### User Story 4 - CPU Pinning and NUMA-Aware Placement (Priority: P3)

As a cloud operator deploying latency-sensitive applications, I need to pin IOThreads to specific CPU cores with NUMA locality so that I can minimize I/O latency and maximize cache efficiency for the highest-performance workloads.

**Why this priority**: This is an optimization on top of basic IOThreads. It provides an additional 15-20% performance benefit, but the major gains (2-3x IOPS) come from basic IOThreads in P1. This is for advanced use cases requiring absolute maximum performance.

**Independent Test**: Can be tested by creating a flavor with CPU pinning and IOThread pinning policies, launching an instance, and verifying that IOThreads are pinned to the specified CPU cores on the correct NUMA nodes. Performance testing should show reduced latency variance.

**Acceptance Scenarios**:

1. **Given** a flavor with dedicated CPU policy and IOThread CPU pinning enabled, **When** an instance is launched, **Then** IOThreads are assigned to dedicated CPU cores that don't overlap with guest vCPUs
2. **Given** a compute node with multiple NUMA nodes, **When** an instance with IOThreads is created, **Then** IOThread CPU cores are allocated from the same NUMA node as the guest vCPUs and storage controllers
3. **Given** a flavor specifying manual CPU affinity for IOThreads, **When** the instance is created, **Then** IOThreads are pinned to the exact CPU cores specified in the configuration
4. **Given** an instance with IOThread CPU pinning, **When** resource utilization is queried, **Then** the system correctly reports both vCPU and IOThread CPU allocations separately

---

### User Story 5 - IOThread Diagnostics and Observability (Priority: P3)

As a cloud operator troubleshooting performance issues, I need to view IOThread configuration and runtime statistics for instances so that I can validate that IOThreads are working as expected and identify I/O bottlenecks.

**Why this priority**: Observability is important for operations but not required for the feature to deliver value. Users can get performance benefits without detailed diagnostics. This enables advanced troubleshooting and optimization.

**Independent Test**: Can be tested by launching instances with IOThreads and querying diagnostic APIs to retrieve IOThread configuration, CPU affinity, device assignments, and runtime statistics. Validation doesn't require the feature to work - just accurate reporting.

**Acceptance Scenarios**:

1. **Given** an instance running with IOThreads, **When** an operator requests IOThread diagnostics, **Then** the system returns IOThread count, CPU affinity, and device-to-IOThread mappings
2. **Given** an instance with IOThreads processing I/O operations, **When** statistics are queried, **Then** the system provides per-IOThread metrics including operation counts and CPU time consumed
3. **Given** multiple instances on a compute node, **When** node resource usage is queried, **Then** IOThread CPU allocations are correctly reflected in resource accounting reports
4. **Given** an instance without IOThread support, **When** diagnostics are requested, **Then** the system clearly indicates that IOThreads are not configured or not supported

---

### Edge Cases

- What happens when an operator configures more IOThreads than available CPU cores on the compute node? (System should either reject the instance creation with clear error, or reduce IOThread count to available resources based on policy)
- How does the system handle migration when the target compute node has different NUMA topology from the source? (System should recalculate CPU pinning for the target topology while preserving IOThread count and configuration)
- What happens when a flavor specifies IOThread count but the image metadata conflicts with a different count? (System should use a defined precedence: flavor takes precedence over image metadata, with the merge documented)
- How does system handle resize from an IOThread-enabled flavor to a non-IOThread flavor? (IOThread configuration should be removed cleanly, with instance reboot required)
- What happens during live migration if I/O operations are in flight in IOThreads? (Migration should coordinate with QEMU to drain I/O operations before final cutover, similar to existing live migration)
- How does the system behave when QEMU/libvirt versions are upgraded on a compute node with running IOThread instances? (Running instances preserve their configuration; upgrade happens during normal maintenance windows)
- What happens if an operator specifies CPU pinning for IOThreads on a compute node with CPU overcommit enabled? (System should reject the configuration as incompatible - CPU pinning requires dedicated CPU policy)

## Requirements *(mandatory)*

### Functional Requirements

#### Phase 1: Basic IOThread Support

- **FR-001**: System MUST allow cloud operators to specify IOThread count in flavor extra specifications
- **FR-002**: System MUST validate IOThread configuration at flavor creation time, rejecting invalid values (e.g., negative counts, counts exceeding reasonable limits)
- **FR-003**: System MUST allow application vendors to specify recommended IOThread count in image metadata as workload hints
- **FR-004**: System MUST automatically assign virtual storage devices to available IOThreads using round-robin distribution when no manual mapping is specified
- **FR-005**: System MUST detect hypervisor IOThread capability at runtime by checking QEMU version (>= 2.1) and libvirt version (>= 1.2.8)
- **FR-006**: System MUST gracefully degrade when IOThread configuration is requested on incompatible hypervisors by launching instances without IOThreads and logging warnings
- **FR-007**: System MUST support IOThreads for virtio-blk and virtio-scsi device types only, ignoring configuration for incompatible device types
- **FR-008**: System MUST preserve IOThread configuration during instance migration between compatible compute nodes
- **FR-009**: System MUST validate target compute node IOThread capability before allowing migration of IOThread-enabled instances
- **FR-010**: System MUST generate appropriate hypervisor domain configuration (libvirt XML) including IOThread definitions and device assignments

#### Phase 2: CPU Pinning and NUMA Integration

- **FR-011**: System MUST allow operators to specify IOThread CPU pinning policy in flavor extra specifications (automatic or manual)
- **FR-012**: System MUST allocate dedicated CPU cores for IOThreads separately from guest vCPU cores when CPU pinning is enabled
- **FR-013**: System MUST coordinate IOThread CPU allocation with existing CPU pinning and NUMA topology management
- **FR-014**: System MUST ensure IOThread CPU cores are allocated from the same NUMA node as guest vCPUs when NUMA topology is specified
- **FR-015**: System MUST track IOThread CPU core allocation in the resource tracker, preventing double-allocation
- **FR-016**: System MUST account for IOThread CPU requirements in the scheduler when placing instances on compute nodes
- **FR-017**: System MUST recalculate IOThread CPU pinning for target NUMA topology during migration while preserving IOThread count
- **FR-018**: System MUST prevent IOThread CPU pinning when CPU overcommit is enabled, rejecting incompatible configurations

#### Phase 3: Advanced Management and Observability

- **FR-019**: System MUST provide diagnostic API endpoints to retrieve IOThread configuration for running instances
- **FR-020**: System MUST expose per-IOThread runtime statistics including I/O operation counts and CPU time consumed
- **FR-021**: System MUST allow operators to specify manual device-to-IOThread assignment for advanced optimization scenarios
- **FR-022**: System MUST support instance resize with IOThread reconfiguration, applying new settings after reboot
- **FR-023**: System MUST integrate IOThread metrics with telemetry systems for monitoring and alerting
- **FR-024**: System MUST provide clear documentation of IOThread configuration options, performance implications, and tuning guidelines

### Key Entities *(include if feature involves data)*

- **Flavor**: Represents an instance type configuration, extended with IOThread specifications (count, pinning policy, CPU affinity)
- **Image Metadata**: Contains workload hints including recommended IOThread configuration for optimal performance
- **IOThread Configuration**: Represents the IOThread settings for an instance including thread count, CPU assignments, and device mappings
- **Compute Node Capability**: Tracks hypervisor support for IOThreads based on QEMU and libvirt versions
- **Resource Allocation**: Represents CPU core assignments for both vCPUs and IOThreads, tracked separately to prevent conflicts
- **Device Assignment**: Maps virtual storage devices to specific IOThreads for I/O processing

## Success Criteria *(mandatory)*

### Measurable Outcomes

#### Performance

- **SC-001**: Storage-intensive workloads achieve 2-3x IOPS improvement when using IOThread-enabled instances compared to standard instances (measured with database benchmarks like pgbench, sysbench)
- **SC-002**: I/O latency P99 (99th percentile) is reduced by 40-60% under high load for IOThread-enabled instances
- **SC-003**: System supports at least 8 IOThreads per instance without performance degradation
- **SC-004**: IOThread CPU pinning provides an additional 15-20% latency reduction compared to unpinned IOThreads

#### Usability and Operations

- **SC-005**: Cloud operators can create and deploy IOThread-enabled flavors in under 5 minutes using standard OpenStack CLI tools
- **SC-006**: Instance launch time for IOThread-enabled instances is within 5% of standard instance launch time (no significant overhead)
- **SC-007**: 100% of instance migrations preserve IOThread configuration when target node is compatible
- **SC-008**: System provides clear error messages for all configuration failures, enabling operators to resolve issues without consulting documentation

#### Reliability and Compatibility

- **SC-009**: IOThread-configured instances launch successfully with 99.9% success rate on compatible hypervisors
- **SC-010**: System gracefully handles 100% of incompatible hypervisor scenarios without instance launch failures (graceful degradation)
- **SC-011**: Mixed deployments with both IOThread-capable and non-capable compute nodes operate without manual operator intervention
- **SC-012**: Zero data loss or corruption during migration of IOThread-enabled instances

#### Observability

- **SC-013**: Operators can retrieve complete IOThread diagnostic information (configuration, assignments, statistics) in under 2 seconds
- **SC-014**: Resource accounting correctly reflects IOThread CPU allocations with 100% accuracy, preventing resource exhaustion
- **SC-015**: Performance improvements are measurable through standard monitoring tools without specialized instrumentation

## Assumptions

### Technical Assumptions

1. **Hypervisor Support**: This feature targets QEMU/KVM hypervisors exclusively. Xen, VMware ESXi, and Hyper-V are not in scope.
2. **Minimum Versions**: Deployment environments will use QEMU 2.1+ and libvirt 1.2.8+ for IOThread support, or gracefully degrade on older versions.
3. **Storage Backend**: Maximum performance benefits require high-performance storage backends (NVMe, high-IOPS SAN). Standard spinning disks will show minimal improvement.
4. **Device Types**: Only virtio-blk and virtio-scsi devices benefit from IOThreads. Other device types (IDE, SATA, SR-IOV) are out of scope.

### Operational Assumptions

1. **Phased Rollout**: Implementation follows a three-phase approach, with each phase independently deployable and testable.
2. **Backward Compatibility**: Existing instances without IOThread configuration continue to function unchanged. This is an opt-in feature.
3. **Mixed Deployments**: Cloud environments may have compute nodes with varying IOThread capabilities during rollout periods.
4. **Resource Management**: Operators will properly size compute nodes with sufficient CPU cores to support both guest vCPUs and IOThreads when CPU pinning is used.

### Performance Assumptions

1. **Workload Characteristics**: Maximum benefits apply to high-concurrency, random I/O workloads (databases, distributed storage). Sequential I/O workloads see smaller improvements.
2. **IOThread Count**: Optimal IOThread count is typically 2-6 for most workloads. Beyond 8 IOThreads, benefits plateau due to storage backend limitations.
3. **CPU Overhead**: IOThreads shift the bottleneck from QEMU serialization to storage backend throughput. Fast storage is required for maximum benefit.

### Configuration Precedence

1. **Flavor vs. Image**: When both flavor and image specify IOThread configuration, flavor extra specs take precedence.
2. **Defaults**: If no IOThread configuration is specified, instances are created without IOThreads (existing behavior).
3. **Automatic Assignment**: Device-to-IOThread assignment uses automatic round-robin distribution unless manual mapping is explicitly configured (Phase 3).

## Dependencies

### External Dependencies

1. **QEMU/KVM**: Requires QEMU 2.1+ for IOThread support
2. **Libvirt**: Requires libvirt 1.2.8+ for IOThread configuration via domain XML
3. **virtio Drivers**: Guest operating systems must use virtio-blk or virtio-scsi drivers for storage devices

### Internal Dependencies (OpenStack Nova)

1. **Resource Tracker**: Phase 2 requires enhancements to track IOThread CPU allocations separately from vCPU allocations
2. **Scheduler**: Phase 2 requires scheduler awareness of IOThread CPU requirements for placement decisions
3. **CPU Pinning**: Phase 2 integrates with existing CPU pinning functionality (`hw:cpu_policy=dedicated`)
4. **NUMA Topology**: Phase 2 integrates with existing NUMA topology management for IOThread placement
5. **Libvirt Driver**: All phases require enhancements to the Nova libvirt driver for domain XML generation and capability detection

### Process Dependencies

1. **OpenStack Spec Proposal**: Feature requires OpenStack specification proposal and community review before implementation
2. **Documentation**: Operator documentation, configuration guides, and performance tuning recommendations must be created
3. **Testing**: Tempest integration tests and performance benchmarks must be developed
4. **Upgrade Path**: Mixed-version compatibility must be validated for rolling upgrades

## Out of Scope

### Explicitly Excluded

1. **Non-KVM Hypervisors**: Xen, VMware ESXi, Hyper-V, and other hypervisors are not supported
2. **Network IOThreads**: This feature focuses on storage I/O. Network device IOThread support is not included
3. **Runtime Reconfiguration**: Changing IOThread count or pinning for running instances without reboot is not supported (Phase 1-2)
4. **Automatic Tuning**: The system does not automatically determine optimal IOThread count based on workload profiling. Operators must configure explicitly.
5. **Guest OS Integration**: No guest operating system agents or tools are included. Performance improvements are transparent to the guest.
6. **Legacy Device Types**: IDE, SATA, and other non-virtio devices do not support IOThreads

### Future Enhancements (Post-MVP)

1. **SmartNIC Integration**: IOThreads with DPU/SmartNIC acceleration for offloaded I/O processing
2. **NVMe-oF Optimization**: Specialized IOThread configurations for NVMe over Fabrics
3. **Container Runtime Integration**: IOThread support for Kata Containers and container-optimized instances
4. **ML/AI Workload Profiles**: Pre-configured IOThread settings optimized for data-intensive training workloads
5. **Automatic Performance Analysis**: Telemetry-based recommendations for IOThread configuration based on observed workload patterns
6. **Live Reconfiguration**: Hot-add/remove IOThreads without instance reboot (if future QEMU versions support)
