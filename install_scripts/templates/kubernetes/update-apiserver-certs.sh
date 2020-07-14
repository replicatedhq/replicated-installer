#!/bin/bash

set -e

PRIVATE_ADDRESS=
LOAD_BALANCER_ADDRESS=
LOAD_BALANCER_PORT=
KUBEADM_TOKEN="{{ kubeadm_token }}"
KUBEADM_TOKEN_CA_HASH="{{ kubeadm_token_ca_hash }}"
UNSAFE_SKIP_CA_VERIFICATION="{{ '1' if unsafe_skip_ca_verification else '0' }}"
TAINT_CONTROL_PLANE="{{ '1' if taint_control_plane else '0' }}"

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
        load-balancer-address|load_balancer_address)
            LOAD_BALANCER_ADDRESS="$_value"
            ;;
        private-address|private_address)
            PRIVATE_ADDRESS="$_value"
            ;;
        kubeadm-token|kubeadm_token)
            KUBEADM_TOKEN="$_value"
            ;;
        kubeadm-token-ca-hash|kubeadm_token_ca_hash)
            KUBEADM_TOKEN_CA_HASH="$_value"
            ;;
        unsafe-skip-ca-verification|unsafe_skip_ca_verification)
            UNSAFE_SKIP_CA_VERIFICATION=1
            ;;
        taint-control-plane|taint_control_plane)
            TAINT_CONTROL_PLANE=1
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

PRIMARY=1

promptForToken
promptForTokenCAHash

kubernetesDiscoverPrivateIp
if [ -z "$PRIVATE_ADDRESS" ]; then
    promptForPrivateIp
fi

promptForLoadBalancerAddress
API_SERVICE_ADDRESS="$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"

if [ "$TAINT_CONTROL_PLANE" != "1" ]; then
    cp /etc/kubernetes/admin.conf /tmp/kube.conf
    sed -i "s/server: https.*/server: https:\/\/$PRIVATE_ADDRESS:6443/" /tmp/kube.conf
    export KUBECONFIG=/tmp/kube.conf

    maybeSetTaintControlPlane
fi

rm -f /opt/replicated/kubeadm.conf
makeKubeadmJoinConfigV1Beta2

export KUBECONFIG=/etc/kubernetes/admin.conf

joinUpdateKubeconfigs
joinUpdateApiServerCerts

outro

exit 0
