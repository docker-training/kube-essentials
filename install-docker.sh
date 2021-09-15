#!/bin/bash -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Save input arguments for debug and diagnosis
echo "Running: $0 $@" >> .install.log

# Set defaults
#USER=${1:-$SUDO_USER}
DCKRV=${2:-5:20.10.8~3-0~ubuntu-bionic}

docker_install()
{
  apt update
  apt install -y apt-transport-https ca-certificates gnupg-agent software-properties-common curl
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
	  $(lsb_release -cs) \
	  stable"
  apt update
  apt install -y docker-ce=$DCKRV docker-ce-cli=$DCKRV containerd.io
}

docker_add_group()
{
    usermod -aG docker ubuntu
}

#docker_customize()
#{
    # Nice to have: make sure if dockerd is restarted it won't kill k8s
#    cat <<EOF >/etc/docker/daemon.json
#{
#  "live-restore": true,
#  "storage-driver": "overlay2"
#}
#EOF

 #   systemctl restart docker.service
 #  systemctl enable docker.service
#}

docker_install $DCKRV
docker_add_group
docker info
echo
echo "#################################"
echo "# Docker Installation complete #"
echo "#################################"
echo
