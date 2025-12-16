#!/bin/bash
#
# Bug #2112373 Reproduction Test Script
# Flavor Extra Specs for SCSI Controller Model Not Honored for Volume Boot
#
# This script automates the reproduction of the bug where Nova ignores
# the hw:scsi_model flavor extra spec when booting instances from volumes.
#
# Prerequisites:
# - OpenStack cloud with Nova + Cinder configured
# - OpenStack CLI tools installed and configured (openstack, nova commands)
# - User has permissions to create flavors, volumes, and instances
# - SSH access to compute nodes for libvirt XML inspection
#
# Usage:
#   ./reproduce-test.sh [--cleanup]
#
# Options:
#   --cleanup    Delete test resources after completion
#

set -e

# Configuration
FLAVOR_NAME="test-scsi-flavor-bug2112373"
VOLUME_NAME="test-boot-volume-bug2112373"
INSTANCE_NAME="test-volume-boot-bug2112373"
NETWORK_NAME="${NETWORK_NAME:-private}"
IMAGE_NAME="${IMAGE_NAME:-cirros}"
VOLUME_SIZE=10
CLEANUP=false

# Parse arguments
if [[ "$1" == "--cleanup" ]]; then
    CLEANUP=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

bug_found() {
    echo -e "${RED}[BUG REPRODUCED]${NC} $1"
}

bug_not_found() {
    echo -e "${GREEN}[BUG NOT REPRODUCED]${NC} $1"
}

# Cleanup function
cleanup_resources() {
    info "Cleaning up test resources..."

    # Delete instance
    if openstack server show "$INSTANCE_NAME" &>/dev/null; then
        info "Deleting instance: $INSTANCE_NAME"
        openstack server delete "$INSTANCE_NAME" --wait || warning "Failed to delete instance"
    fi

    # Delete volume
    if openstack volume show "$VOLUME_NAME" &>/dev/null; then
        info "Deleting volume: $VOLUME_NAME"
        openstack volume delete "$VOLUME_NAME" || warning "Failed to delete volume"
        sleep 5  # Wait for volume deletion
    fi

    # Delete flavor
    if openstack flavor show "$FLAVOR_NAME" &>/dev/null; then
        info "Deleting flavor: $FLAVOR_NAME"
        openstack flavor delete "$FLAVOR_NAME" || warning "Failed to delete flavor"
    fi

    success "Cleanup complete"
}

# Trap to cleanup on exit if requested
if [[ "$CLEANUP" == true ]]; then
    trap cleanup_resources EXIT
fi

# Main test execution
main() {
    echo "================================================================="
    echo "    Bug #2112373 Reproduction Test"
    echo "    Flavor Extra Specs for SCSI Controller Model Not Honored"
    echo "================================================================="
    echo ""

    # Step 1: Create flavor with virtio-scsi
    info "[1/6] Creating flavor with hw:scsi_model=virtio-scsi..."

    if openstack flavor show "$FLAVOR_NAME" &>/dev/null; then
        warning "Flavor $FLAVOR_NAME already exists, deleting..."
        openstack flavor delete "$FLAVOR_NAME"
    fi

    openstack flavor create \
        --ram 2048 \
        --vcpus 2 \
        --disk 0 \
        "$FLAVOR_NAME"

    openstack flavor set "$FLAVOR_NAME" \
        --property hw:scsi_model=virtio-scsi \
        --property hw:disk_bus=scsi

    success "Flavor created"
    echo ""
    echo "Flavor configuration:"
    openstack flavor show "$FLAVOR_NAME" -f json | grep -A 10 properties || \
        openstack flavor show "$FLAVOR_NAME" | grep -A 5 properties
    echo ""

    # Step 2: Create bootable volume without image metadata
    info "[2/6] Creating bootable volume..."

    if openstack volume show "$VOLUME_NAME" &>/dev/null; then
        warning "Volume $VOLUME_NAME already exists, deleting..."
        openstack volume delete "$VOLUME_NAME"
        sleep 5
    fi

    # Get a base image
    IMAGE_ID=$(openstack image list -f value -c ID -c Name | grep -i "$IMAGE_NAME" | head -1 | awk '{print $1}')

    if [[ -z "$IMAGE_ID" ]]; then
        error "No image found matching '$IMAGE_NAME'. Please set IMAGE_NAME environment variable."
        exit 1
    fi

    info "Using image ID: $IMAGE_ID"

    # Create volume from image
    openstack volume create \
        --image "$IMAGE_ID" \
        --size "$VOLUME_SIZE" \
        --bootable \
        "$VOLUME_NAME"

    # Wait for volume to become available
    info "Waiting for volume to become available..."
    timeout 60 bash -c "while [[ \$(openstack volume show $VOLUME_NAME -f value -c status) != 'available' ]]; do sleep 2; done" || {
        error "Volume did not become available in time"
        exit 1
    }

    success "Volume created"
    echo ""

    # Check if volume has image metadata (this may affect the bug)
    info "Checking volume metadata..."
    VOLUME_META=$(openstack volume show "$VOLUME_NAME" -f json | grep -i image_metadata || echo "No image metadata")
    echo "$VOLUME_META"
    echo ""

    # Step 3: Boot instance from volume
    info "[3/6] Booting instance from volume..."

    if openstack server show "$INSTANCE_NAME" &>/dev/null; then
        warning "Instance $INSTANCE_NAME already exists, deleting..."
        openstack server delete "$INSTANCE_NAME" --wait
    fi

    openstack server create \
        --flavor "$FLAVOR_NAME" \
        --network "$NETWORK_NAME" \
        --volume "$VOLUME_NAME" \
        "$INSTANCE_NAME"

    # Wait for instance to become ACTIVE
    info "Waiting for instance to become ACTIVE..."
    timeout 120 bash -c "while [[ \$(openstack server show $INSTANCE_NAME -f value -c status) != 'ACTIVE' ]]; do sleep 3; done" || {
        error "Instance did not become ACTIVE in time"
        openstack server show "$INSTANCE_NAME"
        exit 1
    }

    success "Instance is ACTIVE"
    echo ""

    # Step 4: Find compute node and instance name
    info "[4/6] Locating instance on compute node..."

    COMPUTE_NODE=$(openstack server show "$INSTANCE_NAME" -f value -c OS-EXT-SRV-ATTR:host 2>/dev/null || \
                   openstack server show "$INSTANCE_NAME" -f value -c host 2>/dev/null || \
                   echo "unknown")

    INSTANCE_LIBVIRT_NAME=$(openstack server show "$INSTANCE_NAME" -f value -c OS-EXT-SRV-ATTR:instance_name 2>/dev/null || \
                            echo "unknown")

    if [[ "$COMPUTE_NODE" == "unknown" ]] || [[ "$INSTANCE_LIBVIRT_NAME" == "unknown" ]]; then
        warning "Could not determine compute node or libvirt instance name"
        warning "You may need admin privileges to see these attributes"
    fi

    success "Compute node: $COMPUTE_NODE"
    success "Libvirt instance name: $INSTANCE_LIBVIRT_NAME"
    echo ""

    # Step 5: Instructions for checking libvirt XML
    info "[5/6] Verification instructions..."
    echo ""
    echo "================================================================="
    echo "  To verify the bug, SSH to the compute node and run:"
    echo "================================================================="
    echo ""
    echo "  ssh $COMPUTE_NODE"
    echo "  sudo virsh dumpxml $INSTANCE_LIBVIRT_NAME | grep -A 5 \"controller type='scsi'\""
    echo ""
    echo "EXPECTED OUTPUT (correct behavior):"
    echo "  <controller type='scsi' index='0' model='virtio-scsi'>"
    echo ""
    echo "ACTUAL OUTPUT (BUG #2112373):"
    echo "  <controller type='scsi' index='0' model='lsilogic'>"
    echo ""
    echo "================================================================="
    echo ""

    # Step 6: Automated verification (if possible)
    info "[6/6] Attempting automated verification..."

    # Try to SSH to compute node and check (requires passwordless SSH)
    if [[ "$COMPUTE_NODE" != "unknown" ]] && [[ "$INSTANCE_LIBVIRT_NAME" != "unknown" ]]; then
        info "Attempting to retrieve libvirt XML from compute node..."

        if command -v ssh &>/dev/null; then
            SCSI_CONTROLLER=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$COMPUTE_NODE" \
                "sudo virsh dumpxml $INSTANCE_LIBVIRT_NAME 2>/dev/null | grep -A 2 \"controller type='scsi'\" | grep model" 2>/dev/null || echo "")

            if [[ -n "$SCSI_CONTROLLER" ]]; then
                echo "SCSI Controller configuration:"
                echo "$SCSI_CONTROLLER"
                echo ""

                if echo "$SCSI_CONTROLLER" | grep -q "model='virtio-scsi'"; then
                    bug_not_found "Controller model is 'virtio-scsi' (correct)"
                    echo "The bug is NOT present (or was already fixed)"
                elif echo "$SCSI_CONTROLLER" | grep -q "model='lsilogic'"; then
                    bug_found "Controller model is 'lsilogic' instead of 'virtio-scsi'"
                    echo "The flavor extra spec hw:scsi_model=virtio-scsi was IGNORED"
                else
                    warning "Controller model is neither virtio-scsi nor lsilogic"
                    echo "Unexpected controller: $SCSI_CONTROLLER"
                fi
            else
                warning "Could not retrieve SCSI controller information"
                info "Please check manually using the instructions above"
            fi
        else
            warning "SSH command not available for automated verification"
            info "Please check manually using the instructions above"
        fi
    else
        warning "Cannot perform automated verification"
        info "Please check manually using the instructions above"
    fi

    echo ""
    echo "================================================================="
    echo "  Test Summary"
    echo "================================================================="
    echo ""
    echo "Created resources:"
    echo "  - Flavor: $FLAVOR_NAME (hw:scsi_model=virtio-scsi)"
    echo "  - Volume: $VOLUME_NAME (bootable)"
    echo "  - Instance: $INSTANCE_NAME (booted from volume)"
    echo ""
    echo "To cleanup test resources, run:"
    echo "  $0 --cleanup"
    echo ""
    echo "Or manually delete:"
    echo "  openstack server delete $INSTANCE_NAME"
    echo "  openstack volume delete $VOLUME_NAME"
    echo "  openstack flavor delete $FLAVOR_NAME"
    echo ""
    echo "================================================================="
    echo "  For more information:"
    echo "  https://bugs.launchpad.net/nova/+bug/2112373"
    echo "================================================================="
}

# Run main test
main

exit 0
