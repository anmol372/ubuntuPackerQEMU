#!/bin/bash

# Import all environment variables
set -a
source /etc/environment


# Create cert-manager
source 11_launch_chart.sh /tmp/resources/cert-manager-v1.11.0.tgz cert-manager /tmp/resources/scripts/cko_resources/cert-manager_images.tgz
# helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.10.0 --set installCRDs=true --wait

# create ns
kubectl create ns netop-manager

# create secrets
source 12_create_secrets.sh


# Create cko
source 11_launch_chart.sh /tmp/resources/netop-org-manager-0.9.0.tgz cert-manager /tmp/resources/scripts/cko_resources/netop-org-manager_images.tgz
# helm install netop-org-manager cko/netop-org-manager -n netop-manager --create-namespace --version 0.9.0 -f my_values.yaml --wait