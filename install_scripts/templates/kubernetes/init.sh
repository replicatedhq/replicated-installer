#!/bin/bash

set -e

AIRGAP=0
DAEMON_TOKEN=
GROUP_ID=
LOG_LEVEL=
MIN_DOCKER_VERSION="1.10.3" # k8s min
NO_PROXY=0
REPLICATED_VERSION="{{ replicated_version }}"
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
YAML_GENERATE_OPTS=

PUBLIC_ADDRESS=
PRIVATE_ADDRESS=
HA_CLUSTER=0
TAINT_CONTROL_PLANE="{{ '1' if taint_control_plane else '0' }}"
MAINTAIN_ROOK_STORAGE_NODES=0
PURGE_DEAD_NODES=0
LOAD_BALANCER_ADDRESS=
LOAD_BALANCER_PORT=
REGISTRY_BIND_PORT=
SKIP_DOCKER_INSTALL=0
OFFLINE_DOCKER_INSTALL=0
SKIP_DOCKER_PULL=0
KUBERNETES_ONLY=0
RESET=0
FORCE_RESET=0
LOAD_IMAGES=0
BIND_DAEMON_TO_MASTERS=1
BIND_DAEMON_HOSTNAME=
TLS_CERT_PATH=
UI_BIND_PORT=8800
USER_ID=
FORCE_REPLICATED_DOWNGRADE=0

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
DISABLE_ROOK_OBJECT_STORE="{{ disable_rook_object_store }}"
NO_CLEAR="{{ no_clear }}"
IP_ALLOC_RANGE=
DEFAULT_SERVICE_CIDR="10.96.0.0/12"
SERVICE_CIDR=$DEFAULT_SERVICE_CIDR
DEFAULT_CLUSTER_DNS="10.96.0.10"
CLUSTER_DNS=$DEFAULT_CLUSTER_DNS
ENCRYPT_NETWORK=
ADDITIONAL_NO_PROXY=
SKIP_PREFLIGHTS="{{ '1' if skip_preflights else '' }}"
IGNORE_PREFLIGHTS="{{ '1' if ignore_preflights else '' }}"
IPVS=1
CEPH_DASHBOARD_URL=
CEPH_DASHBOARD_USER=
CEPH_DASHBOARD_PASSWORD=
REGISTRY_ADDRESS_OVERRIDE=
APP_REGISTRY_ADVERTISE_HOST=
OBJECT_STORE_ACCESS_KEY=
OBJECT_STORE_SECRET_KEY=
OBJECT_STORE_CLUSTER_IP=
DID_INIT_KUBERNETES=0
RELEASE_SEQUENCE="{{ release_sequence }}"
RELEASE_PATCH_SEQUENCE="{{ release_patch_sequence }}"
UNSAFE_SKIP_CA_VERIFICATION="{{ '1' if unsafe_skip_ca_verification else '0' }}"

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
{% include 'preflights/index.sh' %}

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

initKubeadmConfigV1Beta2() {
    mkdir -p /opt/replicated
    cat <<EOF > /opt/replicated/kubeadm.conf
apiVersion: kubeadm.k8s.io/v1beta2
kind: InitConfiguration
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
EOF
    if [ "$TAINT_CONTROL_PLANE" != "1" ]; then
        cat << EOF >> /opt/replicated/kubeadm.conf
  taints: []
EOF
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
    if [ -n "$CURRENT_KUBERNETES_VERSION" ]; then
        makeKubeadmConfig "$CURRENT_KUBERNETES_VERSION"
    else
        makeKubeadmConfig "$KUBERNETES_VERSION"
    fi
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

initKube15() {
    logStep "Initialize Kubernetes"

    if [ "$HA_CLUSTER" -eq "1" ]; then
        promptForLoadBalancerAddress

        if [ "$LOAD_BALANCER_ADDRESS_CHANGED" = "1" ]; then
            handleLoadBalancerAddressChangedPreInit
        fi
    fi

    local k8sVersion="$KUBERNETES_VERSION"
    if [ -n "$CURRENT_KUBERNETES_VERSION" ]; then
        k8sVersion="$CURRENT_KUBERNETES_VERSION"
    fi

    initKubeadmConfigV1Beta2
    appendKubeadmClusterConfigV1Beta2 "$k8sVersion"
    appendKubeProxyConfigV1Alpha1

    loadIPVSKubeProxyModules

    set -o pipefail
    kubeadm init \
        --ignore-preflight-errors=all \
        --config /opt/replicated/kubeadm.conf \
        | tee /tmp/kubeadm-init
    set +o pipefail

    exportKubeconfig

    waitForNodes

    DID_INIT_KUBERNETES=1
    logSuccess "Kubernetes Master Initialized"

    if [ "$LOAD_BALANCER_ADDRESS_CHANGED" = "1" ]; then
        handleLoadBalancerAddressChangedPostInit
    fi
}

handleLoadBalancerAddressChangedPreInit() {
    # this will stop all the control plane pods except etcd
    rm -f /etc/kubernetes/manifests/kube-*
    while docker ps | grep -q kube-apiserver ; do
        sleep 2
    done

    # kubectl must communicate with the local API server until all servers are upgraded to
    # serve certs with the new load balancer address in their SANs
    if [ -f /etc/kubernetes/admin.conf ]; then
        mv /etc/kubernetes/admin.conf /tmp/kube.conf
        sed -i "s/server: https.*/server: https:\/\/$PRIVATE_ADDRESS:6443/" /tmp/kube.conf
        export KUBECONFIG=/tmp/kube.conf
    fi

    # delete files that need to be regenerated
    rm -f /etc/kubernetes/*.conf
    rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
}

handleLoadBalancerAddressChangedPostInit() {
    runUpgradeScriptOnAllRemoteNodes "$REPLICATED_VERSION" "{{ channel_name }}"
    export KUBECONFIG=/etc/kubernetes/admin.conf

    logStep "Restarting kube-proxy"
    kubectl -n kube-system get pods | grep kube-proxy | awk '{print $1}' | xargs kubectl -n kube-system delete pod
    logSuccess "Kube-proxy restarted"
}

discoverCurrentKubernetesVersion() {
    set +e
    CURRENT_KUBERNETES_VERSION=$(cat /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | grep image: | grep -oE '[0-9]+.[0-9]+.[0-9]')
    set -e

    if [ -n "$CURRENT_KUBERNETES_VERSION" ]; then
        semverParse $CURRENT_KUBERNETES_VERSION
        KUBERNETES_CURRENT_VERSION_MAJOR="$major"
        KUBERNETES_CURRENT_VERSION_MINOR="$minor"
        KUBERNETES_CURRENT_VERSION_PATCH="$patch"
    fi
}

isMinorUpgrade() {
    if [ -z "$CURRENT_KUBERNETES_VERSION" ]; then
        return 1
    fi
    if [ "$KUBERNETES_CURRENT_VERSION_MINOR" -lt "$KUBERNETES_TARGET_VERSION_MINOR" ]; then
        return 0
    fi
    return 1
}

initKube() {
    case "$KUBERNETES_TARGET_VERSION_MINOR" in
        15)
            if isMinorUpgrade; then
                return
            fi
            initKube15
            return
            ;;
    esac

    local kubeV=$(kubeadm version --output=short)

    # init is idempotent for the same version of Kubernetes. If init has already run this file will
    # exist and have the version that we must re-init with.
    if [ ! -e "/etc/kubernetes/manifests/kube-apiserver.yaml" ] || shouldReinitK8s; then
        logStep "Initialize Kubernetes"

        if [ "$HA_CLUSTER" -eq "1" ]; then
            promptForLoadBalancerAddress

            # this will stop all the control plane pods except etcd
            rm -f /etc/kubernetes/manifests/kube-*
            while docker ps | grep -q kube-apiserver ; do
                sleep 2
            done
            if [ "$LOAD_BALANCER_ADDRESS_CHANGED" = "1" ]; then
                # kubectl must communicate with the local API server until all servers are upgraded to
                # serve certs with the new load balancer address in their SANs
                if [ -f /etc/kubernetes/admin.conf ]; then
                    mv /etc/kubernetes/admin.conf /tmp/kube.conf
                    sed -i "s/server: https.*/server: https:\/\/$PRIVATE_ADDRESS:6443/" /tmp/kube.conf
                    export KUBECONFIG=/tmp/kube.conf
                fi
            fi
            # delete files that need to be regenerated in case of load balancer address change
            rm -f /etc/kubernetes/*.conf
            rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
        fi

        initKubeadmConfig

        loadIPVSKubeProxyModules

        local skipPhases=
        local numMasters="$(kubectl get nodes --selector='node-role.kubernetes.io/master' 2>/dev/null | sed '1d' | wc -l)"
        if [ "$numMasters" -gt "0" ]; then
            skipPhases="preflight,mark-control-plane"
        fi

        if [ "$kubeV" = "v1.9.3" ]; then
            ( set -exo pipefail; kubeadm init \
                --skip-preflight-checks \
                --config /opt/replicated/kubeadm.conf \
                | tee /tmp/kubeadm-init
            )
        elif [ "$kubeV" = "v1.11.5" ]; then
            ( set -exo pipefail; kubeadm init \
                --ignore-preflight-errors=all \
                --config /opt/replicated/kubeadm.conf \
                | tee /tmp/kubeadm-init
            )
            patchCoreDNS
        else
            ( set -exo pipefail; kubeadm init \
                --ignore-preflight-errors=all \
                --config /opt/replicated/kubeadm.conf \
                --skip-phases "$skipPhases" \
                --skip-token-print \
                | tee /tmp/kubeadm-init
            )
        fi

        DID_INIT_KUBERNETES=1
    # we don't write any init files that can be read by kubeadm v1.12
    elif [ "$kubeV" != "v1.12.3" ]; then
        logStep "Verify kubernetes config"
        chmod 444 /etc/kubernetes/admin.conf
        initKubeadmConfig
        loadIPVSKubeProxyModules
        kubeadm config upload from-file --config /opt/replicated/kubeadm.conf
        _current=$(getK8sServerVersion)
    fi
    cp /etc/kubernetes/admin.conf $HOME/admin.conf
    chown $SUDO_USER:$SUDO_GID $HOME/admin.conf

    exportKubeconfig

    waitForNodes

    untaintMaster

    logSuccess "Kubernetes Master Initialized"

    if [ "$LOAD_BALANCER_ADDRESS_CHANGED" = "1" ]; then
        handleLoadBalancerAddressChangedPostInit
    fi
}

shouldReinitK8s() {
    if kubectl version --short 2>/dev/null | grep -q 'Server'; then
        if kubectl version --short 2>/dev/null | grep -q 'Server Version: v1.13'; then
            return 0
        fi
    elif curl --noproxy "*" -k https://localhost:6443/version 2>/dev/null | grep -q '"gitVersion": '; then
        if curl --noproxy "*" -k https://localhost:6443/version 2>/dev/null | grep -q '"gitVersion": "v1.13"'; then
            return 0
        fi
    else
        printf "${YELLOW}The kube-apiserver seems to be unreachable. Would you like to re-initialize Kubernetes?${NC} "
        if confirmN " "; then
            return 0
        fi
    fi
    return 1
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

getYAMLOpts() {
    opts=""
    if [ "$AIRGAP" = "1" ]; then
        opts=$opts" airgap"
    fi
    if [ -n "$LOG_LEVEL" ]; then
        opts=$opts" log-level=$LOG_LEVEL"
    fi
    if [ -n "$RELEASE_SEQUENCE" ]; then
        opts=$opts" release-sequence=$RELEASE_SEQUENCE"
    fi
    if [ -n "$RELEASE_PATCH_SEQUENCE" ]; then
        opts=$opts" release-patch-sequence=$RELEASE_PATCH_SEQUENCE"
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
    if [ -n "$STORAGE_PROVISIONER" ]; then
        opts=$opts" storage-provisioner=$STORAGE_PROVISIONER"
    fi
    if [ -n "$CEPH_DASHBOARD_URL" ]; then
        opts=$opts" ceph-dashboard-url=$CEPH_DASHBOARD_URL"
    fi
    if [ -n "$CEPH_DASHBOARD_USER" ]; then
        opts=$opts" ceph-dashboard-user=$CEPH_DASHBOARD_USER ceph-dashboard-password=$CEPH_DASHBOARD_PASSWORD"
    fi
    if [ -n "$STORAGE_CLASS" ]; then
        opts=$opts" storage-class=$STORAGE_CLASS"
    fi
    if kubectl get pvc | grep replicated-pv-claim > /dev/null ; then
        opts=$opts" replicated-pvc=0"
    fi
    if [ -n "$PRIVATE_ADDRESS" ]; then
        opts=$opts" app-registry-advertise-host=$PRIVATE_ADDRESS"
    fi
    if [ "$MAINTAIN_ROOK_STORAGE_NODES" = "1" ]; then
        opts=$opts" maintain-rook-storage-nodes"
    fi
    if [ "$PURGE_DEAD_NODES" = "1" ]; then
        opts=$opts" purge-dead-nodes"
    fi
    if [ -n "$REGISTRY_ADDRESS_OVERRIDE" ]; then
        opts=$opts" registry-address-override=$REGISTRY_ADDRESS_OVERRIDE"
    fi
    if [ -n "$APP_REGISTRY_ADVERTISE_HOST" ]; then
        opts=$opts" app-registry-advertise-host=$APP_REGISTRY_ADVERTISE_HOST"
    fi
    if [ "$BIND_DAEMON_TO_MASTERS" = "1" ]; then
        opts=$opts" bind-daemon-to-masters"
    fi
    if [ -n "$BIND_DAEMON_HOSTNAME" ]; then
        opts=$opts" bind-daemon-hostname=$BIND_DAEMON_HOSTNAME"
    fi
    if [ -n "$OBJECT_STORE_ACCESS_KEY" ]; then
        opts=$opts" object-store-access-key=$OBJECT_STORE_ACCESS_KEY" 
    fi
    if [ -n "$OBJECT_STORE_SECRET_KEY" ]; then
        opts=$opts" object-store-secret-key=$OBJECT_STORE_SECRET_KEY"
    fi
    if [ -n "$OBJECT_STORE_CLUSTER_IP" ]; then
        opts=$opts" object-store-cluster-ip=$OBJECT_STORE_CLUSTER_IP"
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

    # disabling airgap upgrades of Weave until we solve image distribution
    if [ "$AIRGAP" = "1" ] && kubectl -n kube-system get ds weave-net &>/dev/null; then
        return
    fi

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

clusterAdminDeploy() {
    logStep "deploy cluster admin role"

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS cluster_role_binding_yaml=1 > /tmp/cluster-admin-role.yml

    kubectl apply -f /tmp/cluster-admin-role.yml
    logSuccess "Cluster admin role deployed"
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
        if ! isRook103Plus; then
            # we no longer have v0.8.x rook version yaml
            logSuccess "Rook already deployed"
            maybeDefaultRookStorageClass
            return
        fi
    fi

    semverCompare "$REPLICATED_VERSION" "2.36.0"
    if [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
        rookDeploy08
        return
    fi

    local use_rook_103=0
    if isRook103; then
        use_rook_103=1
    else
        getKernelVersion
        # Rook 1.0.4+ does not seem to work on linux kernel 4 less than or equal 4.5
        # https://github.com/rook/rook/issues/3751
        # https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1728739
        if [ "$KERNEL_MAJOR" -eq "4" ] && [ "$KERNEL_MINOR" -lt "5" ]; then
            use_rook_103=1
        fi
    fi

    if [ "$use_rook_103" = "1" ]; then
        # do not upgrade rook/ceph
        sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_103_system_yaml=1 > /tmp/rook-ceph-system.yml
        sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_103_cluster_yaml=1 > /tmp/rook-ceph.yml
    else
        sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_106_system_yaml=1 > /tmp/rook-ceph-system.yml
        sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_106_cluster_yaml=1 > /tmp/rook-ceph.yml
    fi

    kubectl apply -f /tmp/rook-ceph-system.yml

    spinnerRookReady # creating the cluster before the operator is ready fails

    kubectl apply -f /tmp/rook-ceph.yml
    storageClassDeploy
 
    # wait for ceph dashboard password to be generated
    local delay=0.75
    local spinstr='|/-\'
    while ! kubectl -n rook-ceph get secret rook-ceph-dashboard-password &>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done

    logSuccess "Rook deployed"
}

rookDeploy08() {
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_08_system_yaml=1 > /tmp/rook-ceph-system.yml
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_08_cluster_yaml=1 > /tmp/rook-ceph.yml

    kubectl apply -f /tmp/rook-ceph-system.yml

    spinnerRookReady # creating the cluster before the operator is ready fails
    sudo systemctl restart kubelet

    kubectl apply -f /tmp/rook-ceph.yml
    storageClassDeploy

    logSuccess "Rook deployed"
}

maybeDefaultRookStorageClass() {
    # different versions of Rook have different storage class specs so never re-apply
    if ! kubectl get storageclass | grep -q rook.io ; then
        storageClassDeploy
        return
    fi

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
    storageClassDeploy
    logSuccess "Hostpath provisioner deployed"
}

storageClassDeploy() {
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS storage_class_yaml=1 > /tmp/storage-class.yml
    kubectl apply -f /tmp/storage-class.yml
}

contourDeploy() {
    # DISABLE_CONTOUR
    if [ -n "$1" ]; then
        return
    fi

    # disabling airgap upgrades of Contour until we solve image distribution
    if [ "$AIRGAP" = "1" ] && kubectl get ns heptio-contour &>/dev/null; then
        return
    fi

    logStep "deploy Contour ingress controller"
    # prior to 2.31.0 this was a DaemonSet but now is a Deployment
    kubectl -n heptio-contour delete daemonset contour 2>/dev/null || true

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS contour_yaml=1 > /tmp/contour.yml
    kubectl apply -f /tmp/contour.yml
    logSuccess "Contour deployed"
}

rekOperatorDeploy() {
    semverCompare "$REPLICATED_VERSION" "2.36.0"
    if [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
        return
    fi
    if [ "$MAINTAIN_ROOK_STORAGE_NODES" = "0" ]; then
        return
    fi

    if [ "$HA_CLUSTER" = "1" ]; then
        PURGE_DEAD_NODES=1
    fi
    getYAMLOpts

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rek_operator_yaml=1 > /tmp/rek-operator.yml
    kubectl apply -f /tmp/rek-operator.yml -n $KUBERNETES_NAMESPACE
}

appRegistryServiceDeploy() {
    logStep "Deploy app registry service"

    # Docker < 19.03 does not support cidr addresses in the no_proxy variable.
    # This is a workaround to add support for http proxies until we upgrade docker.
    local clusterIp=""
    if [ "$SERVICE_CIDR" = "10.96.0.0/12" ]; then
        # clusterIP is immutable
        clusterIp="$(kubectl get svc replicated-registry -ojsonpath --template '{.spec.clusterIP}' 2>/dev/null)" || :
        if [ -z "$clusterIp" ]; then
            clusterIp="10.100.100.101"
        fi
    fi

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS \
        replicated_registry_yaml=1 \
        replicated-registry-cluster-ip=$clusterIp > /tmp/replicated-registry.yml
    kubectl apply -f /tmp/replicated-registry.yml

    local replicatedRegistryIP=$(kubectl get service replicated-registry -o jsonpath='{.spec.clusterIP}')
    while [ -z "$replicatedRegistryIP" ]; do
        sleep 1
        replicatedRegistryIP=$(kubectl get service replicated-registry -o jsonpath='{.spec.clusterIP}')
    done
    APP_REGISTRY_ADVERTISE_HOST="$replicatedRegistryIP"

    logSuccess "App registry service deployed"
}

objectStoreDeploy() {
    logStep "Deploy rook object store"

    getYAMLOpts

    if isRook106Plus; then
        sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_106_object_store_yaml=1 > /tmp/rook-object-store.yml
    else
        # do not render limits and requests
        sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_103_object_store_yaml=1 > /tmp/rook-object-store.yml
    fi
    kubectl apply -f /tmp/rook-object-store.yml

    # wait for the object store gateway before creating the user
    spinnerPodRunning rook-ceph rook-ceph-rgw-replicated

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_object_store_user_yaml=1 > /tmp/rook-object-store-user.yml
    kubectl apply -f /tmp/rook-object-store-user.yml

    # Rook operator creates this secret from the user CRD just applied 
    while ! kubectl -n rook-ceph get secret rook-ceph-object-user-replicated-replicated 2>/dev/null; do
        sleep 2
    done

    logSuccess "Rook object store deployed"
}

objectStoreCreateDockerRegistryBucket() {
    logStep "Create object store registry bucket"

    # create the docker-registry bucket through the S3 API
    OBJECT_STORE_ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-replicated-replicated -o yaml | grep AccessKey | awk '{print $2}' | base64 --decode)
    OBJECT_STORE_SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-replicated-replicated -o yaml | grep SecretKey | awk '{print $2}' | base64 --decode)
    OBJECT_STORE_CLUSTER_IP=$(kubectl -n rook-ceph get service rook-ceph-rgw-replicated | tail -n1 | awk '{ print $3}')
    local acl="x-amz-acl:private"
    local d=$(date +"%a, %d %b %Y %T %z")
    local string="PUT\n\n\n${d}\n${acl}\n/docker-registry"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    curl --noproxy "*" -X PUT  \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/docker-registry" >/dev/null

    logSuccess "Object store registry bucket created"
}

registryDeploy() {
    logStep "Deploy registry"

    # Replicated >= 2.43.0 which includes RGW fixes
    semverCompare "$REPLICATED_VERSION" "2.43.0"
    if [ -z "$DISABLE_ROOK_OBJECT_STORE" ] && [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
        # cleanup pvc-backed registry if it exists; all images are re-pushed after this step
        if kubectl get statefulset docker-registry &>/dev/null; then
            kubectl delete statefulset docker-registry
        fi
        if kubectl get pvc registry-data-docker-registry-0 &>/dev/null; then
            kubectl delete pvc registry-data-docker-registry-0
        fi

        objectStoreCreateDockerRegistryBucket
    fi

    # Docker < 19.03 does not support cidr addresses in the no_proxy variable.
    # This is a workaround to add support for http proxies until we upgrade docker.
    local clusterIp=""
    if [ "$SERVICE_CIDR" = "10.96.0.0/12" ]; then
        # clusterIP is immutable
        clusterIp="$(kubectl get svc docker-registry -ojsonpath --template '{.spec.clusterIP}' 2>/dev/null)" || :
        if [ -z "$clusterIp" ]; then
            clusterIp="10.100.100.100"
        fi
    fi

    getYAMLOpts

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS \
        registry_yaml=1 \
        registry-cluster-ip=$clusterIp > /tmp/registry.yml
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
    "insecure-registries": ["$SERVICE_CIDR"]
}

Continue after updating and restarting docker on nodes: $workers
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
        if curl -s -o /dev/null -I --noproxy "*" -w "%{http_code}" "http://${REGISTRY_ADDRESS_OVERRIDE}/v2/" | grep -q 200; then
            return
        fi
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

replicatedDeploy() {
    logStep "deploy replicated components"

    # Multi-master airgap binds to the single master expected to have the canonical airgap bundle
    # and license. Replicated >= 2.36.0 copies the airgap files to all masters, but binding to a
    # single master prevents rescheduling before the copy has completed and also provides a fixed
    # destination to upload new release bundles when upgrading. In the event of loss of the bound
    # master, the REK operator will remove the bind to the single-master and leave it bound to any
    # master. Re-running this script will restore the single-master affinity.
    if [ "$HA_CLUSTER" = "1" ] && [ "$AIRGAP" = "1" ]; then
        BIND_DAEMON_HOSTNAME=$(hostname | tr '[:upper:]' '[:lower:]')
    fi

    logStep "generate manifests"
    getYAMLOpts
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS > /tmp/kubernetes.yml

    kubectl apply -f /tmp/kubernetes.yml -n $KUBERNETES_NAMESPACE
    kubectl -n $KUBERNETES_NAMESPACE get pods,svc
    rekOperatorDeploy
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
    if [ -n "$APP_REGISTRY_ADVERTISE_HOST" ]; then
        printf "\nIf uploading a custom certificate, include the registry IP as a Subject Alternative Name: ${GREEN}${APP_REGISTRY_ADVERTISE_HOST}${NC}"
        printf "\n"
        printf "\n"
    fi
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

    local joinArgs="kubernetes-master-address=${PRIVATE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION}"
    if [ "$UNSAFE_SKIP_CA_VERIFICATION" = "1" ]; then
        joinArgs=$joinArgs" unsafe-skip-ca-verification"
    fi

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
        printf "${GREEN}    cat ./kubernetes-node-join.sh | sudo bash -s airgap $joinArgs \n"
        printf "${NC}"
        printf "\n"
        printf "\n"
    else
        printf "\n"
        printf "To add nodes to this installation, run the following script on your other nodes"
        printf "\n"
        printf "${GREEN}    curl {{ replicated_install_url }}/{{ kubernetes_node_join_path }} | sudo bash -s $joinArgs \n"
        printf "${NC}"
        printf "\n"
        printf "\n"
    fi
}

outroReset() {
    printf "\n"
    printf "\t\t${GREEN}Uninstallation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    printf "\n"
}

outroLoadImages() {
    printf "\n"
    printf "\t\t${GREEN}Load images${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
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
        taint-control-plane|taint_control_plane)
            TAINT_CONTROL_PLANE=1
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
        release-patch-sequence|release_patch_sequence)
            RELEASE_PATCH_SEQUENCE="$_value"
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
        bypass-firewalld-warning|bypass_firewalld_warning)
            BYPASS_FIREWALLD_WARNING=1
            ;;
        hard-fail-on-firewalld|hard_fail_on_firewalld)
            HARD_FAIL_ON_FIREWALLD=1
            ;;
        disable-contour|disable_contour)
            DISABLE_CONTOUR=1
            ;;
        disable-rook-object-store|disable_rook_object_store)
            DISABLE_ROOK_OBJECT_STORE=1
            ;;
        kubernetes-version|kubernetes_version)
            KUBERNETES_VERSION="$_value"
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
        load-images)
            LOAD_IMAGES=1
            ;;
        force-replicated-downgrade|force_replicated_downgrade)
            FORCE_REPLICATED_DOWNGRADE=1
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

export KUBECONFIG=/etc/kubernetes/admin.conf

if [ "$FORCE_REPLICATED_DOWNGRADE" != "1" ] && isReplicatedDowngrade "$REPLICATED_VERSION"; then
    replicated2Version
    echo -e >&2 "${RED}Current Replicated version $INSTALLED_REPLICATED_VERSION is greater than the proposed version $REPLICATED_VERSION.${NC}"
    echo -e >&2 "${RED}To downgrade Replicated re-run the script with the force-replicated-downgrade flag.${NC}"
    exit 1
fi

discoverCurrentKubernetesVersion
parseKubernetesTargetVersion
setK8sPatchVersion

if [ "$RESET" == "1" ]; then
    k8s_reset "$FORCE_RESET"
    outroReset "$NO_CLEAR"
	exit 0
fi

if [ "$LOAD_IMAGES" == "1" ]; then
    k8s_load_images "$KUBERNETES_VERSION"
    outroLoadImages "$NO_CLEAR"
	exit 0
fi

checkDockerK8sVersion
checkFirewalld

if [ "$HA_CLUSTER" = "1" ]; then
    semverCompare "$REPLICATED_VERSION" "2.34.0"
    if [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
        bail "HA installs require Replicated >= 2.34.0"
    fi
fi

if [ "$KUBERNETES_VERSION" == "1.9.3" ]; then
    IPVS=0
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

kubernetesDiscoverPrivateIp
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
        if [ "$SERVICE_CIDR" = "10.96.0.0/12" ]; then
            # Docker < 19.03 does not support cidr addresses in the no_proxy variable.
            # This is a workaround to add support for http proxies until we upgrade docker.
            getNoProxyAddresses "$PRIVATE_ADDRESS" "$SERVICE_CIDR" "10.100.100.100" "10.100.100.101"
        else
            getNoProxyAddresses "$PRIVATE_ADDRESS" "$SERVICE_CIDR"
        fi
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

prompt_airgap_preload_images "$KUBERNETES_VERSION"

must_disable_selinux
installKubernetesComponents "$KUBERNETES_VERSION"

if [ "$AIRGAP" = "1" ]; then
    airgapLoadKubernetesCommonImages "$KUBERNETES_VERSION"
    airgapLoadKubernetesControlImages "$KUBERNETES_VERSION"
else
    docker pull replicated/docker-registry:2.6.2-20200512
fi

installCNIPlugins

if [ "$TAINT_CONTROL_PLANE" = "1" ]; then
    semverCompare "$REPLICATED_VERSION" "2.43.0"
    # support for tainting masters added in 2.43.0
    if [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
        logWarn "Will not taint contol plane, Replicated version 2.43.0+ required"
        TAINT_CONTROL_PLANE=0
    elif isRookInstalled && ! isRook106Plus; then
        # we do not upgrade rook ceph and tolerations do not seem to work well on rook v1.0.3
        # This happens before we install rook
        logWarn "Will not taint contol plane, Rook 1.0.6+ required"
        TAINT_CONTROL_PLANE=0
    else
        getKernelVersion
        # Rook 1.0.4+ does not seem to work on linux kernel 4 less than or equal 4.5
        # This happens before we install rook
        if [ "$KERNEL_MAJOR" -eq "4" ] && [ "$KERNEL_MINOR" -lt "5" ]; then
            logWarn "Will not taint contol plane, Kernel version 4.5+ required"
            TAINT_CONTROL_PLANE=0
        fi
    fi
fi

maybeGenerateBootstrapToken
if ! upgradeInProgress; then
    # If re-initing the node will be temporarily tainted which will trigger orchestration.
    # If the cluster has exactly two nodes the orchestration will lead to loss of quorum.
    disableRookCephOperator
    initKube
    enableRookCephOperator
fi

kubectl cluster-info
logSuccess "Cluster Initialized"

getK8sYmlGenerator

weavenetDeploy

spinnerMasterNodeReady
labelMasterNodeDeprecated

if [ "$DID_INIT_KUBERNETES" = "0" ] || [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]; then
    maybeUpgradeKubernetes "$KUBERNETES_VERSION"
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
        CEPH_DASHBOARD_URL=http://rook-ceph-mgr-dashboard.rook-ceph.svc.cluster.local:7000

        # Ceph v13+ requires login. Rook 1.0+ creates a secret in the rook-ceph namespace.
        cephDashboardPassword=$(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode)
        if [ -n "$cephDashboardPassword" ]; then
            CEPH_DASHBOARD_USER=admin
            CEPH_DASHBOARD_PASSWORD="$cephDashboardPassword"
        fi

        semverCompare "$REPLICATED_VERSION" "2.41.0"
        if [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
            logWarn "Rook object store disabled, Replicated version must be greater than or equal to 2.41.0"
            DISABLE_ROOK_OBJECT_STORE=1
        elif ! isRook103Plus; then
            logWarn "Rook object store disabled, Rook version must be greater than or equal to 1.0.3"
            DISABLE_ROOK_OBJECT_STORE=1
        fi

        if isRook1; then
            MAINTAIN_ROOK_STORAGE_NODES=1
        fi
        if [ -z "$DISABLE_ROOK_OBJECT_STORE" ]; then
            objectStoreDeploy
        fi
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

installAKAService

if [ "$KUBERNETES_ONLY" -eq "1" ]; then
    spinnerKubeSystemReady "$KUBERNETES_VERSION"
    clusterAdminDeploy
    rekOperatorDeploy
    outroKubeadm "$NO_CLEAR"
    exit 0
fi

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
    semverCompare "$REPLICATED_VERSION" "2.34.0"
    if [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
        registryDeploy
        airgapPushReplicatedImagesToRegistry "$REGISTRY_ADDRESS_OVERRIDE"
    fi

    # deploy the app registry service before the Replicated deployment so the cluster IP can be
    # passed in as the registry advertise host
    appRegistryServiceDeploy
fi

replicatedDeploy

installCliFile \
    "kubectl exec -c replicated" \
    '$(kubectl get pods -o=jsonpath="{.items[0].metadata.name}" -l tier=master) --'
logSuccess "Installed replicated cli executable"

installAliasFile
logSuccess "Installed replicated command alias"

spinnerReplicatedReady "$REPLICATED_VERSION"

includeBranding

outro "$NO_CLEAR"

exit 0
