#!/bin/bash

# In order to run this script as intended, the following condtions must be true:
#    - node1 and node2 must have the private IPs of the lab environment set within the /etc/hosts
#    - script must be executed as the non-privileged ubuntu user context (sudo baked in script) 

# Checking if `sudo` is used with the shell command
if [[ $EUID -eq 0 ]]; then
   echo "This script must NOT be run as root!"
   echo "Try running as the ubuntu user instead..."
   exit 1
fi


create_NFS_service()
{

  # Installing NFS server packages
  DEBIAN_FRONTEND=noninteractive apt update
  DEBIAN_FRONTEND=noninteractive apt -yq install nfs-kernel-server rpcbind

  # Creating directory to share with cluster nodes
  mkdir /data
  chown -R nobody:nogroup /data
  chmod 777 /data

  # Exporting /data directory
  echo "/data  node1(rw,sync,no_subtree_check)" > /etc/exports
  echo "/data  node2(rw,sync,no_subtree_check)" >> /etc/exports
  exportfs -a

  # Restarting NFS server for sharing the /data directory over NFS
  systemctl restart nfs-kernel-server

}

create_NFS_mount () 
{

# Creating NFS Mount Point on worker nodes
for node in node1 node2
do
    scp /etc/hosts ubuntu@$node:~/
    ssh -t ubuntu@$node "sudo mv -f ~/hosts /etc/hosts && \
                         sudo DEBIAN_FRONTEND=noninteractive apt update && \
                         sudo DEBIAN_FRONTEND=noninteractive apt -yq install nfs-common && \
                         sudo mkdir -p /mnt/nfs_share && \
                         sudo mount control0:/data /mnt/nfs_share"
done
}

cat << EOS | sudo bash
$(declare -f create_NFS_service)
create_NFS_service
EOS

create_NFS_mount
