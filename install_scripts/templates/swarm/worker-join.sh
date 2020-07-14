#!/bin/bash

set -e

AIRGAP=0
MIN_DOCKER_VERSION="1.13.1" # secrets compatibility
NO_PROXY=0
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
SKIP_DOCKER_INSTALL=0
NO_CE_ON_EE="{{ no_ce_on_ee }}"
HARD_FAIL_ON_LOOPBACK="{{ hard_fail_on_loopback }}"
HARD_FAIL_ON_FIREWALLD="{{ hard_fail_on_firewalld }}"
ADDITIONAL_NO_PROXY=
SKIP_PREFLIGHTS="{{ '1' if skip_preflights else '' }}"
IGNORE_PREFLIGHTS="{{ '1' if ignore_preflights else '' }}"
REPLICATED_USERNAME="{{ replicated_username }}"

{% include 'common/common.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/log.sh' %}
{% include 'common/system.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/docker-install.sh' %}
{% include 'common/docker-swarm.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/proxy.sh' %}
{% include 'common/airgap.sh' %}
{% include 'common/firewall.sh' %}
{% include 'preflights/index.sh' %}

CA="{{ ca }}"
CERT="{{ cert }}"
DAEMON_REGISTRY_ADDRESS="{{ daemon_registry_address }}"
SWARM_MANAGER_ADDRESS="{{ swarm_manager_address }}"
SWARM_TOKEN="{{ swarm_token }}"

joinSwarm() {
    set +e
    docker swarm join --token "${SWARM_TOKEN}" "${SWARM_MANAGER_ADDRESS}"
    _status=$?
    set -e
    if [ "$_status" -ne "0" ]; then
        printf "${RED}Failed to join the swarm cluster.${NC}\n" 1>&2
        if [ -z "$SWARM_ADVERTISE_ADDR" ] || [ -z "$SWARM_LISTEN_ADDR" ]; then
            printf "${RED}It may be possible to re-run this installer with the flags -swarm-advertise-addr and -swarm-listen-addr to resolve the problem.${NC}\n" 1>&2
        fi
        exit $_status
    fi
}

################################################################################
# Execution starts here
################################################################################

export DEBIAN_FRONTEND=noninteractive

require64Bit
requireRootUser
detectLsbDist
detectInitSystem

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            # airgap implies "skip docker"
            AIRGAP=1
            SKIP_DOCKER_INSTALL=1
            ;;
        bypass-storagedriver-warnings|bypass_storagedriver_warnings)
            BYPASS_STORAGEDRIVER_WARNINGS=1
            ;;
        ca)
            CA="$_value"
            ;;
        cert)
            CERT="$_value"
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
        swarm-manager-address|swarm_manager_address)
            SWARM_MANAGER_ADDRESS="$_value"
            ;;
        swarm-master-address|swarm_master_address) # deprecated
            SWARM_MANAGER_ADDRESS="$_value"
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
        hard-fail-on-loopback|hard_fail_on_loopback)
            HARD_FAIL_ON_LOOPBACK=1
            ;;
        bypass-firewalld-warning|bypass_firewalld_warning)
            BYPASS_FIREWALLD_WARNING=1
            ;;
        hard-fail-on-firewalld|hard_fail_on_firewalld)
            HARD_FAIL_ON_FIREWALLD=1
            ;;
        additional-no-proxy|additional_no_proxy)
            if [ -z "$ADDITIONAL_NO_PROXY" ]; then
                ADDITIONAL_NO_PROXY="$_value"
            else
                ADDITIONAL_NO_PROXY="$ADDITIONAL_NO_PROXY,$_value"
            fi
            ;;
        skip-preflights|skip_preflights)
            SKIP_PREFLIGHTS=1
            ;;
        prompt-on-preflight-warnings|prompt_on_preflight_warnings)
            IGNORE_PREFLIGHTS=0
            ;;
        ignore-preflights|ignore_preflights)
            # do nothing
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

checkFirewalld

if [ "$NO_PROXY" != "1" ]; then
    if [ -z "$PROXY_ADDRESS" ]; then
        discoverProxy
    fi

    if [ -z "$PROXY_ADDRESS" ] && [ "$AIRGAP" != "1" ]; then
        promptForProxy
    fi
fi

exportProxy

if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
    installDocker "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"

    checkDockerDriver
    checkDockerStorageDriver "$HARD_FAIL_ON_LOOPBACK"
else
    requireDocker
fi

promptForSwarmManagerAddress

if [ -n "$PROXY_ADDRESS" ]; then
    getNoProxyAddresses "$SWARM_MANAGER_ADDRESS"
    requireDockerProxy
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

if [ -n "$PROXY_ADDRESS" ]; then
    checkDockerProxyConfig
fi

if [ "$SKIP_PREFLIGHTS" != "1" ]; then
    echo ""
    echo "Running preflight checks..."
    runPreflights || true
    if [ "$IGNORE_PREFLIGHTS" != "1" ]; then
        if [ "$HAS_PREFLIGHT_ERRORS" = "1" ]; then
            bail "\nPreflights have encountered some errors. Please correct them before proceeding."
        elif [ "$HAS_PREFLIGHT_WARNINGS" = "1" ]; then
            logWarn "\nPreflights have encountered some warnings. Please review them before proceeding."
            logWarn "Would you like to proceed anyway?"
            if ! confirmN " "; then
                exit 1
                return
            fi
        fi
    fi
fi

# TODO: docker group
# TODO: replicated user

promptForSwarmToken

if [ -n "$DAEMON_REGISTRY_ADDRESS" ]; then
    if [ -n "$CA" ]; then
        mkdir -p "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS"
        echo "$(echo "$CA" | base64 --decode)" > "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS/ca.crt"
    fi

    if [ -n "$CERT" ]; then
        mkdir -p "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS"
        echo "$(echo "$CERT" | base64 --decode)" > "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS/cert.crt"
    fi
fi

# creating the Replicated user on workers is optional but gives nicer output in `ps` if the uid is
# the same as on the manager node
detectDockerGroupId
maybeCreateReplicatedUser

echo "Joining the swarm"
joinSwarm

SWARM_IP="$(docker info --format "{{ '{{.Swarm.NodeAddr}}' }}")"
echo "Swarm worker IP: ${SWARM_IP}"

exit 0
