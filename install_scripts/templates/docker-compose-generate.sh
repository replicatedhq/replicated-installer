#!/bin/bash

#
# This script is meant for quick & easy install via:
#   'curl -sSL {{ replicated_install_url }}/docker-compose-generate | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/docker-compose-generate | sudo bash'
#

set -e

AIRGAP="{{ airgap|default('0', true) }}"
GROUP_ID="{{ group_id }}"
LOG_LEVEL="{{ log_level|default('info', true) }}"
PUBLIC_ADDRESS="{{ public_address }}"
REGISTRY_BIND_PORT="{{ registry_bind_port|default('9874', true) }}"
SUPPRESS_RUNTIME="{{ suppress_runtime }}"
SWARM_NODE_ADDRESS="{{ swarm_node_address }}"
SWARM_STACK_NAMESPACE="{{ swarm_stack_namespace }}"
TLS_CERT_PATH="{{ tls_cert_path }}"
UI_BIND_PORT="{{ ui_bind_port|default('8800', true) }}"
USER_ID="{{ user_id }}"

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            AIRGAP=1
            ;;
        group-id|group_id)
            GROUP_ID="$_value"
            ;;
        log-level|log_level)
            LOG_LEVEL="$_value"
            ;;
        public-address|public_address)
            PUBLIC_ADDRESS="$_value"
            ;;
        registry-bind-port|registry_bind_port)
            REGISTRY_BIND_PORT="$_value"
            ;;
        release-sequence|release_sequence)
            RELEASE_SEQUENCE="$_value"
            ;;
        suppress-runtime)
            SUPPRESS_RUNTIME=1
            ;;
        swarm-node-address|swarm_node_address)
            SWARM_NODE_ADDRESS="$_value"
            ;;
        swarm-stack-namespace|swarm_stack_namespace)
            SWARM_STACK_NAMESPACE="$_value"
            ;;
        tls-cert-path|tls_cert_path)
            TLS_CERT_PATH="$_value"
            ;;
        ui-bind-port|ui_bind_port)
            UI_BIND_PORT="$_value"
            ;;
        user-id|user_id)
            USER_ID="$_value"
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

if [ "$SUPPRESS_RUNTIME" != "1" ]; then
    if [ -z "$SWARM_NODE_ADDRESS" ]; then
        SWARM_NODE_ADDRESS="$(docker info --format "{{ '{{.Swarm.NodeAddr}}' }}")"
    fi
fi

# TODO: detect
# - public_address
# - user_id
# - group_id
# - tls_cert_path

echo "# optional query parameters:
# - group_id
# - log_level
# - public_address
# - registry_bind_port
# - swarm_node_address
# - swarm_stack_namespace
# - tls_cert_path
# - ui_bind_port
# - user_id

# secrets:
# - daemon_token (external, required)
"
echo "version: '3.1'"
echo ""
echo "services:"
echo ""
echo "  replicated:"
echo "    image: {{ replicated_docker_host|default('quay.io', true) }}/replicated/replicated:{{ replicated_tag|default('stable', true) }}{{ environment_tag_suffix }}"
echo "    ports:"
echo "      - ${REGISTRY_BIND_PORT}:9874"
echo "      - 9878:9878"
echo "    environment:"
echo "      - RELEASE_CHANNEL={{ channel_name|default('stable', true) }}"
echo "      - LOG_LEVEL=${LOG_LEVEL}"
if [ "$AIRGAP" = "1" ]; then
    echo "      - AIRGAP=true"
fi
echo "      - SCHEDULER_ENGINE=swarm"
echo "      - LOCAL_ADDRESS=${SWARM_NODE_ADDRESS}"
if [ -n "$SWARM_STACK_NAMESPACE" ]; then
    echo "      - STACK_NAMESPACE=${SWARM_STACK_NAMESPACE}"
fi
if [ -n "$PUBLIC_ADDRESS" ]; then
    echo "      - SWARM_INGRESS_ADDRESS=${PUBLIC_ADDRESS}"
fi
if [ -n "$RELEASE_SEQUENCE" ]; then
    echo "      - RELEASE_SEQUENCE=${RELEASE_SEQUENCE}"
fi
{% if replicated_env == "staging" %}
    echo "      - MARKET_BASE_URL=https://api.staging.replicated.com/market"
    echo "      - DATA_BASE_URL=https://data.staging.replicated.com/market"
    echo "      - VENDOR_REGISTRY=registry.staging.replicated.com"
    echo "      - INSTALLER_URL=https://get.staging.replicated.com"
    echo "      - REPLICATED_IMAGE_TAG_SUFFIX=.staging"
{% endif %}
echo "    volumes:"
echo "      - replicated-data-volume:/var/lib/replicated"
echo "      - replicated-sock-volume:/var/run/replicated"
if [ -n "$TLS_CERT_PATH" ]; then
    echo "      - ${TLS_CERT_PATH}:/etc/ssl/certs/ca-certificates.crt:ro"
fi
echo "      - /var/run/docker.sock:/host/var/run/docker.sock"
echo "      - /proc:/host/proc:ro"
echo "      - /etc:/host/etc:ro"
echo "      - /etc/os-release:/host/etc/os-release:ro"
if [ -n "$USER_ID" ] && [ -n "$GROUP_ID" ]; then
    echo "    user: \"${USER_ID}:${GROUP_ID}\""
fi
if [ -n "$USER_ID" ]; then
    echo "    user: \"${USER_ID}\""
fi
echo "    deploy:"
echo "      mode: replicated"
echo "      replicas: 1"
echo "      placement:"
echo "        constraints:"
echo "          - node.role == manager"
echo "          - node.labels.replicated-role == master"
echo "      restart_policy:"
echo "        condition: on-failure"
echo "        delay: 5s"
echo "        max_attempts: 5"
echo "        window: 20s"
echo "    secrets:"
echo "      - source: daemon_token"
echo "        target: daemon_token"
if [ -n "$USER_ID" ]; then
    echo "        uid: \"${USER_ID}\""
fi
if [ -n "$GROUP_ID" ]; then
    echo "        gid: \"${GROUP_ID}\""
fi
echo "        mode: 0440"
echo ""
echo "  replicated-ui:"
echo "    image: {{ replicated_docker_host|default('quay.io', true) }}/replicated/replicated-ui:{{ replicated_ui_tag|default('stable', true) }}{{ environment_tag_suffix }}"
echo "    ports:"
echo "      - ${UI_BIND_PORT}:8800"
echo "    environment:"
echo "      - RELEASE_CHANNEL={{ channel_name|default('stable', true) }}"
echo "      - LOG_LEVEL=${LOG_LEVEL}"
echo "    depends_on:"
echo "      - replicated"
echo "    volumes:"
echo "      - replicated-sock-volume:/var/run/replicated"
if [ -n "$USER_ID" ] && [ -n "$GROUP_ID" ]; then
    echo "    user: \"${USER_ID}:${GROUP_ID}\""
fi
if [ -n "$USER_ID" ]; then
    echo "    user: \"${USER_ID}\""
fi
echo "    deploy:"
echo "      mode: replicated"
echo "      replicas: 1"
echo "      placement:"
echo "        constraints:"
echo "          - node.role == manager"
echo "          - node.labels.replicated-role == master"
echo "      restart_policy:"
echo "        condition: on-failure"
echo "        delay: 5s"
echo "        max_attempts: 5"
echo "        window: 20s"
echo ""
echo "  replicated-operator:"
if [ "$AIRGAP" = "1" ]; then
    echo "    image: ${SWARM_NODE_ADDRESS}:${REGISTRY_BIND_PORT}/replicated/replicated-operator:{{ replicated_operator_tag|default('stable', true) }}{{ environment_tag_suffix }}"
else
    echo "    image: {{ replicated_docker_host|default('quay.io', true) }}/replicated/replicated-operator:{{ replicated_operator_tag|default('stable', true) }}{{ environment_tag_suffix }}"
fi
echo "    environment:"
echo "      - RELEASE_CHANNEL={{ channel_name|default('stable', true) }}"
echo "      - LOG_LEVEL=${LOG_LEVEL}"
if [ "$AIRGAP" = "1" ]; then
    echo "      - AIRGAP=true"
fi
echo "      - SCHEDULER_ENGINE=swarm"
echo "      - DAEMON_ENDPOINT=replicated:9879"
echo "      - DAEMON_REGISTRY_ENDPOINT=${SWARM_NODE_ADDRESS}:${REGISTRY_BIND_PORT}"
echo "      - DAEMON_HOST=replicated"
echo "    volumes:"
echo "      - replicated-operator-data-volume:/var/lib/replicated-operator"
echo "      - replicated-operator-sock-volume:/var/run/replicated-operator"
echo "      - /var/run/docker.sock:/host/var/run/docker.sock"
echo "      - /proc:/host/proc:ro"
echo "      - /etc:/host/etc:ro"
echo "      - /etc/os-release:/host/etc/os-release:ro"
if [ -n "$USER_ID" ] && [ -n "$GROUP_ID" ]; then
    echo "    user: \"${USER_ID}:${GROUP_ID}\""
fi
if [ -n "$USER_ID" ]; then
    echo "    user: \"${USER_ID}\""
fi
echo "    deploy:"
echo "      mode: global"
echo "      restart_policy:"
echo "        condition: on-failure"
echo "        delay: 5s"
echo "        max_attempts: 5"
echo "        window: 20s"
echo "    secrets:"
echo "      - source: daemon_token"
echo "        target: daemon_token"
if [ -n "$USER_ID" ]; then
    echo "        uid: \"${USER_ID}\""
fi
if [ -n "$GROUP_ID" ]; then
    echo "        gid: \"${GROUP_ID}\""
fi
echo "        mode: 0440"
echo ""
echo "volumes:"
echo "  replicated-data-volume:"
echo "  replicated-sock-volume:"
echo "  replicated-operator-data-volume:" # TODO: how does this work with global service?
echo "  replicated-operator-sock-volume:" # TODO: how does this work with global service?
echo ""
echo "secrets:"
echo "  daemon_token:"
echo "    external: true"
