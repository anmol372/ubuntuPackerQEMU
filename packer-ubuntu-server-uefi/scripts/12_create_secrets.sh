#!/bin/bash

# Import all environment variables
set -a
source /etc/environment

# Create secrets
kubectl create secret generic cko-config -n netop-manager \
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


kubectl create secret generic cko-argo -n netop-manager \
--from-literal=url=$REPO \
--from-literal=type=git  \
--from-literal=password=$GIT_PAT \
--from-literal=username=$GIT_USER \
--from-literal=proxy=$HTTP_PROXY

kubectl label secret cko-argo -n netop-manager 'argocd.argoproj.io/secret-type'=$REPO