#!/bin/bash

# Import all environment variables
set -a
source /etc/environment #2>/dev/null


# Create cert-manager
#source 11_launch_chart.sh ../prepImgChart/cko_resources/cert-manager-v1.11.0.tgz cko-jetstack-cert-manager ../prepImgChart/cko_resources/cert-manager_images.tgz "--namespace cert-manager --create-namespace --version v1.10.0 --set installCRDs=true"
source 11_launch_chart.sh /tmp/resources/cert-manager-v1.11.0.tgz cko-jetstack-cert-manager /tmp/resources/cert-manager_images.tgz "--namespace cert-manager --create-namespace --version v1.10.0 --set installCRDs=true"
# helm install cert-manager jetstack/cert-manager "--namespace cert-manager --create-namespace --version v1.10.0 --set installCRDs=true --wait"

# create ns
kubectl create ns netop-manager

# create ns
kubectl create ns netop-manager

#TODO: load helm template with correct values.yaml for netop-org-manager
# Create cko
#source 11_launch_chart.sh ../prepImgChart/cko_resources/netop-org-manager-0.9.0.tgz cko-netop-org-manager ../prepImgChart/cko_resources/netop-org-manager_images.tgz "--namespace netop-manager --create-namespace --version 0.9.0 -f my_values.yaml"
source 11_launch_chart.sh /tmp/resources/netop-org-manager-0.9.0.tgz cko-netop-org-manager /tmp/resources/netop-org-manager_images.tgz "--namespace  netop-manager --create-namespace --version 0.9.0 -f my_values.yaml"
# helm install netop-org-manager cko/netop-org-manager "-n netop-manager --create-namespace --version 0.9.0 -f my_values.yaml --wait"