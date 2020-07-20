#!/bin/bash -e
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Save input arguments for debug and diagnosis
echo "Running: $0 $@" >> .install.log

# https://packages.cloud.google.com/apt/dists/kubernetes-xenial/main/binary-amd64/Packages
K8SCNI="0.8.6-00"
K8SVER="1.18.6-00"

# https://kubernetes.io/docs/setup/independent/install-kubeadm/
# -------------------------------------------------------------
install_k8s_tools()
{
    apt-get install -y apt-transport-https
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo deb http://apt.kubernetes.io/ kubernetes-xenial main | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubernetes-cni=${1}
    apt-get install -y kubeadm=${2} kubectl=${2} kubelet=${2} --allow-downgrades
    apt-mark hold kubelet kubeadm kubectl
    echo 'source <(kubectl completion bash)' | tee --append $HOME/.bashrc
    kubeadm version
    kubelet --version

# DEPRECATED: User customizing k8s installation for Heapster
#    cat <<EOF > /etc/default/kubelet
#KUBELET_EXTRA_ARGS="--read-only-port=10255"
#EOF
}


install_k8s_tools $K8SCNI $K8SVER
echo
echo "#############################################"
echo "# Kubernetes Components (v1.18.6) Installed #"
echo "#############################################"
echo