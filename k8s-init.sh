# Initialize the cluster! 
sudo systemctl enable kubelet

#init kubernetes
sudo kubeadm init --token-ttl 36h \
    --kubernetes-version 1.28.1 \
    --control-plane-endpoint=${PublicIP} \
    --pod-network-cidr 192.168.0.0/16

# export config
export KUBECONFIG=/etc/kubernetes/admin.conf

# Get calico operator and custom resources
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml -O
kubectl apoly -f calico.yaml