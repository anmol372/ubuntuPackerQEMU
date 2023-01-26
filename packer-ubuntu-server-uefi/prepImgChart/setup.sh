#!/bin/bash

# Run cert-manager-pull.sh script
#chart_name="cert-manager"
#repo_name="jetstack"
#repo_url="https://charts.jetstack.io"
#output_dir="cko_resources"
#source prepImgChart/cert-manager-pull.sh "cert-manager" "jetstack" "https://charts.jetstack.io" "cko_resources"

source pull.sh cert-manager-pull.sh

# Run cko-pull.sh script
#chart_name="netop-org-manager"
#repo_name="cko"
#repo_url="https://noironetworks.github.io/netop-helm"
#output_dir="cko_resources"
#source prepImgChart/pull.sh "netop-org-manager" "cko" "https://noironetworks.github.io/netop-helm" "cko_resources"

source pull.sh cko-pull.sh