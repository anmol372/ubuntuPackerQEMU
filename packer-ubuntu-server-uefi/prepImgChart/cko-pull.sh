#!/bin/bash

# Define variables for chart name and repo URL
chart_name="netop-org-manager"
repo_name="cko"
repo_url="https://noironetworks.github.io/netop-helm"
output_dir="cko_resources"

# Add the repo to Helm
helm repo add $repo_name $repo_url

# Fetch the latest chart
helm fetch $repo_name/$chart_name

# Extract the container images from the chart
chart_file=$(ls $chart_name-*tgz)
tar -xvzf $chart_file

# Create a tar file with all of the container images
images=$(helm template $chart_name | grep "image:" | awk '{print $2}')
for image in $images; do
  echo "Adding $image to tar file"
  image=$(echo $image | sed -e 's/^"//' -e 's/"$//')
  docker pull $image
  docker save $image | gzip > cko.tgz
done


#tar -czvf $output_dir/$chart_name"_images.tar.gz" $(docker images -q)

# Move the chart
mv cko.tgz $output_dir/$chart_name"_images.tgz"
mv $chart_file $output_dir/$chart_file

# Cleanup
rm -rf $chart_name
rm cko.tgz
docker rmi $(docker images -q)