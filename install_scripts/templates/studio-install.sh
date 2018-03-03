#!/bin/bash

#
# This script is meant for quick & easy install of Replicated Studio via:
#   'curl -sSL {{ replicated_install_url }}/studio | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/studio | sudo bash'
#

echo "Installing Replicated"

curl -sSL '{{ replicated_install_url }}/docker?customer_base_url="http://172.17.0.1:8006"' | sudo bash

echo "Starting Replicated Studio"

mkdir -p {{ studio_base_path }}/replicated

{% if replicated_env == 'staging' %}
docker run --name studio -d \
     --restart always \
     -v {{ studio_base_path }}/replicated:/replicated \
     -p 8006:8006 \
     -e STUDIO_UPSTREAM_BASE_URL="https://api.staging.replicated.com/market" \
     replicated/studio:latest
{% else %}
docker run --name studio -d \
     --restart always \
     -v {{ studio_base_path }}/replicated:/replicated \
     -p 8006:8006 \
     replicated/studio:latest
{%- endif %}

echo "Replicated Studio started"
