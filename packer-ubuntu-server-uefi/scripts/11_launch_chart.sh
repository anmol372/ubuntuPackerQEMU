#!/bin/bash

# Define the name of the Helm chart
chart_name=$1
echo $chart_name

# Define the name of the release
release_name=$2
echo $release_name

# Define images.tar
images=$3

args=$(echo $4 | sed -e 's/^"//' -e 's/"$//')

# Load an image from a tgz file
docker load -i $images

# Use the helm template command to save the chart to a file
helm template $release_name $chart_name $args> $release_name.yaml

# Update the value of imagePullPolicy to IfNotPresent
sed -i'' -e 's/imagePullPolicy:.*/imagePullPolicy: IfNotPresent/g' $release_name.yaml
rm $release_name.yaml-e

# Run the chart.yaml file
helm install --name $release_name -f chart.yaml $chart_name