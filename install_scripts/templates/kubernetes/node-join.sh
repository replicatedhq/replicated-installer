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
WAIT_FOR_ROOK=0
ADDITIONAL_NO_PROXY=
SKIP_PREFLIGHTS="{{ '1' if skip_preflights else '' }}"
IGNORE_PREFLIGHTS="{{ '1' if ignore_preflights else '' }}"
KUBERNETES_VERSION="{{ kubernetes_version }}"
K8S_UPGRADE_PATCH_VERSION="{{ k8s_upgrade_patch_version }}"
IPVS=1
PRIVATE_ADDRESS=
UNSAFE_SKIP_CA_VERIFICATION="{{ '1' if unsafe_skip_ca_verification else '0' }}"

{% include 'common/common.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/system.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/docker-install.sh' %}
{% include 'common/docker-swarm.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/cli-script.sh' %}
{% include 'common/alias.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/proxy.sh' %}
{% include 'common/log.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/selinux.sh' %}
{% include 'common/airgap.sh' %}
{% include 'common/swap.sh' %}
{% include 'common/kubernetes-upgrade.sh' %}
{% include 'common/firewall.sh' %}
{% include 'preflights/index.sh' %}

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
    (set -x; curl --noproxy "*" --max-time 120 --connect-timeout 5 $_opt -qSsf "$MASTER_PKI_BUNDLE_URL" > /tmp/etc-kubernetes.tar)
    (set -x; tar -C /etc/kubernetes/ -xvf /tmp/etc-kubernetes.tar)
    logSuccess "Kubernetes PKI downloaded successfully"
}

joinKubernetes() {
    if [ "$MASTER" -eq "1" ]; then
        logStep "Join Kubernetes master node"

        # this will stop all the control plane pods except etcd
        rm -f /etc/kubernetes/manifests/kube-*
        while docker ps | grep -q kube-apiserver ; do
            sleep 2
        done
        # delete files that need to be regenerated in case of load balancer address change
        rm -f /etc/kubernetes/*.conf
        rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
    else
        logStep "Join Kubernetes node"
    fi
    semverParse "$KUBERNETES_VERSION"
    set +e
    if [ "$minor" -ge 15 ]; then
        mkdir -p /opt/replicated
        makeKubeadmJoinConfigV1Beta2
        (set -x; kubeadm join --config /opt/replicated/kubeadm.conf --ignore-preflight-errors=all)
    elif [ "$minor" -ge 13 ]; then
        mkdir -p /opt/replicated
        makeKubeadmJoinConfig
        (set -x; kubeadm join --config /opt/replicated/kubeadm.conf --ignore-preflight-errors=all)
        untaintMaster
    else
        (set -x; kubeadm join --discovery-token-ca-cert-hash "${KUBEADM_TOKEN_CA_HASH}" --token "${KUBEADM_TOKEN}" "${API_SERVICE_ADDRESS}")
        untaintMaster
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

waitForRook() {
    if [ "$WAIT_FOR_ROOK" != "1" ]; then
        return
    fi
    logStep "Waiting for Rook plugin"
    while [ ! -f "/usr/libexec/kubernetes/kubelet-plugins/volume/exec/ceph.rook.io~rook-ceph-system/rook-ceph-system" ]; do
        sleep 1
    done
    sudo systemctl restart kubelet
    logSuccess "Rook is ready"
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

export DEBIAN_FRONTEND=noninteractive

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
        bypass-firewalld-warning|bypass_firewalld_warning)
            BYPASS_FIREWALLD_WARNING=1
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
        skip-preflights|skip_preflights)
            SKIP_PREFLIGHTS=1
            ;;
        prompt-on-preflight-warnings|prompt_on_preflight_warnings)
            IGNORE_PREFLIGHTS=0
            ;;
        ignore-preflights|ignore_preflights)
            # do nothing
            ;;
        kubernetes-upgrade-patch-version|kubernetes_upgrade_patch_version)
            K8S_UPGRADE_PATCH_VERSION=1
            ;;
        private-address|private_address)
            PRIVATE_ADDRESS="$_value"
            ;;
        wait-for-rook|wait_for_rook)
            WAIT_FOR_ROOK=1
            ;;
        unsafe-skip-ca-verification|unsafe_skip_ca_verification)
            UNSAFE_SKIP_CA_VERIFICATION=1
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

parseKubernetesTargetVersion
setK8sPatchVersion

checkDockerK8sVersion
checkFirewalld

if [ -n "$API_SERVICE_ADDRESS" ]; then
    splitHostPort "$API_SERVICE_ADDRESS"
    KUBERNETES_MASTER_ADDR="$HOST"
    KUBERNETES_MASTER_PORT="$PORT"
    LOAD_BALANCER_ADDRESS="$HOST"
    LOAD_BALANCER_PORT="$PORT"
else
    promptForMasterAddress
    splitHostPort "$KUBERNETES_MASTER_ADDR"
    if [ -n "$PORT" ]; then
        KUBERNETES_MASTER_ADDR="$HOST"
        KUBERNETES_MASTER_PORT="$PORT"
    fi
    LOAD_BALANCER_ADDRESS="$KUBERNETES_MASTER_ADDR"
    LOAD_BALANCER_PORT="$KUBERNETES_MASTER_PORT"
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

if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
    if [ "$SERVICE_CIDR" = "10.96.0.0/12" ]; then
        # Docker < 19.03 does not support cidr addresses in the no_proxy variable.
        # This is a workaround to add support for http proxies until we upgrade docker.
        getNoProxyAddresses "$KUBERNETES_MASTER_ADDR" "$SERVICE_CIDR" "10.100.100.100" "10.100.100.101"
    else
        getNoProxyAddresses "$KUBERNETES_MASTER_ADDR" "$SERVICE_CIDR"
    fi

    # enable kubeadm to reach the K8s API server
    export no_proxy="$NO_PROXY_ADDRESSES"
    requireDockerProxy
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
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

must_disable_selinux
installKubernetesComponents "$KUBERNETES_VERSION"

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
    if [ "$MASTER" -eq "1" ]; then
        airgapLoadKubernetesControlImages "$KUBERNETES_VERSION"
    fi
    addInsecureRegistry "$SERVICE_CIDR"
else
    docker pull registry:2.6.2
    docker tag registry:2.6.2 registry:2
fi

loadIPVSKubeProxyModules

if ! docker ps | grep -q 'k8s.gcr.io/pause'; then
    downloadPkiBundle

    joinKubernetes
else
    maybeUpgradeKubernetesNode "$KUBERNETES_VERSION"
fi

if [ "$MASTER" -eq "1" ]; then
    if [ "$AIRGAP" = "1" ]; then
        # delete the rek operator so that its anti-affinity with the docker-registry applies
        kubectl scale deployment rek-operator --replicas=0
        kubectl scale deployment rek-operator --replicas=1
    fi
fi

purgeNative

if [ "$MASTER" -eq "1" ]; then
    exportKubeconfig

    installCliFile \
        "kubectl exec -c replicated" \
        '$(kubectl get pods -o=jsonpath="{.items[0].metadata.name}" -l tier=master) --'
    logSuccess "Installed replicated cli executable"

    installAliasFile
    logSuccess "Installed replicated command alias"
fi

installAKAService

waitForRook

outro

exit 0
