#!/bin/env bash

set -xe

DEBIAN_FRONTEND=noninteractive

# Set proxy
echo "Setting proxy"
export http_proxy=http://proxy.esl.cisco.com:80
export https_proxy=http://proxy.esl.cisco.com:80

echo "Successfully update Ubuntu packages"

# Update netplan
echo "Change interface name to enp1s0 in netplan config to facilitate dhcp ..."
sudo -E cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
if [ $? -ne 0 ]; then
  echo "Error: Failed to make backup of the current configuration file."
  exit 1
fi

# Replace ens3 with enp1s0 in the configuration file
sudo -E sed -i 's/ens3/enp1s0/g' /etc/netplan/00-installer-config.yaml
if [ $? -ne 0 ]; then
  echo "Error: Failed to update the configuration file."
  exit 1
fi

echo "Done"

# Update packages
echo "Update Ubuntu ..."
# sudo -E apt-get autoremove --purge
sudo -E apt-get -y update

# Install OpenSSH server
sudo -E apt-get install -y openssh-server
if [ $? -ne 0 ]; then
  echo "Error: Failed to install OpenSSH server."
  exit 1
fi

# Start the OpenSSH service
sudo -E systemctl start ssh
if [ $? -ne 0 ]; then
  echo "Error: Failed to start the OpenSSH service."
  exit 1
fi

# Enable the OpenSSH service to start on boot
sudo -E systemctl enable ssh
if [ $? -ne 0 ]; then
  echo "Error: Failed to enable the OpenSSH service to start on boot."
  exit 1
fi

echo "Successfully installed and configured the OpenSSH server."

# Install general dependencies
echo "Install required general dependencies ..."
if ! sudo -E apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq; then
    echo "Error: Failed to install general dependencies"
    exit 1
fi

echo "Done"

# Step 3: Install docker
echo "Installing docker and containerd"

# Remove all other versions of docker from your system
sudo -E dpkg --purge docker docker-engine docker.io containerd runc

# Add docker GPG key
if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo -E gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg; then
    echo "Error: Failed to add docker GPG key"
    exit 1
fi

# Add docker apt repository
if ! echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo -E tee /etc/apt/sources.list.d/docker.list; then
    echo "Error: Failed to add docker apt repository"
    exit 1
fi

# Fetch the package lists from docker repository
if ! sudo -E apt-get -y update; then
    echo "Error: Failed to fetch package lists from docker repository"
    exit 1
fi

# Install docker and containerd
if ! sudo -E apt-get install -y docker-ce docker-ce-cli containerd.io; then
    echo "Error: Failed to install docker and containerd"
    exit 1
fi

rm -f /etc/containerd/config.toml
sudo -E systemctl restart containerd

echo "Done"

# Step 4: Configure docker for kubeadm
echo "Configuring docker for kubeadm"

# Configure docker to use overlay2 storage and systemd
if ! sudo -E mkdir -p /etc/docker; then
    echo "Error: Failed to create /etc/docker directory"
    exit 1
fi

if ! echo '{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {"max-size": "100m"}
}' | sudo -E tee /etc/docker/daemon.json; then
    echo "Error: Failed to configure docker to use overlay2 storage and systemd"
    exit 1
fi

sudo -E systemctl stop docker

# Restart docker to load new configuration
if ! sudo -E systemctl start docker; then
    echo "Error: Failed to start docker"
    # exit 1
fi


# Add docker to start up programs
if ! sudo -E systemctl enable docker; then
    echo "Error: Failed to add docker to start up programs"
    exit 1
fi

# Allow current user access to docker command line
if ! sudo -E usermod -aG docker $USER; then
    echo "Error: Failed to provide user access to docker cli"
    exit 1
fi

echo "Done"

# Download cri-dockerd
#if ! curl -sSLo cri-dockerd_0.2.3.3-0.ubuntu-focal_amd64.deb \
# https://github.com/Mirantis/cri-dockerd/releases/download/v0.2.3/cri-dockerd_0.2.3.3-0.ubuntu-focal_amd64.deb; then
#    echo "Error: Failed to add cri-dockerd deb"
#    exit 1
#fi

# Install cri-dockerd for Kubernetes 1.24 support
#if ! sudo -E dpkg -i cri-dockerd_0.2.3.3-0.ubuntu-focal_amd64.deb; then
#    echo "Error: Failed to add cri-dockered"
#    exit 1
#fi

# Step 5: Install kubeadm, kubelet & kubectl
echo "Installing kubeadm, kubelet & kubectl"

# Add Kubernetes GPG key
if ! curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg; then
    echo "Error: Failed to add Kubernetes GPG key"
    exit 1
fi

# Add Kubernetes apt repository
if ! echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo -E tee /etc/apt/sources.list.d/kubernetes.list; then
    echo "Error: Failed to add Kubernetes apt repository"
    exit 1
fi

# Fetch package list
if ! sudo -E apt-get -y update; then
    echo "Error: Failed to fetch package list"
    exit 1
fi

# Install kubeadm, kubelet & kubectl
if ! sudo -E apt-get install -y kubelet kubeadm kubectl; then
    echo "Error: Failed to install kubeadm, kubelet & kubectl"
    exit 1
fi

echo "Done"

#Step 6: Ensure swap is disabled
echo "Checking Swap"
# Check if swap is enabled
swap_status=$(swapon --show)

if ! [ -z "$swap_status" ]; then
    echo "Swap is enabled, disabling..."

    # Turn off swap
    sudo -E swapoff -a;
    # Disable swap completely
    sudo -E sed -i -e '/swap/d' /etc/fstab;

    # Verify that swap is disabled
    swap_status=$(swapon --show)
    if ! [ -z "$swap_status" ]; then
        echo "Swap has been disabled successfully"
    else
        echo "Error: Failed to disable swap"
        exit 1
    fi
else
    echo "Swap is already disabled"
fi

echo "Done"

# Step 7: Create the cluster with kubeadm
echo "Creating the cluster with kubeadm"


if ! sudo -E kubeadm init --pod-network-cidr=10.244.0.0/16; then
    echo "Error: Failed to create the cluster with kubeadm"
    exit 1
fi

echo "Done"

# Step 8: Configure kubectl
echo "Configuring kubectl"

# Create kube directory
if ! mkdir -p $HOME/.kube; then
    echo "Error: Failed to create $HOME/.kube directory"
    exit 1
fi

# Copy admin.conf
if ! sudo -E cp -i /etc/kubernetes/admin.conf $HOME/.kube/config; then
    echo "Error: Failed to copy admin.conf"
    exit 1
fi

# Change ownership of config file
if ! sudo -E chown $(id -u):$(id -g) $HOME/.kube/config; then
    echo "Error: Failed to change ownership of $HOME/.kube/config"
    exit 1
fi

echo "Done"

# Step 9: Untaint node
echo "Untainting node"

# Untaint node
if ! kubectl taint nodes --all node.kubernetes.io/not-ready-; then
    echo "Error: Failed to untaint node"
    exit 1
fi

#Untaint node
if ! kubectl taint nodes --all node-role.kubernetes.io/control-plane-; then
    echo "Error: Failed to untaint node"
    exit 1
fi

echo "Done"


# Step 10: Install a CNI plugin
echo "Installing a CNI plugin"

# Install CNI plugin
if ! kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml; then
    echo "Error: Failed to install CNI plugin"
    exit 1
fi

echo "Done"

# Step 11: Install helm
echo "Installing helm"

# Download and install helm
if ! curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash; then
    echo "Error: Failed to install helm"
    exit 1
fi

echo "Done"

echo "Completed 0_initial_install script"
