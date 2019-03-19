
#######################################
#
# kubernetes.sh
#
# require common.sh
# require prompt.sh
# require log.sh
# require system.sh
# require kubernetes.sh
#
#######################################

#######################################
# If kubernetes is installed and version is less than specified, upgrade.
# Kubeadm requires installing every minor version between current and target.
# kubeadm < 1.11 uses v1alpha1 config file format
# kubeadm 1.11 writes v1alpha2 configs and can also read v1alpha1
# kubeadm 1.12 writes v1alpha3 configs and can also read v1alpha2
# kubeadm 1.13 writes v1beta1 configs and can also read v1alpha3
# Globals:
#   KUBERNETES_ONLY
# Arguments:
#   k8sTargetVersion - e.g. 1.10.6
# Returns:
#   DID_UPGRADE_KUBERNETES
#######################################
DID_UPGRADE_KUBERNETES=0
maybeUpgradeKubernetes() {
    local k8sTargetVersion="$1"
    semverParse "$k8sTargetVersion"
    local k8sTargetMajor="$major"
    local k8sTargetMinor="$minor"
    local k8sTargetPatch="$patch"

    if allNodesUpgraded "$k8sTargetVersion"; then
        maybeUpgradeKubernetesLoadBalancer "$k8sTargetVersion"
        return
    fi
    # attempt to stop Replicated to reduce Docker load during upgrade
    if [ "$KUBERNETES_ONLY" != "1" ]; then
        kubectl delete all --all --grace-period=30 --timeout=60s || true
    fi


    local kubeletVersion="$(getKubeletVersion)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"

    if [ "$kubeletMajor" -ne "$k8sTargetMajor" ]; then
        printf "Cannot upgrade from %s to %s\n" "$kubeletVersion" "$k8sTargetVersion"
        return 1
    fi

    if [ "$k8sTargetMinor" -eq "9" ]; then
        return 0
    fi

    if [ "$kubeletMinor" -eq "9" ] && [ "$k8sTargetMinor" -gt "9" ]; then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.10.6"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.10.6
            airgapLoadKubernetesControlImages 1.10.6
            airgapLoadReplicatedAddonImagesWorker
        fi
        upgradeK8sMaster "1.10.6"
        logSuccess "Kubernetes upgraded to version v1.10.6"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sWorkers "1.10.6" "0"

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    if [ "$kubeletMinor" -eq "10" ] || ([ "$kubeletMinor" -eq "11" ] && [ "$k8sTargetMinor" -eq "11" ] && [ "$kubeletPatch" -lt "$k8sTargetPatch" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.11.5"
        upgradeK8sMaster "1.11.5"
        logSuccess "Kubernetes upgraded to version v1.11.5"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sWorkers "1.11.5" "$K8S_UPGRADE_PATCH_VERSION"

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    if [ "$k8sTargetMinor" -eq "11" ]; then
        return 0
    fi

    if [ "$kubeletMinor" -eq "11" ] &&  [ "$k8sTargetMinor" -gt "11" ]; then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.12.3"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.12.3
            airgapLoadKubernetesControlImages 1.12.3
            airgapLoadReplicatedAddonImagesWorker
        fi
        # must migrate alpha1 to alpha2 with kubeadm 1.11 while it's still available
        kubeadm config migrate --old-config /opt/replicated/kubeadm.conf --new-config /opt/replicated/kubeadm.conf
        upgradeK8sMaster "1.12.3"
        logSuccess "Kubernetes upgraded to version v1.12.3"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sWorkers "1.12.3" "0"

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    # no patch versions of 1.13 yet.
    if [ "$kubeletMinor" -eq "12" ]; then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.13.0"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.13.0
            airgapLoadKubernetesControlImages 1.13.0
            airgapLoadReplicatedAddonImagesWorker
        fi
        : > /opt/replicated/kubeadm.conf
        makeKubeadmConfig
        upgradeK8sMaster "1.13.0"
        logSuccess "Kubernetes upgraded to version v1.13.0"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sWorkers "1.13.0" "$K8S_UPGRADE_PATCH_VERSION"
}

#######################################
# Returns 0 if load balancer address is changing
# Globals:
#   None
# Arguments:
#   Load balancer address
# Returns:
#   1 if load balancer address is changing, 0 if not
#######################################
isLoadBalancerAddressChanging() {
    local loadBalancerAddress="$1"
    if [ -z "$loadBalancerAddress" ] || ! kubeadm config view >/dev/null 2>&1; then
        return 1
    fi
    local previous_address="$(kubeadm config view | grep 'controlPlaneEndpoint:' | sed 's/controlPlaneEndpoint: \|"//g')"
    if [ -z "$previous_address" ]; then
        return 1
    fi
    splitHostPort "$previous_address"
    local previous_address="$HOST"
    local previous_port="$PORT"
    if [ -z "$previous_port" ]; then
        previous_port=6443
    fi
    splitHostPort "$loadBalancerAddress"
    local next_address="$HOST"
    local next_port="$PORT"
    if [ -z "$next_port" ]; then
        next_port=6443
    fi
    if [ "$previous_address" = "$next_address" ] && [ "$previous_port" = "$next_port" ]; then
        return 0
    else
        return 1
    fi
}

#######################################
# TODO
# Globals:
#   LOAD_BALANCER_ADDRESS
#   LOAD_BALANCER_PORT
# Arguments:
#   k8sTargetVersion - e.g. 1.10.6
# Returns:
#   DID_UPGRADE_KUBERNETES
#######################################
DID_UPGRADE_KUBERNETES=0
maybeUpgradeKubernetesLoadBalancer() {
    if [ -z "$LOAD_BALANCER_ADDRESS" ] || [ -z "$LOAD_BALANCER_PORT" ]; then
        return
    fi
    if ! isLoadBalancerAddressChanging "$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"; then
        updateKubernetesAPIServerCerts "$LOAD_BALANCER_ADDRESS" "$LOAD_BALANCER_PORT"
        updateKubeconfigs "https://$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
        return
    fi

    local k8sTargetVersion="$1"
    semverParse "$k8sTargetVersion"
    local k8sTargetMajor="$major"
    local k8sTargetMinor="$minor"
    local k8sTargetPatch="$patch"

    if [ "$k8sTargetMinor" -lt 13 ]; then
        return
    fi

    echo ""
    logStep "Kubernetes control plane endpoint updated, upgrading control plane..."
    echo ""

    # this will use the new load balancer address to the kubeadm.conf
    : > /opt/replicated/kubeadm.conf
    makeKubeadmConfig

    updateKubernetesAPIServerCerts "$LOAD_BALANCER_ADDRESS" "$LOAD_BALANCER_PORT"
    updateKubeconfigs "https://$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"

    logStep "Upgrading kubernetes control plane"
    (
        set -x
        kubeadm upgrade apply -yf --ignore-preflight-errors=all \
            --config=/opt/replicated/kubeadm.conf
    )
    logSuccess "Kubernetes control plane upgraded"

    logStep "Restarting kube-proxy"
    kubectl -n kube-system get pods | grep kube-proxy | awk '{print $1}' | xargs kubectl -n kube-system delete pod
    logSuccess "Kube-proxy restarted"

    spinnerNodesReady

    if [ "$(kubectl get nodes | awk '{if(NR>1)print}' | grep master | wc -l)" -gt "1" ]; then
        echo ""
        printf "Run the upgrade script on remote master nodes before proceeding:\n\n${GREEN}"
        replicatedctl cluster node-join-script --master | sed "s/api-service-address=[^ ]*/api-service-address=$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/"
        printf "${NC}\n\n"
        kubectl get nodes | awk '{if(NR==1)print}'
        kubectl get nodes | awk '{if(NR>1)print}' | grep master
        echo ""
        echo ""

        while true; do
            echo ""
            READ_TIMEOUT=""
            printf "${YELLOW}Have all master nodes been updated?${NC} "
            if confirmN; then
                break
            fi
        done

        spinnerNodesReady
    fi

    if [ "$(kubectl get nodes | awk '{if(NR>1)print}' | grep -v master | wc -l)" -gt "0" ]; then
        echo ""
        printf "Run the upgrade script on remote worker nodes before proceeding:\n\n${GREEN}"
        replicatedctl cluster node-join-script | sed "s/api-service-address=[^ ]*/api-service-address=$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/"
        printf "${NC}\n\n"
        kubectl get nodes | awk '{if(NR==1)print}'
        kubectl get nodes | awk '{if(NR>1)print}' | grep -v master
        echo ""
        echo ""
        while true; do
            echo ""
            READ_TIMEOUT=""
            printf "${YELLOW}Have all worker nodes been updated?${NC} "
            if confirmN; then
                break
            fi
        done

        spinnerNodesReady
    fi

    echo ""
    logSuccess "Kubernetes control plane endpoint updated"
    echo ""

    DID_UPGRADE_KUBERNETES=1
}

#######################################
# Regenerate certs if missing control plane endpoint in SANs
# Globals:
#   None
# Arguments:
#   ip or domain, port
# Returns:
#   K8S_API_SERVER_CERTS_RENEWED
#######################################
updateKubernetesAPIServerCerts()
{
    if ! certHasSAN /etc/kubernetes/pki/apiserver.crt "$1"; then
        logStep "Regenerate api server certs"
        rm -f /etc/kubernetes/pki/apiserver.*
        kubeadm init phase certs apiserver --config=/opt/replicated/kubeadm.conf

        logSuccess "API server certs regenerated"
        logStep "Restart kubernetes api server"
        # admin.conf may not have been updated yet so kubectl may not work
        docker ps | grep k8s_kube-apiserver | awk '{print $1}' | xargs docker rm -f
        while ! curl -skf "https://$1:$2/healthz" ; do
            sleep 1
        done
        logSuccess "Kubernetes api server restarted"
    fi
}

#######################################
# Regenerate kubeconfigs if not pointing at control plane endpoint
# Globals:
#   None
# Arguments:
#   control plane endpoint
# Returns:
#   None
#######################################
updateKubeconfigs()
{
    local regenerate=0

    if ! confHasEndpoint /etc/kubernetes/admin.conf "$1"; then
        rm -f /etc/kubernetes/admin.conf
        regenerate=1
    fi

    if ! confHasEndpoint /etc/kubernetes/kubelet.conf "$1"; then
        rm -f /etc/kubernetes/kubelet.conf
        regenerate=1
    fi

    if ! confHasEndpoint /etc/kubernetes/scheduler.conf "$1"; then
        rm -f /etc/kubernetes/scheduler.conf
        regenerate=1
    fi

    if ! confHasEndpoint /etc/kubernetes/controller-manager.conf "$1"; then
        rm -f /etc/kubernetes/controller-manager.conf
        regenerate=1
    fi

    if [ "$regenerate" = "1" ]; then
        logStep "Regenerating control plane kubeconfig"
        kubeadm init phase kubeconfig all --config=/opt/replicated/kubeadm.conf
        chmod 444 /etc/kubernetes/*.conf
        logSuccess "Kubernetes control plane kubeconfigs regenerated"
    fi
}

#######################################
# If kubelet is installed and version is less than specified, upgrade.
# Globals:
#   None
# Arguments:
#   k8sTargetVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
maybeUpgradeKubernetesNode() {
    local k8sTargetVersion="$1"
    semverParse "$k8sTargetVersion"
    local k8sTargetMajor="$major"
    local k8sTargetMinor="$minor"
    local k8sTargetPatch="$patch"

    local kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"

    if [ "$kubeletMajor" -ne "$k8sTargetMajor" ]; then
        printf "Cannot upgrade from %s to %s\n" "$kubeletVersion" "$k8sTargetVersion"
        return 1
    fi
    if [ "$kubeletMinor" -lt "$k8sTargetMinor" ] || ([ "$kubeletMinor" -eq "$k8sTargetMinor" ] && [ "$kubeletPatch" -lt "$k8sTargetPatch" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading node to version v$k8sTargetVersion"

        systemctl stop kubelet
        upgradeK8sNode "$k8sTargetVersion"

        if [ "$k8sTargetMinor" -gt 10 ]; then
            # kubeadm alpha phase kubelet write-env-file failed in airgap
            local cgroupDriver=$(docker info 2> /dev/null | grep "Cgroup Driver" | cut -d' ' -f 3)
            local envFile="KUBELET_KUBEADM_ARGS=--cgroup-driver=%s --cni-bin-dir=/opt/cni/bin --cni-conf-dir=/etc/cni/net.d --network-plugin=cni\n"
            printf "$envFile" "$cgroupDriver" > /var/lib/kubelet/kubeadm-flags.env

            local n=0
            local ver=$(kubelet --version | cut -d ' ' -f 2)
            while ! kubeadm upgrade node config --kubelet-version "$ver" ; do
                n="$(( $n + 1 ))"
                if [ "$n" -ge "10" ]; then
                    exit 1
                fi
                sleep 2
            done
        fi

        systemctl start kubelet

        logSuccess "Kubernetes node upgraded to version v$k8sTargetVersion"
    elif [ "$k8sTargetMinor" -ge 13 ]; then
        # Sync the config in case it changed.
        logStep "Sync Kubernetes node config"
        if isMasterNode; then
            (set -x; kubeadm upgrade node experimental-control-plane)
            : > /opt/replicated/kubeadm.conf
            makeKubeadmConfig
            updateKubernetesAPIServerCerts "$LOAD_BALANCER_ADDRESS" "$LOAD_BALANCER_PORT"
            updateKubeconfigs "https://$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
        else
            (set -x; kubeadm upgrade node config --kubelet-version v1.13.0)
            if [ -n "$LOAD_BALANCER_ADDRESS" ] && [ -n "$LOAD_BALANCER_PORT" ]; then
                sudo sed -i "s/server: https.*/server: https:\/\/$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/" /etc/kubernetes/kubelet.conf
            fi
        fi
        logSuccess "Kubernetes node config upgraded"
    fi
}

#######################################
# Run `kubectl get nodes` until it succeeds or up to 1 minute
# Globals:
#   K8S_UPGRADE_PATCH_VERSION
# Arguments:
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
listNodes() {
    local nodes=
    n=0
    while ! nodes="$(kubectl get nodes 2>/dev/null)"; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "30" ]; then
            # this should exit script on non-zero exit code and print error message
            local nodes="$(kubectl get nodes)"
        fi
        sleep 2
    done
    echo "$nodes" | sed '1d'
}

#######################################
# Upgrade Kubernetes on remote workers to version. Never downgrades a worker.
# Globals:
#   K8S_UPGRADE_PATCH_VERSION
# Arguments:
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
allNodesUpgraded() {
    local k8sTargetVersion="$1"
    semverParse "$k8sTargetVersion"
    local k8sTargetMajor="$major"
    local k8sTargetMinor="$minor"
    local k8sTargetPatch="$patch"

    while read -r node; do
        local nodeVersion="$(echo "$node" | awk '{ print $5 }' | sed 's/v//' )"
        semverParse "$nodeVersion"
        local nodeMajor="$major"
        local nodeMinor="$minor"
        local nodePatch="$patch"

        if [ "$nodeMajor" -eq "$k8sTargetMajor" ] &&  [ "$nodeMinor" -lt "$k8sTargetMinor" ]; then
            return 1
        fi
        if [ "$nodeMajor" -eq "$k8sTargetMajor" ] && [ "$nodeMinor" -eq "$k8sTargetMinor" ] && [ "$nodePatch" -lt "$k8sTargetPatch" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]; then
            return 1
        fi
    done <<< "$(listNodes)"

    return 0
}

#######################################
# Upgrade Kubernetes on remote workers to version. Never downgrades a worker.
# Globals:
#   AIRGAP
# Arguments:
#   k8sVersion - e.g. 1.10.6
#   shouldUpgradePatch
# Returns:
#   None
#######################################
upgradeK8sWorkers() {
    k8sVersion="$1"
    shouldUpgradePatch="$2"

    semverParse "$k8sVersion"
    local upgradeMajor="$major"
    local upgradeMinor="$minor"
    local upgradePatch="$patch"

    local nodes=
    n=0
    while ! nodes="$(kubectl get nodes 2>/dev/null)"; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "30" ]; then
            # this should exit script on non-zero exit code and print error message
            nodes="$(kubectl get nodes)"
        fi
        sleep 2
    done
    # not an error if there are no workers
    # TODO better master identification
    local workers="$(echo "$nodes" | sed '1d' | grep -v master || :)"

    while read -r node; do
        if [ -z "$node" ]; then
            continue
        fi
        nodeVersion="$(echo "$node" | awk '{ print $5 }' | sed 's/v//' )"
        semverParse "$nodeVersion"
        nodeMajor="$major"
        nodeMinor="$minor"
        nodePatch="$patch"
        if [ "$nodeMajor" -ne "$upgradeMajor" ]; then
            printf "Cannot upgrade from %s to %s\n" "$nodeVersion" "$k8sVersion"
            return 1
        fi
        if [ "$nodeMinor" -gt "$upgradeMinor" ]; then
            continue
        fi
        if [ "$nodeMinor" -eq "$upgradeMinor" ] && [ "$nodePatch" -eq "$upgradePatch" ]; then
            continue
        fi
        if [ "$nodeMinor" -eq "$upgradeMinor" ] && [ "$shouldUpgradePatch" != "1" ]; then
            continue
        fi
        nodeName=$(echo "$node" | awk '{ print $1 }')
        kubectl drain "$nodeName" \
            --delete-local-data \
            --ignore-daemonsets \
            --force \
            --grace-period=30 \
            --timeout=300s \
            --pod-selector 'app notin (rook-ceph-mon,rook-ceph-osd,rook-ceph-osd-prepare,rook-ceph-operator,rook-ceph-agent)' || :


        printf "\n\n\tRun the upgrade script on remote node before proceeding: ${GREEN}$nodeName${NC}\n\n"
        local upgradePatchFlag=""
        if [ "$shouldUpgradePatch" = "1" ]; then
            upgradePatchFlag=" kubernetes-upgrade-patch-version"
        fi
        if [ "$AIRGAP" = "1" ]; then
            printf "\t${GREEN}cat kubernetes-node-upgrade.sh | sudo bash -s airgap kubernetes-version=${k8sVersion}${upgradePatchFlag}${NC}"
        else
            printf "\t${GREEN}curl {{ replicated_install_url }}/kubernetes-node-upgrade | sudo bash -s kubernetes-version=${k8sVersion}${upgradePatchFlag}${NC}"
        fi
        while true; do
            echo ""
            READ_TIMEOUT=""
            printf "Has script completed? "
            if confirmN; then
                break
            fi
        done
        kubectl uncordon "$nodeName"
    done <<< "$workers"

    spinnerNodesReady
}

#######################################
# Upgrade Kubernetes on master node
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
upgradeK8sMaster() {
    k8sVersion=$1
    local node=$(k8sMasterNodeName)

    prepareK8sPackageArchives "$k8sVersion"

    # must use kubeadm binary to begin upgrade before upgrading kubeadm package
    # https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
    cp archives/kubeadm /usr/bin/kubeadm
    chmod a+rx /usr/bin/kubeadm

    kubeadm upgrade apply "v$k8sVersion" --yes --config=/opt/replicated/kubeadm.conf --force
    waitForNodes

    kubectl drain "$node" \
        --delete-local-data \
        --ignore-daemonsets \
        --force \
        --grace-period=30 \
        --timeout=300s \
        --pod-selector 'app notin (rook-ceph-mon,rook-ceph-osd,rook-ceph-osd-prepare,rook-ceph-operator,rook-ceph-agent)' || :
 
    systemctl stop kubelet

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04|ubuntu18.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i --force-depends-version archives/*.deb
            ;;
        centos7.4|centos7.5|centos7.6|rhel7.4|rhel7.5|rhel7.6)
            rpm --upgrade --force --nodeps archives/*.rpm
            ;;
        *)
            bail "Unsuported OS: $LSB_DIST$DIST_VERSION"
            ;;
    esac

    rm -rf archives

    systemctl daemon-reload
    systemctl start kubelet
    kubectl uncordon "$node"

    sed -i "s/kubernetesVersion:.*/kubernetesVersion: v$k8sVersion/" /opt/replicated/kubeadm.conf

    waitForNodes
    spinnerNodeVersion "$(k8sMasterNodeName)" "$k8sVersion"
    spinnerNodesReady
}

#######################################
# Upgrade Kubernetes on worker node
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
upgradeK8sNode() {
    k8sVersion=$1

    prepareK8sPackageArchives "$k8sVersion"

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04|ubuntu18.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i --force-depends-version archives/*.deb
            ;;
        centos7.4|centos7.5|centos7.6|rhel7.4|rhel7.5|rhel7.6)
            rpm --upgrade --force --nodeps archives/*.rpm
            ;;
        *)
            bail "Unsuported OS: $LSB_DIST$DIST_VERSION"
            ;;
    esac

    rm -rf archives

    systemctl daemon-reload
}

#######################################
# Get k8s server version
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   version - e.g. 1.9.3
#######################################
getK8sServerVersion() {
    logStep "check k8s server version"
    # poll until we can get the current server version
    _current="$(kubectl version | grep 'Server Version' | tr " " "\n" | grep GitVersion | cut -d'"' -f2 | sed 's/v//')"
    until [ -n "$_current" ]; do
      _current="$(kubectl version | grep 'Server Version' | tr " " "\n" | grep GitVersion | cut -d'"' -f2 | sed 's/v//')"
    done
    logSuccess "got k8s server version: $_current"
    printf "$_current"
}

#######################################
# Get k8s node version
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   version - e.g. 1.9.3
#######################################
getK8sNodeVersion() {
    echo "$(kubelet --version | cut -d ' ' -f 2 | sed 's/v//')"
}
