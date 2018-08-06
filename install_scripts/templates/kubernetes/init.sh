#!/bin/bash

set -e
AIRGAP=0
DAEMON_TOKEN=
GROUP_ID=
LOG_LEVEL=
MIN_DOCKER_VERSION="1.10.3" # k8s min
NO_PROXY=0
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
YAML_GENERATE_OPTS=

PUBLIC_ADDRESS=
PRIVATE_ADDRESS=
REGISTRY_BIND_PORT=
SKIP_DOCKER_INSTALL=0
OFFLINE_DOCKER_INSTALL=0
SKIP_DOCKER_PULL=0
KUBERNETES_ONLY=0
RESET=0
TLS_CERT_PATH=
UI_BIND_PORT=8800
USER_ID=

BOOTSTRAP_TOKEN=
BOOTSTRAP_TOKEN_TTL="24h"
KUBERNETES_NAMESPACE="default"
KUBERNETES_VERSION="{{ kubernetes_version }}"
NO_CE_ON_EE="{{ no_ce_on_ee }}"
HARD_FAIL_ON_LOOPBACK="{{ hard_fail_on_loopback }}"
DISABLE_CONTOUR="{{ disable_contour }}"
NO_CLEAR="{{ no_clear }}"
IP_ALLOC_RANGE=
DEFAULT_SERVICE_CIDR="10.96.0.0/12"
SERVICE_CIDR=$DEFAULT_SERVICE_CIDR
DEFAULT_CLUSTER_DNS="10.96.0.10"
CLUSTER_DNS=$DEFAULT_CLUSTER_DNS
ENCRYPT_NETWORK=
ADDITIONAL_NO_PROXY=

{% include 'common/common.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/system.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/docker-install.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/cli-script.sh' %}
{% include 'common/alias.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/proxy.sh' %}
{% include 'common/airgap.sh' %}
{% include 'common/log.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/selinux.sh' %}
{% include 'common/swap.sh' %}
{% include 'common/kubernetes-upgrade.sh' %}

initKubeadmConfig() {
    mkdir -p /opt/replicated
    cat <<EOF > /opt/replicated/kubeadm.conf
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
kubernetesVersion: v$KUBERNETES_VERSION
token: $BOOTSTRAP_TOKEN
tokenTTL: ${BOOTSTRAP_TOKEN_TTL}
networking:
  serviceSubnet: $SERVICE_CIDR
apiServerExtraArgs:
  service-node-port-range: "80-60000"
EOF

    # if we have a private address, add it to SANs
    if [ -n "$PRIVATE_ADDRESS" ]; then
          cat <<EOF >> /opt/replicated/kubeadm.conf
apiServerCertSANs:
- $PRIVATE_ADDRESS
EOF
    fi

    # if we have a public address, add it to SANs
    if [ -n "$PUBLIC_ADDRESS" ] && [ -n "$PRIVATE_ADDRESS" ]; then
          cat <<EOF >> /opt/replicated/kubeadm.conf
- $PUBLIC_ADDRESS
EOF
    fi



}

initKube() {
    logStep "Verify Kubelet"
    if ! ps aux | grep -qE "[k]ubelet"; then
        logStep "Initialize Kubernetes"
        initKubeadmConfig
        set +e

        kubeadm init \
            --skip-preflight-checks \
            --config /opt/replicated/kubeadm.conf \
            | tee /tmp/kubeadm-init
        _status=$?
        set -e
        if [ "$_status" -ne "0" ]; then
            printf "${RED}Failed to initialize the kubernetes cluster.${NC}\n" 1>&2
            exit $_status
        fi
    else
        logStep "verify kubernetes config"
        export KUBECONFIG=/etc/kubernetes/admin.conf
        chmod 444 /etc/kubernetes/admin.conf
        initKubeadmConfig
        kubeadm config upload from-file --config /opt/replicated/kubeadm.conf
        _current=$(getK8sServerVersion)

        maybeUpgradeKubernetes "$KUBERNETES_VERSION"
    fi
    cp /etc/kubernetes/admin.conf $HOME/admin.conf
    chown $SUDO_USER:$SUDO_USER $HOME/admin.conf


    export KUBECONFIG=/etc/kubernetes/admin.conf
    chmod 444 /etc/kubernetes/admin.conf
    echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /etc/profile
    echo "source <(kubectl completion bash)" >> /etc/profile
    logSuccess "Kubernetes Master Initialized"
}

maybeGenerateBootstrapToken() {
    if [ -z "$BOOTSTRAP_TOKEN" ]; then
        logStep "generate kubernetes bootstrap token"
        BOOTSTRAP_TOKEN=$(kubeadm token generate)
    fi
    echo "Kubernetes bootstrap token: ${BOOTSTRAP_TOKEN}"
    echo "This token will expire in 24 hours"
}

ensureCNIPlugins() {
    if [ ! -d /tmp/cni-plugins ]; then
        installCNIPlugins
    fi
    logSuccess "CNI configured"
}

untaintMaster() {
    logStep "remove NoSchedule taint from master node"
    kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- || \
        echo "Taint not found or already removed. The above error can be ignored."
    logSuccess "master taint removed"
}

getYAMLOpts() {
    opts=
    if [ "$AIRGAP" = "1" ]; then
        opts=$opts" airgap"
    fi
    if [ -n "$LOG_LEVEL" ]; then
        opts=$opts" log-level=$LOG_LEVEL"
    fi
    if [ -n "$RELEASE_SEQUENCE" ]; then
        opts=$opts" release-sequence=$RELEASE_SEQUENCE"
    fi
    if [ -n "$UI_BIND_PORT" ]; then
        opts=$opts" ui-bind-port=$UI_BIND_PORT"
    fi
    if [ -n "$IP_ALLOC_RANGE" ]; then
        opts=$opts" ip-alloc-range=$IP_ALLOC_RANGE"
    fi
    if [ -n "$PROXY_ADDRESS" ]; then
        opts=$opts" http-proxy=$PROXY_ADDRESS"
    fi
    if [ -n "$NO_PROXY_ADDRESSES" ]; then
        opts=$opts" no-proxy-addresses=$NO_PROXY_ADDRESSES"
    fi
    if [ "$ENCRYPT_NETWORK" = "0" ]; then
        opts=$opts" encrypt-network=0"
    fi
    YAML_GENERATE_OPTS="$opts"
}

getK8sYmlGenerator() {
    getUrlCmd
    if [ "$AIRGAP" -ne "1" ]; then
        $URLGET_CMD "{{ replicated_install_url }}/{{ kubernetes_generate_path }}?{{ kubernetes_manifests_query }}" \
            > /tmp/kubernetes-yml-generate.sh
    else
        cp kubernetes-yml-generate.sh /tmp/kubernetes-yml-generate.sh
    fi

    getYAMLOpts
}

weavenetDeploy() {
    logStep "deploy weave network"

    sleeve=0
    if [ "$ENCRYPT_NETWORK" != "0" ]; then
        # Encrypted traffic cannot use the fast database on kernels below 4.2
        kernel_major=$(uname -r | cut -d'.' -f1)
        kernel_minor=$(uname -r | cut -d'.' -f2)
        if [ "$kernel_major" -lt "4" ]; then
            sleeve=1
        elif [ "$kernel_major" -lt "5" ] && [ "$kernel_minor" -lt "3" ]; then
            sleeve=1
        fi

        if [ "$sleeve" = "1" ]; then
            printf "${YELLOW}This host will not be able to establish optimized network connections with other peers in the Kubernetes cluster.\nRefer to the Replicated networking guide for help.\n\nhttp://help.replicated.com/docs/kubernetes/customer-installations/networking/${NC}\n"
        fi
    fi

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS weave_yaml=1 > /tmp/weave.yml

    kubectl apply -f /tmp/weave.yml -n kube-system
    logSuccess "weave network deployed"
}

rookDeploy() {
    logStep "deploy rook"

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_system_yaml=1 > /tmp/rook-system.yml
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_cluster_yaml=1 > /tmp/rook.yml

    kubectl apply -f /tmp/rook-system.yml
    spinnerRookReady # creating the cluster before the operator is ready fails
    kubectl apply -f /tmp/rook.yml
    logSuccess "Rook deployed"
}

contourDeploy() {
    # DISABLE_CONTOUR
    if [ -n "$1" ]; then
        return
    fi

    logStep "deploy Contour ingress controller"
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS contour_yaml=1 > /tmp/contour.yml
    kubectl apply -f /tmp/contour.yml
    logSuccess "Contour deployed"
}

kubernetesDeploy() {
    logStep "deploy replicated components"

    logStep "generate manifests"
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS > /tmp/kubernetes.yml

    kubectl apply -f /tmp/kubernetes.yml -n $KUBERNETES_NAMESPACE
    kubectl -n $KUBERNETES_NAMESPACE get pods,svc
    logSuccess "Replicated Daemon"
}

outro() {
    # NO_CLEAR
    if [ -z "$1" ]; then
        clear
    fi

    echo
    if [ -z "$PUBLIC_ADDRESS" ]; then
      if [ -z "$PRIVATE_ADDRESS" ]; then
        PUBLIC_ADDRESS="<this_server_address>"
      else
        PUBLIC_ADDRESS="$PRIVATE_ADDRESS"
      fi
    fi
    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    printf "\n"
    printf "\nTo access the cluster with kubectl, reload your shell:\n\n"
    printf "\n"
    printf "${GREEN}    bash -l${NC}"
    printf "\n"
    printf "\n"
    printf "\nTo continue the installation, visit the following URL in your browser:\n\n"
    printf "\n"
    printf "    ${GREEN}https://%s:%s\n${NC}" "$PUBLIC_ADDRESS" "$UI_BIND_PORT"
    printf "\n"
    printf "\n"
}

outroKubeadm() {
    # NO_CLEAR
    if [ -z "$1" ]; then
        clear
    fi

    echo
    if [ -z "$PUBLIC_ADDRESS" ]; then
      if [ -z "$PRIVATE_ADDRESS" ]; then
        PUBLIC_ADDRESS="<this_server_address>"
        PRIVATE_ADDRESS="<this_server_address>"
      else
        PUBLIC_ADDRESS="$PRIVATE_ADDRESS"
      fi
    fi

    KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'kubeadm join' | awk '{ print $(NF) }')

    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    printf "\n"
    printf "\nTo access the cluster with kubectl, reload your shell:\n\n"
    printf "\n"
    printf "${GREEN}    bash -l${NC}"
    printf "\n"
    printf "\n"
    if [ "$AIRGAP" -eq "1" ]; then
        printf "\nTo add nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
        printf "\n"
        printf "\n"
        printf "${GREEN}    cat ./kubernetes-node-join.sh  | sudo bash -s kubernetes-master-address=${PRIVATE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=$KUBERNETES_VERSION \n"
        printf "${NC}"
        printf "\n"
        printf "\n"
    else
        printf "\nTo add nodes to this installation, run the following script on your other nodes"
        printf "\n"
        printf "${GREEN}    curl {{ replicated_install_url }}/{{ kubernetes_node_join_path }} | sudo bash -s kubernetes-master-address=${PRIVATE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=$KUBERNETES_VERSION \n"
        printf "${NC}"
        printf "\n"
        printf "\n"
    fi
}

outroReset() {
    # NO_CLEAR
    if [ -z "$1" ]; then
        clear
    fi

    printf "\n"
    printf "\t\t${GREEN}Uninstallation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
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
            # arigap implies "no proxy" and "offline docker"
            AIRGAP=1
            NO_PROXY=1
            OFFLINE_DOCKER_INSTALL=1
            ;;
        bypass-storagedriver-warnings|bypass_storagedriver_warnings)
            BYPASS_STORAGEDRIVER_WARNINGS=1
            ;;
        bootstrap-token|bootrap_token)
            BOOTSTRAP_TOKEN="$_value"
            ;;
        bootstrap-token-ttl|bootrap_token_ttl)
            BOOTSTRAP_TOKEN_TTL="$_value"
            ;;
        docker-version|docker_version)
            PINNED_DOCKER_VERSION="$_value"
            ;;
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        ip-alloc-range|ip_alloc_range)
            IP_ALLOC_RANGE="$_value"
            ;;
        log-level|log_level)
            LOG_LEVEL="$_value"
            ;;
        no-clear|no_clear)
            NO_CLEAR=1
            ;;
        no-docker|no_docker)
            SKIP_DOCKER_INSTALL=1
            ;;
        no-proxy|no_proxy)
            NO_PROXY=1
            ;;
        public-address|public_address)
            PUBLIC_ADDRESS="$_value"
            ;;
        private-address|private_address)
            PRIVATE_ADDRESS="$_value"
            ;;
        release-sequence|release_sequence)
            RELEASE_SEQUENCE="$_value"
            ;;
        skip-pull|skip_pull)
            SKIP_DOCKER_PULL=1
            ;;
        kubernetes-namespace|kubernetes_namespace)
            KUBERNETES_NAMESPACE="$_value"
            ;;
        ui-bind-port|ui_bind_port)
            UI_BIND_PORT="$_value"
            ;;
        no-ce-on-ee|no_ce_on_ee)
            NO_CE_ON_EE=1
            ;;
        hard-fail-on-loopback|hard_fail_on_loopback)
            HARD_FAIL_ON_LOOPBACK=1
            ;;
        disable-contour|disable_contour)
            DISABLE_CONTOUR=1
            ;;
        kubernetes-only|kubernetes_only)
            KUBERNETES_ONLY=1
            ;;
        reset)
            RESET=1
            ;;
        service-cidr|service_cidr)
            SERVICE_CIDR="$_value"
            ;;
        cluster-dns|cluster_dns)
            CLUSTER_DNS="$_value"
            ;;
        encrypt-network|encrypt_network)
            ENCRYPT_NETWORK="$_value"
            ;;
        additional-no-proxy|additional_no_proxy)
            if [ -z "$ADDITIONAL_NO_PROXY" ]; then
                ADDITIONAL_NO_PROXY="$_value"
            else
                ADDITIONAL_NO_PROXY="$ADDITIONAL_NO_PROXY,$_value"
            fi
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

if [ "$RESET" == "1" ]; then
    k8s_reset
    outroReset "$NO_CLEAR"
	exit 0
fi

if [ -z "$PUBLIC_ADDRESS" ] && [ "$AIRGAP" -ne "1" ]; then
    printf "Determining service address\n"
    discoverPublicIp

    if [ -n "$PUBLIC_ADDRESS" ]; then
        shouldUsePublicIp
    else
        printf "The installer was unable to automatically detect the service IP address of this machine.\n"
        printf "Please enter the address or leave blank for unspecified.\n"
        promptForPublicIp
    fi
fi

if [ -z "$PRIVATE_ADDRESS" ]; then
    promptForPrivateIp
fi

if [ "$NO_PROXY" != "1" ]; then
    if [ -z "$PROXY_ADDRESS" ]; then
        discoverProxy
    fi

    if [ -z "$PROXY_ADDRESS" ]; then
        promptForProxy
    fi

    if [ -n "$PROXY_ADDRESS" ]; then
        getNoProxyAddresses "$PRIVATE_ADDRESS" "$SERVICE_CIDR"
    fi
fi

exportProxy
# kubeadm requires this in the environment to reach the K8s API server
export no_proxy="$NO_PROXY_ADDRESSES"

if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
    if [ "$OFFLINE_DOCKER_INSTALL" != "1" ]; then
        installDockerK8s "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"
    else
        installDocker_1_12_Offline
    fi
    checkDockerDriver
    checkDockerStorageDriver "$HARD_FAIL_ON_LOOPBACK"
fi

if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
    requireDockerProxy
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
    checkDockerProxyConfig
fi

installKubernetesComponents "$KUBERNETES_VERSION"
if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
    sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
fi
systemctl enable kubelet && systemctl start kubelet

if [ "$AIRGAP" = "1" ]; then
    airgapLoadKubernetesCommonImages "$KUBERNETES_VERSION"
    airgapLoadKubernetesControlImages "$KUBERNETES_VERSION"
else
    docker pull registry:2.6.2
    docker tag registry:2.6.2 registry:2
fi

ensureCNIPlugins

maybeGenerateBootstrapToken
initKube

kubectl cluster-info
logSuccess "Cluster Initialized"

getK8sYmlGenerator

weavenetDeploy

untaintMaster

spinnerMasterNodeReady

echo
kubectl get nodes
logSuccess "Kubernetes nodes"
echo

echo
kubectl get pods -n kube-system
logSuccess "Kubernetes system"
echo

rookDeploy

contourDeploy "$DISABLE_CONTOUR"

if [ "$KUBERNETES_ONLY" -eq "1" ]; then
    spinnerKubeSystemReady "$KUBERNETES_VERSION"
    outroKubeadm "$NO_CLEAR"
    exit 0
fi

if [ "$AIRGAP" = "1" ]; then
    logStep "Loading replicated and replicated-ui images from package\n"
    airgapLoadReplicatedImages
    logStep "Loading replicated debian, command, statsd-graphite, and premkit images from package\n"
    airgapLoadSupportImages
    airgapMaybeLoadSupportBundle
    airgapMaybeLoadRetraced
fi

kubernetesDeploy
spinnerReplicatedReady

printf "Installing replicated command alias\n"
installCliFile \
    "kubectl exec -c replicated" \
    '$(kubectl get pods -o=jsonpath="{.items[0].metadata.name}" -l tier=master) --'
installAliasFile
outro "$NO_CLEAR"

exit 0
