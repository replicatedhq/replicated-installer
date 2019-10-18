#!/bin/bash

set -e

###############################################################################
#
# /preflights
# 
# This script is meant to be run using:
#   'curl -sSL {{ replicated_install_url }}/preflight | sudo bash'
#
###############################################################################

{% include 'common/common.sh' %}
{% include 'preflights/index.sh' %}

runPreflights
