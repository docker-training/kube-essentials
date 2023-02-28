# Initialize the cluster! 
sudo systemctl enable kubelet
# set token for easy reuse later:
token=$(kubeadm token generate)

#init kubernetes
sudo kubeadm init --token $token \
    --kubernetes-version 1.26.1 \
    --upload-certs \
    --apiserver-advertise-address $PrivateIP \
    --pod-network-cidr 192.168.0.0/16 \
    --cri-socket /run/cri-dockerd.sock 

# export config
export KUBECONFIG=/etc/kubernetes/admin.conf

# Get calico operator and custom resources
curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml -o calico-operator.yml
curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml -O
kubectl create -f calico-operator.yml
kubectl create -f custom-resources.yaml
