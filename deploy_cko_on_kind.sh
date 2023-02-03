#!/bin/env bash

set -xe

DEBIAN_FRONTEND=noninteractive

# To be defined by the user
REPO="https://github.com/test/example"
DIR="demo-cluster"
BRANCH_NAME="test"
GITHUB_PAT="dfkjdsanfknjsdakfndsafckajsnflnas"
GIT_USER="networkoperator-gittest"
GIT_EMAIL="test@cisco.com"
SYSTEM_ID="sysID"
#delete proxy variables, if no proxy is present
HTTP_PROXY=<ip:port>
HTTPS_PROXY=<ip:port>
NO_PROXY=<no-proxy>
VALUES_YAML_CKO=/path/to/values.yaml

#cluster
pod_cidr=10.244.0.0/16
api_server=$(ip addr show | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | tr '\n' ',' | sed 's/,$//')
HOSTNAME=$(hostname)

# Set proxy
check_proxy_vars() {
  if [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ]; then
    return 0 # true
  else
    return 1 # false
  fi
}

if check_proxy_vars; then
   export http_proxy=$HTTP_PROXY
   export https_proxy=$HTTPS_PROXY
   export no_proxy=$api_server,$pod_cidr,$NO_PROXY
fi


check_secret_vars() {
  if [ -n "$REPO" ] || [ -n "$DIR" ] || [ -n "$BRANCH_NAME" ] || [ -n "$GITHUB_PAT" ] || [ -n "$GIT_USER" ] || [ -n "$GIT_EMAIL" ] | [ -n "$SYSTEM_ID" ]; then
    return 0 # true
  else
    echo "some or all env variables required to configure cko resources are missing"
    return 1 # false
  fi
}

# Update packages
echo "Update Ubuntu ..."
# sudo -E apt-get autoremove --purge
sudo -E apt-get -y update

# Install general dependencies
echo "Install required general dependencies ..."
if ! sudo -E apt-get install -y apt-transport-https ca-certificates curl gnupg2 lsb-release jq iptables software-properties-common; then
    echo "Error: Failed to install general dependencies"
    exit 1
fi

echo "Done"

#Step 3: Ensure swap is disabled
echo "Disable swap, firewall and load netfilter framework to linux kernal"
sudo -E swapoff -a
sudo -E systemctl disable --now ufw
sudo -E modprobe br_netfilter
sudo -E sysctl -p /etc/sysctl.conf

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
if ! sudo -E apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
    echo "Error: Failed to install docker and containerd"
    exit 1
fi

#rm -f /etc/containerd/config.toml
#sudo -E systemctl restart containerd


echo "Set docker proxy"
# Create required dirs
mkdir -p /etc/systemd/system/docker.service.d

# add proxy
if check_proxy_vars; then
    sudo -E echo -e "[Service]\nEnvironment=HTTP_PROXY=${http_proxy}\nEnvironment=HTTPS_PROXY=${https_proxy}\nEnvironment=NO_PROXY=${no_proxy}" > /etc/systemd/system/docker.service.d/http-proxy.conf
fi

sudo -E systemctl daemon-reload
sudo -E systemctl restart docker

echo "Done"

# Step 5: Install Kind
echo "Installing Kind"

curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.16.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind


# Step 6: Install kubelet & kubectl
echo "Installing  kubelet & kubectl"

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
if ! sudo -E apt-get install -y kubelet kubectl; then
    echo "Error: Failed to install kubeadm, kubelet & kubectl"
    exit 1
fi

echo "Done"


# Step 7: Create the cluster with kind

kind create cluster --name control-cluster

#sudo -E systemctl daemon-reload
#sudo -E systemctl restart docker
#sudo -E systemctl restart kubelet

# Step 8: Untaint node
echo "Untainting node"

# Untaint node
if ! kubectl taint nodes --all node.kubernetes.io/not-ready-; then
    echo "Error: Failed to untaint node"
    exit 1
fi

echo "Done"


# Step 9: Install helm
echo "Installing helm"

# Download and install helm
if ! curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash; then
    echo "Error: Failed to install helm"
    exit 1
fi

echo "Done"

echo "Completed single node cluster setup"


# Step 10: Install cko control cluster
echo "Installing CKO Control cluster"

if check_secret_vars; then
    sudo -E helm repo add jetstack https://charts.jetstack.io
    sudo -E helm repo update
    sudo -E helm install \
    cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.10.0 \
    --set installCRDs=true \
    --wait

    sudo -E kubectl create ns netop-manager

    sudo -E kubectl create secret generic cko-config -n netop-manager \
    --from-literal=repo=$REPO \
    --from-literal=dir=$DIR \
    --from-literal=branch=$BRANCH_NAME \
    --from-literal=token=$GITHUB_PAT \
    --from-literal=user=$GIT_USER \
    --from-literal=email=$GIT_EMAIL \
    --from-literal=systemid=$SYSTEM_ID \
    --from-literal=http_proxy=$HTTP_PROXY \
    --from-literal=https_proxy=$HTTPS_PROXY \
    --from-literal=no_proxy=$NO_PROXY,10.96.0.1,.netop-manager.svc,.svc,.cluster.local,localhost,127.0.0.1,10.96.0.0/16,10.244.0.0/16,control-cluster-control-plane,.svc,.svc.cluster,.svc.cluster.local

    sudo -E kubectl create secret generic cko-argo -n netop-manager \
    --from-literal=url=$REPO \
    --from-literal=type=git  \
    --from-literal=password=$GIT_PAT \
    --from-literal=username=$GIT_USER \
    --from-literal=proxy=$HTTP_PROXY

    sudo -E kubectl label secret cko-argo -n netop-manager 'argocd.argoproj.io/secret-type'=repository


    sudo -E helm repo add cko https://noironetworks.github.io/netop-helm
    sudo -E helm repo update
    sudo -E helm install netop-org-manager cko/netop-org-manager -n netop-manager --create-namespace --version 0.9.0 -f $VALUES_YAML_CKO --wait
else
    echo "some or all required variables to configure cko resources are missing"
fi
