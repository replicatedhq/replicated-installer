#!/bin/bash

#
# This script is meant for quick & easy install of Replicated Studio via:
#   'curl -sSL {{ replicated_install_url }}/studio-k8s | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/studio-k8s | sudo bash'
#

{% include 'common/studio.sh' %}

echo "Installing Replicated"

STUDIO_URL="http://172.17.0.1:8006"
curl -sSL "{{ replicated_install_url }}/kubernetes-init.sh?customer_base_url=${STUDIO_URL}" | sudo bash

echo "Starting Replicated Studio"

mkdir -p {{ studio_base_path }}/replicated

runStudio

echo "Replicated Studio started"
