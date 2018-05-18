#!/bin/bash

set -e

AIRGAP=0
MIN_DOCKER_VERSION="1.13.1" # secrets compatibility
NO_PROXY=0
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
SKIP_DOCKER_INSTALL=0
NO_CE_ON_EE="{{ no_ce_on_ee }}"

{% include 'common/common.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/system.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/docker-install.sh' %}
{% include 'common/docker-swarm.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/proxy.sh' %}
{% include 'common/airgap.sh' %}

CA="{{ ca }}"
DAEMON_REGISTRY_ADDRESS="{{ daemon_registry_address }}"
SWARM_MASTER_ADDRESS="{{ swarm_master_address }}"
SWARM_TOKEN="{{ swarm_token }}"

joinSwarm() {
    set +e
    docker swarm join --token "${SWARM_TOKEN}" "${SWARM_MASTER_ADDRESS}"
    _status=$?
    set -e
    if [ "$_status" -ne "0" ]; then
        printf "${RED}Failed to join the swarm cluster.${NC}\n" 1>&2
        if [ -z "$SWARM_ADVERTISE_ADDR" ] || [ -z "$SWARM_LISTEN_ADDR" ]; then
            printf "${RED}It may be possible to re-run this installer with the flags -swarm-advertise-addr and -swarm-listen-addr to resolve the problem.${NC}\n" 1>&2
        fi
        exit $?
    fi
}

################################################################################
# Execution starts here
################################################################################

require64Bit
requireRootUser
detectLsbDist
detectInitSystem

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            # arigap implies "no proxy" and "skip docker"
            AIRGAP=1
            NO_PROXY=1
            SKIP_DOCKER_INSTALL=1
            ;;
        bypass-storagedriver-warnings|bypass_storagedriver_warnings)
            BYPASS_STORAGEDRIVER_WARNINGS=1
            ;;
        ca)
            CA="$_value"
            ;;
        daemon-registry-address|daemon_registry_address)
            DAEMON_REGISTRY_ADDRESS="$_value"
            ;;
        docker-version|docker_version)
            PINNED_DOCKER_VERSION="$_value"
            ;;
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        no-docker|no_docker)
            SKIP_DOCKER_INSTALL=1
            ;;
        no-proxy|no_proxy)
            NO_PROXY=1
            ;;
        swarm-advertise-addr|swarm_advertise_addr)
            SWARM_ADVERTISE_ADDR="$_value"
            ;;
        swarm-listen-addr|swarm_listen_addr)
            SWARM_LISTEN_ADDR="$_value"
            ;;
        swarm-master-address|swarm_master_address)
            SWARM_MASTER_ADDRESS="$_value"
            ;;
        swarm-token|swarm_token)
            SWARM_TOKEN="$_value"
            ;;
        tags)
            OPERATOR_TAGS="$_value"
            ;;
        no-ce-on-ee|no_ce_on_ee)
            NO_CE_ON_EE=1
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

if [ "$NO_PROXY" != "1" ]; then
    if [ -z "$PROXY_ADDRESS" ]; then
        discoverProxy
    fi

    if [ -z "$PROXY_ADDRESS" ]; then
        promptForProxy
    fi
fi

exportProxy

if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
    installDocker "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"

    checkDockerDriver
    checkDockerStorageDriver
fi

promptForSwarmMasterAddress

if [ -n "$PROXY_ADDRESS" ]; then
    parseIpv4FromAddress "$SWARM_MASTER_ADDRESS"
    NO_PROXY_IP="$PARSED_IPV4"
    requireDockerProxy
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

if [ -n "$PROXY_ADDRESS" ]; then
    checkDockerProxyConfig
fi

# TODO: docker group
# TODO: replicated user

promptForSwarmToken

if [ -n "$DAEMON_REGISTRY_ADDRESS" ] && [ -n "$CA" ]; then
    mkdir -p "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS"
    echo "$(echo "$CA" | base64 --decode)" > "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS/ca.crt"
fi

echo "Joining the swarm"
joinSwarm

SWARM_IP="$(docker info --format "{{ '{{.Swarm.NodeAddr}}' }}")"
echo "Swarm worker IP: ${SWARM_IP}"

exit 0
