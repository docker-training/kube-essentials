#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Run as the ubuntu user."
   exit 1
fi

# Verify kubectl is working
if ! kubectl get nodes &>/dev/null; then
    error "kubectl is not properly configured or cluster is not accessible"
    exit 1
fi

log "Starting NFS setup for k0s cluster with RWX support..."

# Step 1: Install NFS server on current node
log "Installing NFS server..."
sudo apt-get update -qq
sudo apt-get install -y nfs-kernel-server nfs-common

# Create NFS export directory
sudo mkdir -p /srv/nfs/k8s-storage
sudo chown nobody:nogroup /srv/nfs/k8s-storage
sudo chmod 755 /srv/nfs/k8s-storage

# Configure NFS exports
log "Configuring NFS exports..."
echo "/srv/nfs/k8s-storage *(rw,sync,no_subtree_check,no_root_squash,insecure)" | sudo tee /etc/exports

# Start and enable NFS server
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server
sudo exportfs -ra

# Get current node IP
NFS_SERVER_IP=$1
log "NFS server configured at: $NFS_SERVER_IP:/srv/nfs/k8s-storage"

# Step 2: Install NFS client on all nodes
log "Installing NFS client on all cluster nodes..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
    log "Installing NFS client utilities on node: $node"
    if [[ "$node" == "$NFS_SERVER_IP" ]]; then
        # Install on local server node
        sudo apt-get install -y nfs-common
        log "NFS client installed on local server node: $node"
    else
        # Install on remote worker nodes
        ssh -i ~/labkey -o StrictHostKeyChecking=no ubuntu@$node "sudo apt-get update -qq && sudo apt-get install -y nfs-common nfs-kernel-server" || warn "Failed to install NFS client on $node"
        log "NFS client installed on remote node: $node"
    fi

    # Verify mount.nfs helper is available
    if [[ "$node" == "$NFS_SERVER_IP" ]]; then
        if [[ -f /sbin/mount.nfs ]]; then
            log "✅ mount.nfs helper confirmed on local node: $node"
        else
            error "❌ mount.nfs helper missing on local node: $node"
        fi
    else
        ssh -i ~/labkey -o StrictHostKeyChecking=no ubuntu@$node "test -f /sbin/mount.nfs && echo 'mount.nfs helper confirmed on $node' || echo 'mount.nfs helper missing on $node'" || warn "Could not verify mount.nfs on $node"
    fi
done

# Step 3: Install NFS Subdir External Provisioner
log "Installing NFS Subdir External Provisioner for dynamic volume provisioning..."

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    error "Helm is required but not installed. Please install Helm first."
    exit 1
fi

# Add and update helm repository
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# Install the NFS provisioner
helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=$NFS_SERVER_IP \
  --set nfs.path=/srv/nfs/k8s-storage \
  --set storageClass.name=nfs-rwx \
  --set storageClass.defaultClass=true \
  --set storageClass.accessModes=ReadWriteMany \
  --set storageClass.reclaimPolicy=Delete \
  --set storageClass.allowVolumeExpansion=true \
  --set storageClass.mountOptions="{hard,nfsvers=4.1,timeo=600,retrans=2}" \
  --wait

# Step 4: Create a test PVC with RWX (no manual PV needed with dynamic provisioner)
log "Creating test PersistentVolumeClaim with RWX access mode for dynamic provisioning..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs-rwx-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: nfs-rwx
---
apiVersion: v1
kind: Pod
metadata:
  name: test-nfs-rwx-pod1
  namespace: default
spec:
  containers:
  - name: test-container
    image: nginx:alpine
    volumeMounts:
    - name: nfs-storage
      mountPath: /data
    command: ["/bin/sh"]
    args: ["-c", "echo 'Hello from pod1 at $(date)' > /data/test-file.txt && tail -f /dev/null"]
  volumes:
  - name: nfs-storage
    persistentVolumeClaim:
      claimName: test-nfs-rwx-pvc
---
apiVersion: v1
kind: Pod
metadata:
  name: test-nfs-rwx-pod2
  namespace: default
spec:
  containers:
  - name: test-container
    image: nginx:alpine
    volumeMounts:
    - name: nfs-storage
      mountPath: /data
    command: ["/bin/sh"]
    args: ["-c", "sleep 5 && cat /data/test-file.txt && echo 'Hello from pod2 at $(date)' >> /data/test-file.txt && tail -f /dev/null"]
  volumes:
  - name: nfs-storage
    persistentVolumeClaim:
      claimName: test-nfs-rwx-pvc
EOF

# Wait for test pods
log "Waiting for test pods to be ready..."
kubectl wait --for=condition=ready pod test-nfs-rwx-pod2 --timeout=120s

# Step 5: Verify installation
log "Verifying installation..."
echo
log "=== Cluster Nodes ==="
kubectl get nodes

echo
log "=== Storage Classes ==="
kubectl get sc

echo
log "=== Persistent Volumes (Dynamically Created) ==="
kubectl get pv

echo
log "=== Test PVC ==="
kubectl get pvc test-nfs-rwx-pvc

echo
log "=== Test Pods ==="
kubectl get pods test-nfs-rwx-pod1 test-nfs-rwx-pod2

echo
log "=== Testing RWX functionality ==="
sleep 5
log "Content from both pods (should show messages from both pod1 and pod2):"
kubectl exec test-nfs-rwx-pod2 -- cat /data/test-file.txt
kubectl exec test-nfs-rwx-pod1 -- cat /data/test-file.txt

echo
log "=== NFS Server Status ==="
sudo systemctl status nfs-kernel-server --no-pager -l

echo
log "=== NFS Exports ==="
sudo exportfs -v

# Clean up test resources
log "=== Cleaning up test resources ==="
kubectl delete pods test-nfs-rwx-pod1 test-nfs-rwx-pod2 --ignore-not-found=true
kubectl delete pvc test-nfs-rwx-pvc --ignore-not-found=true

echo
log "✅ Installation complete!"
log "📋 Summary:"
log "  - NFS server running on: $NFS_SERVER_IP:/srv/nfs/k8s-storage"
log "  - NFS Subdir External Provisioner installed with Helm"
log "  - StorageClass 'nfs-rwx' created with RWX support and dynamic provisioning"
log "  - Test PVC created and verified RWX functionality"
echo
log "📖 To create additional RWX volumes:"
log "  1. Create a PVC with accessModes: [ReadWriteMany]"
log "  2. Set storageClassName: nfs-rwx in your PVC"
log "  3. The provisioner will automatically create PVs as needed"
echo
log "🧹 To uninstall the NFS provisioner:"
log "  helm uninstall nfs-provisioner"
echo
log "✅ Dynamic NFS provisioning with RWX support is now ready for MSR deployment!"
