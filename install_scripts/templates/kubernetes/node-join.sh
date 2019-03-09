#!/bin/bash

set -e

AIRGAP=0
MIN_DOCKER_VERSION="1.10.3" # k8s min
NO_PROXY=0
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
SKIP_DOCKER_INSTALL=0
OFFLINE_DOCKER_INSTALL=0
NO_CE_ON_EE="{{ no_ce_on_ee }}"
HARD_FAIL_ON_LOOPBACK="{{ hard_fail_on_loopback }}"
HARD_FAIL_ON_FIREWALLD="{{ hard_fail_on_firewalld }}"
KUBERNETES_ONLY=0
ADDITIONAL_NO_PROXY=
KUBERNETES_VERSION="{{ kubernetes_version }}"
K8S_UPGRADE_PATCH_VERSION="{{ k8s_upgrade_patch_version }}"
IPVS=1
PRIVATE_ADDRESS=

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
{% include 'common/log.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/selinux.sh' %}
{% include 'common/airgap.sh' %}
{% include 'common/swap.sh' %}
{% include 'common/kubernetes-upgrade.sh' %}
{% include 'common/firewall.sh' %}

KUBERNETES_MASTER_PORT="6443"
KUBERNETES_MASTER_ADDR="{{ kubernetes_master_address }}"
API_SERVICE_ADDRESS=
MASTER_PKI_BUNDLE_URL=
INSECURE=0
MASTER=0
CA=
CERT=
KUBEADM_TOKEN="{{ kubeadm_token }}"
KUBEADM_TOKEN_CA_HASH="{{ kubeadm_token_ca_hash }}"
SERVICE_CIDR="10.96.0.0/12" # kubeadm default

downloadPkiBundle() {
    if [ -z "$MASTER_PKI_BUNDLE_URL" ]; then
        return
    fi
    logStep "Download Kubernetes PKI bundle"
    _opt=
    if [ "$INSECURE" -eq "1" ]; then
        _opt="-k"
    elif [ -n "$CA" ]; then
        echo "$CA" | base64 -d > /tmp/replicated-ca.crt
        _opt="--cacert /tmp/replicated-ca.crt"
    fi
    (set -x; curl --noproxy "*" --max-time 30 --connect-timeout 2 $_opt -qSsf "$MASTER_PKI_BUNDLE_URL" > /tmp/etc-kubernetes.tar)
    (set -x; tar -C /etc/kubernetes/ -xvf /tmp/etc-kubernetes.tar)
    logSuccess "Kubernetes PKI downloaded successfully"
}

joinKubernetes() {
    if [ "$MASTER" -eq "1" ]; then
        logStep "Join Kubernetes master node"
    else
        logStep "Join Kubernetes node"
    fi
    semverParse "$KUBERNETES_VERSION"
    set +e
    if [ "$minor" -ge 13 ]; then
        mkdir -p /opt/replicated
        makeKubeadmJoinConfig
        (set -x; kubeadm join --config=/opt/replicated/kubeadm.conf)
    else
        (set -x; kubeadm join --discovery-token-ca-cert-hash "${KUBEADM_TOKEN_CA_HASH}" --token "${KUBEADM_TOKEN}" "${API_SERVICE_ADDRESS}")
    fi
    _status=$?
    set -e
    if [ "$_status" -ne "0" ]; then
        printf "${RED}Failed to join the kubernetes cluster.${NC}\n" 1>&2
        exit $_status
    fi
    if [ "$MASTER" -eq "1" ]; then
        logStep "Master node joined successfully"
    else
        logStep "Node joined successfully"
    fi
}

promptForToken() {
    if [ -n "$KUBEADM_TOKEN" ]; then
        return
    fi

    printf "Please enter the kubernetes discovery token.\n"
    while true; do
        printf "Kubernetes join token: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBEADM_TOKEN="$PROMPT_RESULT"
            return
        fi
    done
}

promptForTokenCAHash() {
    if [ -n "$KUBEADM_TOKEN_CA_HASH" ]; then
        return
    fi

    printf "Please enter the discovery token CA's hash.\n"
    while true; do
        printf "Kubernetes discovery token CA hash: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBEADM_TOKEN_CA_HASH="$PROMPT_RESULT"
            return
        fi
    done
}

promptForMasterAddress() {
    if [ -n "$KUBERNETES_MASTER_ADDR" ]; then
        return
    fi

    printf "Please enter the Kubernetes master address.\n"
    printf "e.g. 10.128.0.4\n"
    while true; do
        printf "Kubernetes master address: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBERNETES_MASTER_ADDR="$PROMPT_RESULT"
            return
        fi
    done
}

# Once the Rook agent has started and copied its plugins to the host, the
# the kubelet may need to be restarted as a fix for a race condition in
# K8s 1.11 and Rook < 0.9. https://github.com/rook/rook/issues/2064
ensureRookPluginsRegistered() {
    logStep "Await Node Ready"
    # If Rook is enabled it should start around the same time Weave starts.
    # Cannot wait for Rook directly because it may be disabled.
    while ! docker ps | grep -q weave-net ; do
        sleep 2
    done
    sleep 10
    systemctl restart kubelet
    logSuccess "Node Is Ready"
}

# The node join script generated by Replicated UI modal did not pass the Replicated
# version to the installer app prior to 2.31.0 so the PINNED_DOCKER_VERSION is for the
# latest version of Replicated, not for the cluster that is being joined.
maybeOverridePinnedDockerVersion() {
    semverParse "$KUBERNETES_VERSION"
    # If the K8s version is at least 1.13 then the Replicated version is at least 2.31
    # and the PINNED_DOCKER_VERSION does not need to be corrected.
    if [ "$minor" -lt "13" ]; then
        PINNED_DOCKER_VERSION="1.12.3"
    fi
}

# Clean up operator in case node was migrated from native.
purgeNative() {
    systemctl stop replicated-operator &>/dev/null || true
    docker rm -f replicated-operator &>/dev/null || true
    rm -rf /var/lib/replicated* \
        /etc/default/replicated* \
        /etc/sysconfig/replicated*
}

outro() {
    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    if [ "$MASTER" -eq "1" ]; then
        printf "\n"
        printf "To access the cluster with kubectl, reload your shell:\n"
        printf "\n"
        printf "${GREEN}    bash -l${NC}\n"
    fi
    printf "\n"
}

################################################################################
# Execution starts here
################################################################################

require64Bit
requireRootUser
detectLsbDist
bailIfUnsupportedOS
detectInitSystem
mustSwapoff

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            # airgap implies "offline docker"
            AIRGAP=1
            OFFLINE_DOCKER_INSTALL=1
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
        kubernetes-master-address|kubernetes_master_address)
            KUBERNETES_MASTER_ADDR="$_value"
            ;;
        api-service-address|api_service_address)
            API_SERVICE_ADDRESS="$_value"
            ;;
        master-pki-bundle-url|master_pki_bundle_url)
            MASTER_PKI_BUNDLE_URL="$_value"
            MASTER=1
            ;;
        insecure)
            INSECURE=1
            ;;
        kubeadm-token|kubeadm_token)
            KUBEADM_TOKEN="$_value"
            ;;
        kubeadm-token-ca-hash|kubeadm_token_ca_hash)
            KUBEADM_TOKEN_CA_HASH="$_value"
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
        hard-fail-on-firewalld|hard_fail_on_firewalld)
            HARD_FAIL_ON_FIREWALLD=1
            ;;
        service-cidr|service_cidr)
            SERVICE_CIDR="$_value"
            ;;
        kubernetes-version|kubernetes_version)
            KUBERNETES_VERSION="$_value"
            ;;
        kubernetes-only|kubernetes_only)
            KUBERNETES_ONLY=1
            ;;
        additional-no-proxy|additional_no_proxy)
            if [ -z "$ADDITIONAL_NO_PROXY" ]; then
                ADDITIONAL_NO_PROXY="$_value"
            else
                ADDITIONAL_NO_PROXY="$ADDITIONAL_NO_PROXY,$_value"
            fi
            ;;
        kubernetes-upgrade-patch-version|kubernetes_upgrade_patch_version)
            K8S_UPGRADE_PATCH_VERSION=1
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

if [ -z "$KUBERNETES_VERSION" ]; then
    bail "kubernetes-version is required"
fi
if [ "$KUBERNETES_VERSION" == "1.9.3" ]; then
    IPVS=0
fi

export KUBECONFIG=/etc/kubernetes/admin.conf

setK8sPatchVersion

checkFirewalld

if [ -n "$API_SERVICE_ADDRESS" ]; then
    splitHostPort "$API_SERVICE_ADDRESS"
    KUBERNETES_MASTER_ADDR="$HOST"
    KUBERNETES_MASTER_PORT="$PORT"
else
    promptForMasterAddress
    API_SERVICE_ADDRESS="${KUBERNETES_MASTER_ADDR}:${KUBERNETES_MASTER_PORT}"
fi
promptForToken
promptForTokenCAHash

if [ -z "$PRIVATE_ADDRESS" ]; then
    promptForPrivateIp
fi

if [ "$NO_PROXY" != "1" ]; then
    if [ -z "$PROXY_ADDRESS" ]; then
        discoverProxy
    fi

    if [ -z "$PROXY_ADDRESS" ] && [ "$AIRGAP" != "1" ]; then
        promptForProxy
    fi
fi

exportProxy

# never upgrade docker underneath kubernetes
if commandExists docker ; then
    SKIP_DOCKER_INSTALL=1
fi
if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
    maybeOverridePinnedDockerVersion
    if [ "$OFFLINE_DOCKER_INSTALL" != "1" ]; then
        installDocker "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"

        semverParse "$PINNED_DOCKER_VERSION"
        if [ "$major" -ge "17" ]; then
            lockPackageVersion docker-ce
        fi
    else
        installDockerOffline
    fi
    checkDockerDriver
    checkDockerStorageDriver "$HARD_FAIL_ON_LOOPBACK"
else
    requireDocker
fi

if [ -n "$PROXY_ADDRESS" ]; then
    getNoProxyAddresses "$KUBERNETES_MASTER_ADDR" "$SERVICE_CIDR"
    # enable kubeadm to reach the K8s API server
    export no_proxy="$NO_PROXY_ADDRESSES"
    requireDockerProxy
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

must_disable_selinux
installKubernetesComponents "$KUBERNETES_VERSION"
systemctl enable kubelet && systemctl start kubelet

if [ "$AIRGAP" = "1" ]; then
    if [ "$KUBERNETES_ONLY" != "1" ]; then
        promptForDaemonRegistryAddress
        mkdir -p "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS"
        promptForCA
        echo "$(echo "$CA" | base64 --decode)" > "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS/ca.crt"

        if [ -n "$CERT" ]; then
            echo "$(echo "$CERT" | base64 --decode)" > "/etc/docker/certs.d/$DAEMON_REGISTRY_ADDRESS/cert.crt"
        fi
    fi
    airgapLoadKubernetesCommonImages "$KUBERNETES_VERSION"
    addInsecureRegistry "$SERVICE_CIDR"
else
    docker pull registry:2.6.2
    docker tag registry:2.6.2 registry:2
fi

loadIPVSKubeProxyModules

if ! docker ps | grep -q 'k8s.gcr.io/pause'; then
    downloadPkiBundle

    joinKubernetes
fi

maybeUpgradeKubernetesNode "$KUBERNETES_VERSION"
ensureRookPluginsRegistered

purgeNative

if [ "$MASTER" -eq "1" ]; then
    exportKubeconfig
fi

outro

exit 0
