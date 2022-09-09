#!/bin/bash

#
# This script is meant for quick & easy install via:
#   'curl -sSL {{ replicated_install_url }}/docker-compose-generate | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/docker-compose-generate | sudo bash'
#

set -e

REPLICATED_INSTALL_URL={{ replicated_install_url }}
AIRGAP={{ airgap|default('0', true) }}
GROUP_ID={{ group_id }}
LOG_LEVEL={{ log_level|default('info', true) }}
PUBLIC_ADDRESS={{ public_address }}
REGISTRY_BIND_PORT={{ registry_bind_port|default('9874', true) }}
SUPPRESS_RUNTIME={{ suppress_runtime }}
SWARM_NODE_ADDRESS={{ swarm_node_address }}
SWARM_STACK_NAMESPACE={{ swarm_stack_namespace }}
TLS_CERT_PATH={{ tls_cert_path }}
UI_BIND_PORT={{ ui_bind_port|default('8800', true) }}
USER_ID={{ user_id }}
HTTP_PROXY={{ http_proxy }}
NO_PROXY_ADDRESSES={{ no_proxy_addresses }}
RELEASE_SEQUENCE={{ release_sequence }}
RELEASE_PATCH_SEQUENCE={{ release_patch_sequence }}
REPLICATED_REGISTRY_PREFIX=
REPLICATED_VERSION={{ replicated_version }}
REPLICATED_ENV={{ replicated_env }}
REPLICATED_TAG={{ replicated_tag|default('stable', true) }}{{ environment_tag_suffix }}
REPLICATED_UI_TAG={{ replicated_ui_tag|default('stable', true) }}{{ environment_tag_suffix }}
REPLICATED_OPERATOR_TAG={{ replicated_operator_tag|default('stable', true) }}{{ environment_tag_suffix }}
RELEASE_CHANNEL={{ channel_name|default('stable', true) }}
CUSTOMER_BASE_URL_OVERRIDE={{ customer_base_url_override }}
SNAPSHOTS_USE_OVERLAY={{ snapshots_use_overlay|default('0', true) }}

{% include 'common/common.sh' %}
{% include 'common/replicated.sh' %}
