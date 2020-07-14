#!/bin/bash -e
# https://docs.docker.com/config/daemon/

: ${USE_SUDO:="true"}

#if [[ $EUID -ne 0 ]]; then
#   echo "This script must be run as root" 
#   exit 1
#fi

# Save input arguments for debug and diagnosis
echo "Running: $0 $@" >> .install.log

# runs the given command as root (detects if we are root already)
runAsRoot () {
    local CMD="$*"

    if [ $EUID -ne 0 -a $USE_SUDO = "true" ] ; then
      CMD="sudo $CMD"
    fi

    $CMD
}

# Set defaults
USER=${1:-$SUDO_USER}
DCKRV=${2:-19.03.6-0ubuntu1~18.04.1}

# These instruction only work on Ubuntu Bionic.
# Tested with:
# ncal imageId: "ami-077626d8853156c6a"
# Minimal Ubuntu 18.04 LTS - Bionic
# https://aws.amazon.com/marketplace/pp/B07J5RRYGN
docker_install()
{
  apt update
  apt install -y docker.io=${2}
  docker version
  apt-cache madison docker
}

docker_add_group()
{
    getent group docker || groupadd docker
    id | grep -q docker || usermod -aG docker ${1}
    docker version
}

docker_customize()
{
    # Nice to have: make sure if dockerd is restarted it won't kill k8s
    cat <<EOF >/etc/docker/daemon.json
{
  "live-restore": true,
  "storage-driver": "overlay2"
}
EOF

    systemctl restart docker.service
    systemctl enable docker.service
}

runAsRoot docker_install $DCKRV
runAsRoot docker_add_group $USER
#docker_customize
docker info