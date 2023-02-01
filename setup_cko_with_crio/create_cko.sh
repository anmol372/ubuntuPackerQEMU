#!/bin/env bash

set -xe


check_secret_vars() {
  if [ -n "$REPO" ] || [ -n "$DIR" ] || [ -n "$BRANCH_NAME" ] || [ -n "$GITHUB_PAT" ] || [ -n "$GIT_USER" ] || [ -n "$GIT_EMAIL" ]; then
    return 0 # true
  else
    source values.sh
    echo $REPO
    if [ -n "$REPO" ] || [ -n "$DIR" ] || [ -n "$BRANCH_NAME" ] || [ -n "$GITHUB_PAT" ] || [ -n "$GIT_USER" ] || [ -n "$GIT_EMAIL" ]; then
      return 0 # loaded from a config
    else  
      echo "some or all env variables required to configure cko resources are missing"
      return 1 # false
    fi
  fi
}

if check_secret_vars; then
    sudo -E helm repo add jetstack https://charts.jetstack.io
    sudo -E helm repo update
    sudo -E helm install \
    cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.10.0 \
    --set installCRDs=true
    --wait

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

    sudo -E kubectl label secret cko-argo -n netop-manager 'argocd.argoproj.io/secret-type'=$REPO


    sudo -E helm repo add cko https://noironetworks.github.io/netop-helm
    sudo -E helm repo update
    sudo -E helm install netop-org-manager cko/netop-org-manager -n netop-manager --create-namespace --version 0.9.0 -f $values --wait
else
    echo "some or all required variables to configure cko resources are missing"
fi
