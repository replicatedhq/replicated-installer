#!/bin/bash

set -e

PROXY_ADDRESS=
PUBLIC_ADDRESS=
PRIVATE_ADDRESS=
LOAD_BALANCER_ADDRESS=
LOAD_BALANCER_PORT=
ADDITIONAL_SANS=

{% include 'common/common.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/log.sh' %}
{% include 'common/system.sh' %}
{% include 'common/selinux.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/cli-script.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/kubernetes-upgrade.sh' %}

outro() {
    printf "\n"
    printf "\t\t${GREEN}Update${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    printf "\n"
}

################################################################################
# Execution starts here
################################################################################

export DEBIAN_FRONTEND=noninteractive

requireRootUser

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        load-balancer-address|load_balancer_address)
            LOAD_BALANCER_ADDRESS="$_value"
            ;;
        additional-sans|additional_sans)
            if [ -z "$ADDITIONAL_SANS" ]; then
                ADDITIONAL_SANS="$_value"
            else
                ADDITIONAL_SANS="$ADDITIONAL_SANS;$_value"
            fi
            ;;
        public-address|public_address)
            PUBLIC_ADDRESS="$_value"
            ;;
        private-address|private_address)
            PRIVATE_ADDRESS="$_value"
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

export KUBECONFIG=/etc/kubernetes/admin.conf

if [ -z "$PRIVATE_ADDRESS" ]; then
    promptForPrivateIp
fi

# NOTE: there is no PUBLIC_ADDRESS or PROXY_ADDRESS prompts

promptForLoadBalancerAddress

# NOTE: this should use joinUpdateApiServerCerts for additional nodes
# this will need a new bootstrap token
updateApiServerCerts

outro

exit 0
