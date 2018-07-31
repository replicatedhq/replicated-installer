
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
# Globals:
#   None
# Arguments:
#   upgradeVersion - e.g. 1.10.5
# Returns:
#   None
#######################################
maybeUpgradeKubernetes() {
    export KUBECONFIG=/etc/kubernetes/admin.conf

    upgradeVersion="$1"
    semverParse "$upgradeVersion"
    upgradeMajor="$major"
    upgradeMinor="$minor"

    if [ "$upgradeMajor" -lt "1" ] || [ "$upgradeMinor" -lt "10" ]; then
        return
    fi

    masterVersion="$(getK8sMasterVersion)"
    semverParse "$masterVersion"

    if [ "$major" -eq "1" ] && [ "$minor" -eq "9" ]; then
        logStep "Kubernetes version v$masterVersion detected, upgrading to version v1.10.5"
        upgradeK8sMaster "1.10.5" "$UBUNTU_1604_K8S_10" "$CENTOS_74_K8S_10"
        logSuccess "Kubernetes upgraded to version v1.10.5"
    fi

    upgradeK8sWorkers "1.10.5"

    if [ "$upgradeMinor" -lt "11" ]; then
        return
    fi

    masterVersion="$(getK8sMasterVersion)"
    semverParse "$masterVersion"

    if [ "$major" -eq "1" ] && [ "$minor" -eq "10" ]; then
        logStep "Kubernetes version v$masterVersion detected, upgrading to version v1.11.0"
        upgradeK8sMaster "1.11.0" "$UBUNTU_1604_K8S_11" "$CENTOS_74_K8S_11"
        logSuccess "Kubernetes upgraded to version v1.11.0"
    fi

    upgradeK8sWorkers "1.11.0"
}

#######################################
# If kubelet is installed and version is less than specified, upgrade.
# Globals:
#   None
# Arguments:
#   upgradeVersion - e.g. 1.10.5
# Returns:
#   None
#######################################
maybeUpgradeKubernetesNode() {
    upgradeVersion="$1"
    semverParse "$upgradeVersion"
    upgradeMajor="$major"
    upgradeMinor="$minor"

    nodeVersion="$(getK8sNodeVersion)"
    semverParse "$nodeVersion"

    if [ "$major" -eq "$upgradeMajor" ] && [ "$minor" -lt "$upgradeMinor" ]; then
        logStep "Kubernetes version v$nodeVersion detected, upgrading node to version v$upgradeVersion"
        upgradeK8sNode "$upgradeVersion"

        # not supported in kubeadm < 1.11
        kubeadm upgrade node config --kubelet-version $(kubelet --version | cut -d ' ' -f 2) 2>/dev/null || :

        systemctl restart kubelet

        logSuccess "Kubernetes node upgraded to version v$upgradeVersion"
    fi
}

#######################################
# Upgrade Kubernetes on remote workers to version
# Globals:
#   AIRGAP
# Arguments:
#   k8sVersion - e.g. 1.10.5
# Returns:
#   None
#######################################
upgradeK8sWorkers() {
    k8sVersion="$1"

    workers=$(kubectl get nodes | sed '1d' | grep -v master | grep -v $k8sVersion | awk '{ print $1 }')

    for node in $workers; do
        kubectl drain "$node" --ignore-daemonsets --delete-local-data --force
        printf "\n\n\tRun the upgrade script on remote node before proceeding: ${GREEN}$node${NC}\n\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "\t${GREEN}cat kubernetes-node-upgrade.sh | sudo bash -s kubernetes-version=$k8sVersion${NC}"
        else
            printf "\t${GREEN}curl {{ replicated_install_url }}/kubernetes-node-upgrade | sudo bash -s kubernetes-version=$k8sVersion${NC}"
        fi
        printf "\n\n\tPress enter when script has completed\n\n"
        prompt
        kubectl uncordon $node
    done

    spinnerNodesReady
}

#######################################
# Upgrade Kubernetes on master node
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. 1.10.5
# Returns:
#   None
#######################################
upgradeK8sMaster() {
    k8sVersion=$1

    prepareK8sPackageArchives $k8sVersion

    # must use kubeadm binary to begin upgrade before upgrading kubeadm package
    # https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
    cp archives/kubeadm /usr/bin/kubeadm
    chmod a+rx /usr/bin/kubeadm

    kubeadm upgrade apply "v$k8sVersion" --yes --config=/opt/replicated/kubeadm.conf

    # upgrade master
    master=$(kubectl get nodes | grep master | awk '{ print $1 }')
    # ignore error about unmanaged pods
    kubectl drain $master --ignore-daemonsets --delete-local-data 2>/dev/null || :

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i archives/*.deb
            ;;
        centos7.4|rhel7.4)
            rpm --upgrade --force archives/*.rpm
            ;;
        *)
            bail "Unsuported OS: $LSB_DIST$DIST_VERSION"
            ;;
    esac

    rm -rf archives

    systemctl daemon-reload
    systemctl restart kubelet

    kubectl uncordon $master

    sed -i "s/kubernetesVersion:.*/kubernetesVersion: v$k8sVersion/" /opt/replicated/kubeadm.conf
    
    spinnerNodeVersion $(kubectl get nodes | grep master | awk '{ print $1 }') "$k8sVersion"
    spinnerNodesReady
}

#######################################
# Upgrade Kubernetes on worker node
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. 1.10.5
# Returns:
#   None
#######################################
upgradeK8sNode() {
    k8sVersion=$1
    pkgTag=$(k8sPackageTag $k8sVersion)

    echo "Upgrading node to Kubernetes v$k8sVersion"

    if [ "$AIRGAP" = "1" ]; then
        docker load < packages-kubernetes-${pkgTag}
    fi
    docker run \
      -v $PWD:/out \
      "quay.io/replicated/k8s-packages:${pkgTag}"


    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i archives/*.deb
            ;;
        centos7.4|rhel7.*)
            rpm --upgrade --force archives/*.rpm
            ;;
        *)
            bail "Unsuported OS: $LSB_DIST$DIST_VERSION"
            ;;
    esac

    rm -rf archives

    systemctl daemon-reload
    systemctl restart kubelet
}

#######################################
# Check if kubernetes is installed
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   1 if kubernetes is not installed
#######################################
isKubernetesInstalled() {
    _out=0
    kubectl get nodes 2>/dev/null || _out="$?"
    if [ "$_out" -ne "0" ]; then
        return 1
    fi
    return 0
}

#######################################
# Get k8s master version
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   version - e.g. 1.9.3
#######################################
getK8sMasterVersion() {
    echo "$(kubectl get nodes | grep master | awk '{ print $5 }' | sed 's/v//')"
}

#######################################
# Check if kubelet is installed
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   1 if kubelet is not installed
#######################################
isKubeletInstalled() {
    _out=0
    kubelet --version 2>/dev/null || _out="$?"
    if [ "$_out" -ne "0" ]; then
        return 1
    fi
    return 0
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
