#!/bin/env bash

set -xe

DEBIAN_FRONTEND=noninteractive

set_docker_config() {
  if check_proxy_vars; then
    config_file=~/.docker/config.json
    if [ ! -f "$config_file" ]; then
      echo '{"proxies": {"default": {"http_proxy": "", "https_proxy": "", "no_proxy": ""}}}' > "$config_file"
    fi
    jq '.proxies.default |= . + {"http_proxy": "'"$http_proxy"'", "https_proxy": "'"$https_proxy"'", "no_proxy": "'"$no_proxy"'"}' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
  fi
}


check_proxy_vars() {
  if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
    return 0 # true
  else
    return 1 # false
  fi
}

run_chart() {
  local images=$1
  local release_name=$2
  local chart_name=$3
  local args=$4

  docker load -i $images
  helm template $release_name $chart_name $args > $release_name.yaml
  sed -i'' -e 's/imagePullPolicy:.*/imagePullPolicy: IfNotPresent/g' $release_name.yaml
  rm $release_name.yaml-e
  helm install --name $release_name -f chart.yaml $chart_name
}

check_secret_vars() {
  if [ -n "$REPO" ] || [ -n "$DIR" ] || [ -n "$BRANCH_NAME" ] || [ -n "$GITHUB_PAT" ] || [ -n "$GIT_USER" ] || [ -n "$GIT_EMAIL" ]; then
    return 0 # true
  else
    echo "some or all env variables required to configure cko resources are missing"
    return 1 # false
  fi
}

# Set proxy
IP=$(ip addr show | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
echo "Checking if proxy is set"
export http_proxy=http://proxy.esl.cisco.com:80
export https_proxy=http://proxy.esl.cisco.com:80
export no_proxy=$no_proxy,noiro-quay.cisco.com,$IP
echo "http_proxy=http://proxy.esl.cisco.com:80" | sudo tee -a /etc/environment
echo "https_proxy=http://proxy.esl.cisco.com:80" | sudo tee -a /etc/environment
echo "no_proxy=$no_proxy,noiro-quay.cisco.com,$IP" | sudo tee -a /etc/environment
source /etc/environment
echo "Successfully update Ubuntu packages"

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

# Step 4: Install crio
##########todo....
echo "Installing crio"

export OS_VERSION=xUbuntu_22.04
export CRIO_VERSION=1.24

curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04/Release.key | sudo -E gpg --dearmor --yes -o /usr/share/keyrings/libcontainers-archive-keyring.gpg

curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.24/xUbuntu_22.04/Release.key |  sudo -E gpg --dearmor --yes -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS_VERSION/ /" | sudo -E tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list

echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS_VERSION/ /" | sudo -E tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list

sudo -E apt update

sudo -E apt install -y cri-o cri-o-runc cri-tools

# Create required dirs
mkdir -p /etc/systemd/system/crio.service.d/
mkdir -p /etc/systemd/system/kubelet.service.d/
mkdir -p /etc/systemd/system/crio.service.d/

line="default_capabilities = [\"CHOWN\",\"DAC_OVERRIDE\",\"FSETID\",\"FOWNER\",\"SETGID\",\"SETUID\",\"SETPCAP\",\"NET_BIND_SERVICE\",\"KILL\",\"NET_RAW\",]"
file="/etc/crio/crio.conf"

sudo -E sed -i "/^# will be added./a $line" $file

# add proxy
sudo -E echo -e "[Service]\nEnvironment=HTTP_PROXY=${http_proxy}\nEnvironment=HTTPS_PROXY=${https_proxy}\nEnvironment=NO_PROXY=${no_proxy},noiro-quay.cisco.com" > /etc/systemd/system/cri-o.service
sudo -E echo -e "[Service]\nEnvironment=HTTP_PROXY=${http_proxy}\nEnvironment=HTTPS_PROXY=${https_proxy}\nEnvironment=NO_PROXY=${no_proxy},noiro-quay.cisco.com" > /etc/systemd/system/crio.service.d/http-proxy.conf

# enable crio
#sudo -E systemctl enable crio.service
sudo -E systemctl daemon-reload
sudo -E systemctl restart crio.service



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


# Step 7: Create the cluster with kubeadm
echo "Creating the cluster with kubeadm"

# add entry to /etc/hosts
IP=$(ip addr show | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
HOSTNAME=$(hostname)

echo "$IP $HOSTNAME" | sudo -E tee -a /etc/hosts

# add proxy to kubeadm
if check_proxy_vars; then
  file="/etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

  for item in "HTTP_PROXY=${http_proxy}" "HTTPS_PROXY=${https_proxy}" "NO_PROXY=${no_proxy},$IP,noiro-quay.cisco.com"; do
    if grep -q "^\[Service\]" $file; then
      sudo -E sed -i "/^\[Service\]/a Environment=$item" $file
    else
      sudo -E echo -e "[Service]\Environment=$item\n$(cat $file)" > $file
    fi
  done
fi

sudo -E echo 1 > /proc/sys/net/ipv4/ip_forward

sudo -E systemctl daemon-reload
sudo -E systemctl restart crio.service
sudo -E systemctl restart kubelet


if ! sudo -E kubeadm init --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///var/run/crio/crio.sock; then 
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
#echo "Installing a CNI plugin"

# Install CNI plugin
#if ! kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml; then
#    echo "Error: Failed to install CNI plugin"
#    exit 1
#fi

echo "Done"

# Step 11: Install helm
echo "Installing helm"

# Download and install helm
if ! curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash; then
    echo "Error: Failed to install helm"
    exit 1
fi

echo "Done"

echo "Completed single node cluster setup"

echo "Installing CKO Control cluster"

#source 11_launch_chart.sh /tmp/resources/cert-manager-v1.11.0.tgz cko-jetstack-cert-manager /tmp/resources/cert-manager_images.tgz "--namespace cert-manager --create-namespace --version v1.10.0 --set installCRDs=true"

# create ns
#kubectl create ns netop-manager

# create ns
#kubectl create ns netop-manager

#source 11_launch_chart.sh /tmp/resources/netop-org-manager-0.9.0.tgz cko-netop-org-manager /tmp/resources/netop-org-manager_images.tgz "--namespace  netop-manager --create-namespace --version 0.9.0 -f my_values.yaml"

source create_cko.sh