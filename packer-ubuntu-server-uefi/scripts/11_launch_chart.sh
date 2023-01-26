#!/bin/env bash

# Define the name of the Helm chart
chart_name=$1

# Define the name of the release
release_name=$2

# Define images.tar
images=$3

# Load an image from a tgz file
docker load -i $images

#TODO: load helm template with correct values.yaml

# Use the helm template command to save the chart to a file
helm template $chart_name $release_name > chart.yaml

# Update the value of imagePullPolicy to IfNotPresent
sed -i 's/imagePullPolicy:.*/imagePullPolicy: IfNotPresent/g' chart.yaml

# Run the chart.yaml file
helm install --name $release_name -f chart.yaml $chart_name