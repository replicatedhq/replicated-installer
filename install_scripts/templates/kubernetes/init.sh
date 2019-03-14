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
HA_CLUSTER=0
LOAD_BALANCER_ADDRESS=
LOAD_BALANCER_PORT=
REGISTRY_BIND_PORT=
SKIP_DOCKER_INSTALL=0
OFFLINE_DOCKER_INSTALL=0
SKIP_DOCKER_PULL=0
KUBERNETES_ONLY=0
RESET=0
FORCE_RESET=0
TLS_CERT_PATH=
UI_BIND_PORT=8800
USER_ID=

BOOTSTRAP_TOKEN=
BOOTSTRAP_TOKEN_TTL="24h"
KUBERNETES_NAMESPACE="default"
KUBERNETES_VERSION="{{ kubernetes_version }}"
K8S_UPGRADE_PATCH_VERSION="{{ k8s_upgrade_patch_version }}"
STORAGE_CLASS="{{ storage_class }}"
STORAGE_PROVISIONER="{{ storage_provisioner }}"
NO_CE_ON_EE="{{ no_ce_on_ee }}"
HARD_FAIL_ON_LOOPBACK="{{ hard_fail_on_loopback }}"
HARD_FAIL_ON_FIREWALLD="{{ hard_fail_on_firewalld }}"
DISABLE_CONTOUR="{{ disable_contour }}"
NO_CLEAR="{{ no_clear }}"
IP_ALLOC_RANGE=
DEFAULT_SERVICE_CIDR="10.96.0.0/12"
SERVICE_CIDR=$DEFAULT_SERVICE_CIDR
DEFAULT_CLUSTER_DNS="10.96.0.10"
CLUSTER_DNS=$DEFAULT_CLUSTER_DNS
ENCRYPT_NETWORK=
ADDITIONAL_NO_PROXY=
IPVS=1
CEPH_DASHBOARD_URL=
REGISTRY_ADDRESS_OVERRIDE=

CHANNEL_CSS={% if channel_css %}
set +e
read -r -d '' CHANNEL_CSS << CHANNEL_CSS_EOM
{{ channel_css }}
CHANNEL_CSS_EOM
set -e
{%- endif %}

TERMS={% if terms %}
set +e
read -r -d '' TERMS << TERMS_EOM
{{ terms }}
TERMS_EOM
set -e
{%- endif %}

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
{% include 'common/firewall.sh' %}

promptForLoadBalancerAddress() {
    # Check if we already have the load balancer address set in the kubeadm config
    if [ -z "$LOAD_BALANCER_ADDRESS" ] && kubeadm config view >/dev/null 2>&1; then
        LOAD_BALANCER_ADDRESS="$(kubeadm config view | grep 'controlPlaneEndpoint:' | sed 's/controlPlaneEndpoint: \|"//g')"
    fi

    if [ -z "$LOAD_BALANCER_ADDRESS" ]; then
        printf "Please enter a load balancer address to route external and internal traffic to the API servers.\n"
        printf "In the absence of a load balancer address, all traffic will be routed to the first master.\n"
        printf "Load balancer address: "
        prompt
        LOAD_BALANCER_ADDRESS="$PROMPT_RESULT"
        if [ -z "$LOAD_BALANCER_ADDRESS" ]; then
            LOAD_BALANCER_ADDRESS="$PRIVATE_ADDRESS"
            LOAD_BALANCER_PORT=6443
        fi
    fi

    if [ -z "$LOAD_BALANCER_PORT" ]; then
        splitHostPort "$LOAD_BALANCER_ADDRESS"
        LOAD_BALANCER_ADDRESS="$HOST"
        LOAD_BALANCER_PORT="$PORT"
    fi
    if [ -z "$LOAD_BALANCER_PORT" ]; then
        LOAD_BALANCER_PORT=6443
    fi
}

initKubeadmConfig() {
    local kubeadmVersion=$(getKubeadmVersion)
    semverParse "$kubeadmVersion"

    # don't overwrite an alpha3 config migrated by kubeadm 1.12 from 1.11
    if [ "$minor" -gt "12" ]; then
        initKubeadmConfigBeta
    elif [ "$minor" -lt "12" ]; then
        initKubeadmConfigAlpha
    fi
}

initKubeadmConfigBeta() {
    mkdir -p /opt/replicated
    cat <<EOF > /opt/replicated/kubeadm.conf
kind: InitConfiguration
apiVersion: kubeadm.k8s.io/v1beta1
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: $BOOTSTRAP_TOKEN
  ttl: $BOOTSTRAP_TOKEN_TTL
  usages:
  - signing
  - authentication
localAPIEndpoint:
  advertiseAddress: $PRIVATE_ADDRESS
nodeRegistration:
  kubeletExtraArgs:
    node-ip: $PRIVATE_ADDRESS
EOF
    makeKubeadmConfig
}

initKubeadmConfigAlpha() {
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
  bind-address: $PRIVATE_ADDRESS
  service-node-port-range: "80-60000"
EOF

    if [ "$IPVS" = "1" ]; then
        cat <<EOF >> /opt/replicated/kubeadm.conf
kubeProxy:
  config:
    featureGates: SupportIPVSProxyMode=true
    mode: ipvs
EOF
    fi

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
    local kubeV=$(kubeadm version --output=short)

    if [ ! -e "/etc/kubernetes/manifests/kube-apiserver.yaml" ]; then
        logStep "Initialize Kubernetes"

        if [ "$HA_CLUSTER" -eq "1" ]; then
            promptForLoadBalancerAddress
        fi

        initKubeadmConfig

        loadIPVSKubeProxyModules

        if [ "$kubeV" = "v1.9.3" ]; then
            kubeadm init \
                --skip-preflight-checks \
                --config /opt/replicated/kubeadm.conf \
                | tee /tmp/kubeadm-init
            _status=$?
        elif [ "$kubeV" = "v1.11.5" ]; then
            kubeadm init \
                --ignore-preflight-errors=all \
                --config /opt/replicated/kubeadm.conf \
                | tee /tmp/kubeadm-init
            _status=$?
            patchCoreDNS
        else
            kubeadm init \
                --ignore-preflight-errors=all \
                --config /opt/replicated/kubeadm.conf \
                --skip-token-print \
                | tee /tmp/kubeadm-init
            _status=$?
        fi
        if [ "$_status" -ne "0" ]; then
            printf "${RED}Failed to initialize the kubernetes cluster.${NC}\n" 1>&2
            exit $_status
        fi
    # we don't write any init files that can be read by kubeadm v1.12
    elif [ "$kubeV" != "v1.12.3" ]; then
        logStep "Verify kubernetes config"
        chmod 444 /etc/kubernetes/admin.conf
        if [ "$HA_CLUSTER" -eq "1" ]; then
            promptForLoadBalancerAddress
        fi
        initKubeadmConfig
        loadIPVSKubeProxyModules
        kubeadm config upload from-file --config /opt/replicated/kubeadm.conf
        _current=$(getK8sServerVersion)
    fi
    cp /etc/kubernetes/admin.conf $HOME/admin.conf
    chown $SUDO_USER:$SUDO_GID $HOME/admin.conf

    exportKubeconfig

    logSuccess "Kubernetes Master Initialized"
}

# workaround for https://github.com/kubernetes/kubeadm/issues/998
patchCoreDNS() {
    n=0
    while ! kubectl -n kube-system get deployment coredns &>/dev/null; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "120" ]; then
            # let next line fail
            break
        fi
        sleep 2
    done
    kubectl -n kube-system get deployment coredns -o yaml | \
        sed 's/allowPrivilegeEscalation: false/allowPrivilegeEscalation: true/g' | \
        kubectl apply -f -
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

getYAMLOpts() {
    opts=""
    if [ "$AIRGAP" = "1" ]; then
        opts=$opts" airgap"
    fi
    if [ "$HA_CLUSTER" != "1" ]; then
        opts=$opts" bind-daemon-node"
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
    if [ "$HA_CLUSTER" -eq "1" ]; then
        opts=$opts" ha"
    fi
    if [ -n "$LOAD_BALANCER_ADDRESS" ] && [ -n "$LOAD_BALANCER_PORT" ]; then
        opts=$opts" api-service-address=${LOAD_BALANCER_ADDRESS}:${LOAD_BALANCER_PORT}"
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
    # Do not change rook storage class
    if kubectl get storageclass | grep rook.io > /dev/null ; then
        opts=$opts" storage-provisioner=0"
    elif [ -n "$STORAGE_PROVISIONER" ]; then
        opts=$opts" storage-provisioner=$STORAGE_PROVISIONER"
    fi
    if [ -n "$CEPH_DASHBOARD_URL" ]; then
        opts=$opts" ceph-dashboard-url=$CEPH_DASHBOARD_URL"
    fi
    if [ -n "$STORAGE_CLASS" ]; then
        opts=$opts" storage-class=$STORAGE_CLASS"
    fi
    if kubectl get pvc | grep replicated-pv-claim > /dev/null ; then
        opts=$opts" replicated-pvc=0"
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
    local secret=0
    if [ "$ENCRYPT_NETWORK" != "0" ]; then
        secret=1
        if kubectl -n kube-system get secrets | grep -q weave-passwd ; then
            secret=0
        fi
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

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS weave_yaml=1 weave_secret=$secret > /tmp/weave.yml

    kubectl apply -f /tmp/weave.yml -n kube-system
    logSuccess "weave network deployed"
}

rookDeploy() {
    logStep "deploy rook"

    # never upgrade an existing rook cluster
    if k8sNamespaceExists rook && k8sNamespaceExists rook-system ; then
        logSuccess "Rook 0.7.1 already deployed"
        maybeDefaultRookStorageClass
        return
    fi

    # namespaces used in Rook 0.8+
    if k8sNamespaceExists rook-ceph && k8sNamespaceExists rook-ceph-system ; then
        logSuccess "Rook already deployed"
        maybeDefaultRookStorageClass
        return
    fi

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_system_yaml=1 > /tmp/rook-ceph-system.yml
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_cluster_yaml=1 > /tmp/rook-ceph.yml

    kubectl apply -f /tmp/rook-ceph-system.yml
    spinnerRookReady # creating the cluster before the operator is ready fails
    # according to docs restarting kubelet here is only needed on K8s 1.7, but
    # during tests it was required occasionally on 1.11.
    sudo systemctl restart kubelet
    kubectl apply -f /tmp/rook-ceph.yml
    logSuccess "Rook deployed"
}

maybeDefaultRookStorageClass() {
    if ! defaultStorageClassExists ; then
        logSubstep "making existing rook storage class default"
        kubectl patch storageclass "$STORAGE_CLASS" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    fi
}

hostpathProvisionerDeploy() {
    logStep "deploy hostpath provisioner"

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS hostpath_provisioner_yaml=1 > /tmp/hostpath-provisioner.yml

    kubectl apply -f /tmp/hostpath-provisioner.yml
    spinnerHostpathProvisionerReady
    logSuccess "Hostpath provisioner deployed"
}

contourDeploy() {
    # DISABLE_CONTOUR
    if [ -n "$1" ]; then
        return
    fi

    logStep "deploy Contour ingress controller"
    # prior to 2.31.0 this was a DaemonSet but now is a Deployment
    kubectl -n heptio-contour delete daemonset contour 2>/dev/null || true

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS contour_yaml=1 > /tmp/contour.yml
    kubectl apply -f /tmp/contour.yml
    logSuccess "Contour deployed"
}

clusteradminDeploy() {
    logStep "Deploying cluster admin resources"

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS clusteradmin_yaml=1 > /tmp/clusteradmin.yml
    kubectl apply -f /tmp/clusteradmin.yml

    logSuccess "Cluster admin resources deployed"
}

registryDeploy() {
    logStep "Deploy registry"

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS registry_yaml=1 > /tmp/registry.yml
    kubectl apply -f /tmp/registry.yml

    logStep "Waiting for registry..."
    local registryIP=$(kubectl get service docker-registry -o jsonpath='{.spec.clusterIP}')
    while [ -z "$registryIP" ]; do
        sleep 1
        registryIP=$(kubectl get service docker-registry -o jsonpath='{.spec.clusterIP}')
    done
    REGISTRY_ADDRESS_OVERRIDE="$registryIP:5000"
    YAML_GENERATE_OPTS="$YAML_GENERATE_OPTS registry-address-override=$REGISTRY_ADDRESS_OVERRIDE"

    addInsecureRegistry "$SERVICE_CIDR"
    # check if there are worker nodes that need to be configured for the insecure registry
    local workers=$(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}')
    local numMasters=$(kubectl get nodes --selector='node-role.kubernetes.io/master' | sed '1d' | wc -l)
    # check the ADDED_INSECURE_REGISTRY flag and the number of masters to ensure this is only shown once
    if [ "$ADDED_INSECURE_REGISTRY" = "1" ] && [ -n "$workers" ] && [ "$numMasters" -eq "1" ]; then
        cat <<EOF
Configure Docker on all worker nodes to use http when pulling from the in-cluster registry before proceeding.

Example /etc/docker/daemon.json:
{
    "insecure-registries" ["$SERVICE_CIDR"]
}

Continue after updating nodes: $workers
EOF
    prompt
    fi

    waitForRegistry
    logSuccess "Registry deployed"
}

waitForRegistry() {
    local delay=0.75
    local spinstr='|/-\'
    while true; do
        if curl -s -o /dev/null -I -w "%{http_code}" "http://${REGISTRY_ADDRESS_OVERRIDE}/v2/" | grep -q 200; then
            return
        fi
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

kubernetesDeploy() {
    logStep "deploy replicated components"
    if [ "$HA_CLUSTER" -eq "1" ]; then
        kubectl patch deployment replicated --type json -p='[{"op": "remove", "path": "/spec/template/spec/affinity"}]' 2>/dev/null || true
    fi

    logStep "generate manifests"
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS > /tmp/kubernetes.yml

    kubectl apply -f /tmp/kubernetes.yml -n $KUBERNETES_NAMESPACE
    kubectl -n $KUBERNETES_NAMESPACE get pods,svc
    logSuccess "Replicated Daemon"
}

includeBranding() {
    if [ -n "$CHANNEL_CSS" ]; then
        echo "$CHANNEL_CSS" | base64 --decode > /tmp/channel.css
    fi
    if [ -n "$TERMS" ]; then
        echo "$TERMS" | base64 --decode > /tmp/terms.json
    fi

    REPLICATED_POD_ID="$(kubectl get pods 2>/dev/null | grep -E "^replicated-[^-]+-[^-]+$" | awk '{ print $1}')"

    # then copy in the branding file
    if [ -n "$REPLICATED_POD_ID" ]; then
        kubectl exec "${REPLICATED_POD_ID}" -c replicated -- mkdir -p /var/lib/replicated/branding/
        if [ -f /tmp/channel.css ]; then
            logStep "Uploading branding to Replicated."
            kubectl cp /tmp/channel.css "${REPLICATED_POD_ID}:/var/lib/replicated/branding/channel.css" -c replicated
        fi
        if [ -f /tmp/terms.json ]; then
            logStep "Uploading terms to Replicated."
            kubectl cp /tmp/terms.json "${REPLICATED_POD_ID}:/var/lib/replicated/branding/terms.json" -c replicated
        fi
    else
        logFail "Unable to find replicated pod to copy branding css to."
    fi
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
    printf "    ${GREEN}http://%s:%s\n${NC}" "$PUBLIC_ADDRESS" "$UI_BIND_PORT"
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
    printf "To access the cluster with kubectl, reload your shell:\n"
    printf "\n"
    printf "${GREEN}    bash -l${NC}\n"
    printf "\n"
    if [ "$AIRGAP" -eq "1" ]; then
        printf "\n"
        printf "To add nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
        printf "\n"
        printf "\n"
        printf "${GREEN}    cat ./kubernetes-node-join.sh | sudo bash -s airgap kubernetes-master-address=${PRIVATE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=$KUBERNETES_VERSION \n"
        printf "${NC}"
        printf "\n"
        printf "\n"
    else
        printf "\n"
        printf "To add nodes to this installation, run the following script on your other nodes"
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
            # airgap implies "offline docker"
            AIRGAP=1
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
        ha)
            HA_CLUSTER=1
            ;;
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        ip-alloc-range|ip_alloc_range)
            IP_ALLOC_RANGE="$_value"
            ;;
        load-balancer-address|load_balancer_address)
            LOAD_BALANCER_ADDRESS="$_value"
            HA_CLUSTER=1
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
        storage-provisioner|storage_provisioner)
            STORAGE_PROVISIONER="$_value"
            ;;
        storage-class|storage_class)
            STORAGE_CLASS="$_value"
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
        hard-fail-on-firewalld|hard_fail_on_firewalld)
            HARD_FAIL_ON_FIREWALLD=1
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
        force-reset|force_reset)
            FORCE_RESET=1
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
        kubernetes-upgrade-patch-version|kubernetes_upgrade_patch_version)
            K8S_UPGRADE_PATCH_VERSION=1
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

export KUBECONFIG=/etc/kubernetes/admin.conf

setK8sPatchVersion

checkFirewalld

if [ "$HA_CLUSTER" = "1" ]; then
    semverCompare "{{ replicated_version }}" "2.34.0"
    if [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
        bail "HA installs require Replicated >= 2.34.0"
    fi
fi

if [ "$KUBERNETES_VERSION" == "1.9.3" ]; then
    IPVS=0
fi

if [ "$STORAGE_PROVISIONER" == "rook" ] || [ "$STORAGE_PROVISIONER" == "1" ]; then
    CEPH_DASHBOARD_URL=http://rook-ceph-mgr-dashboard.rook-ceph.svc.cluster.local:7000
fi

if [ "$RESET" == "1" ]; then
    k8s_reset "$FORCE_RESET"
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

    if [ -z "$PROXY_ADDRESS" ] && [ "$AIRGAP" != "1" ]; then
        promptForProxy
    fi

    if [ -n "$PROXY_ADDRESS" ]; then
        getNoProxyAddresses "$PRIVATE_ADDRESS" "$SERVICE_CIDR"
    fi
fi

exportProxy
# kubeadm requires this in the environment to reach the K8s API server
export no_proxy="$NO_PROXY_ADDRESSES"

# never upgrade docker underneath kubernetes
if commandExists docker ; then
    SKIP_DOCKER_INSTALL=1
fi
if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
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
    requireDockerProxy
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
    checkDockerProxyConfig
fi

must_disable_selinux
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
if [ "$HA_CLUSTER" != "1" ]; then
    labelMasterNode
fi

maybeUpgradeKubernetes "$KUBERNETES_VERSION"
if [ "$DID_UPGRADE_KUBERNETES" = "0" ]; then
    # If we did not upgrade k8s then just apply the config in case it changed.
    kubeadm upgrade apply --force --yes --config=/opt/replicated/kubeadm.conf
    waitForNodes
fi

echo
(set -x; kubectl get nodes)
logSuccess "Kubernetes nodes"
echo
(set -x; kubectl get pods -n kube-system)
logSuccess "Kubernetes system"
echo

case "$STORAGE_PROVISIONER" in
    rook|1)
        rookDeploy
        ;;
    hostpath)
        hostpathProvisionerDeploy
        ;;
    0|"")
        ;;
    *)
        bail "Error: unknown storage provisioner \"$STORAGE_PROVISIONER\""
        ;;
esac

contourDeploy "$DISABLE_CONTOUR"

if [ "$KUBERNETES_ONLY" -eq "1" ]; then
    spinnerKubeSystemReady "$KUBERNETES_VERSION"
    outroKubeadm "$NO_CLEAR"
    exit 0
fi

clusteradminDeploy

if [ "$AIRGAP" = "1" ]; then
    logStep "Loading replicated, replicated-ui and replicated-operator images from package\n"
    airgapLoadReplicatedImages
    airgapLoadReplicatedAddonImages
    logStep "Loading replicated debian, command, statsd-graphite, and premkit images from package\n"
    airgapLoadSupportImages
    airgapMaybeLoadSupportBundle
    airgapMaybeLoadRetraced

    # If this is an airgap installation we need to deploy a registry and push all Replicated images
    # to it so that Replicated components can get rescheduled to additional nodes.
    semverCompare "{{ replicated_version }}" "2.34.0"
    if [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
        registryDeploy
        airgapPushReplicatedImagesToRegistry "$REGISTRY_ADDRESS_OVERRIDE"
    fi
fi

kubernetesDeploy
installCliFile \
    "kubectl exec -c replicated" \
    '$(kubectl get pods -o=jsonpath="{.items[0].metadata.name}" -l tier=master) --'
spinnerReplicatedReady

includeBranding

printf "Installing replicated command alias\n"
installAliasFile
outro "$NO_CLEAR"

exit 0
