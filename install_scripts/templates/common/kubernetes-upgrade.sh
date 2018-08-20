
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
#   upgradeVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
maybeUpgradeKubernetes() {
    export KUBECONFIG=/etc/kubernetes/admin.conf

    local upgradeVersion="$1"
    semverParse "$upgradeVersion"
    local upgradeMajor="$major"
    local upgradeMinor="$minor"

    if [ "$upgradeMajor" -lt "1" ] || [ "$upgradeMinor" -lt "10" ]; then
        return
    fi

    if [ "$AIRGAP" = "1" ]; then
        airgapLoadKubernetesCommonImages 1.10.6
        airgapLoadKubernetesControlImages 1.10.6
    fi

    local masterVersion="$(getK8sMasterVersion)"
    semverParse "$masterVersion"

    if [ "$major" -eq "1" ] && [ "$minor" -eq "9" ]; then
        logStep "Kubernetes version v$masterVersion detected, upgrading to version v1.10.6"
        upgradeK8sMaster "1.10.6" "$UBUNTU_1604_K8S_10" "$CENTOS_74_K8S_10"
        logSuccess "Kubernetes upgraded to version v1.10.6"
    fi

    upgradeK8sWorkers "1.10.6"

    if [ "$upgradeMinor" -lt "11" ]; then
        return
    fi

    masterVersion="$(getK8sMasterVersion)"
    semverParse "$masterVersion"

    if [ "$major" -eq "1" ] && [ "$minor" -eq "10" ]; then
        logStep "Kubernetes version v$masterVersion detected, upgrading to version v1.11.1"
        upgradeK8sMaster "1.11.1" "$UBUNTU_1604_K8S_11" "$CENTOS_74_K8S_11"
        logSuccess "Kubernetes upgraded to version v1.11.1"
    fi

    upgradeK8sWorkers "1.11.1"
}

#######################################
# If kubelet is installed and version is less than specified, upgrade.
# Globals:
#   None
# Arguments:
#   upgradeVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
maybeUpgradeKubernetesNode() {
    upgradeVersion="$1"
    semverParse "$upgradeVersion"
    local upgradeMajor="$major"
    local upgradeMinor="$minor"

    local nodeVersion="$(getK8sNodeVersion)"
    semverParse "$nodeVersion"

    if [ "$major" -eq "$upgradeMajor" ] && [ "$minor" -lt "$upgradeMinor" ]; then
        logStep "Kubernetes version v$nodeVersion detected, upgrading node to version v$upgradeVersion"

        # this file was missing once after an upgrade on CentOS 7.4
        local kubeadmFlags="$(cat /var/lib/kubelet/kubeadm-flags.env)"

        upgradeK8sNode "$upgradeVersion"

        # not supported in kubeadm < 1.11
        kubeadm upgrade node config --kubelet-version $(kubelet --version | cut -d ' ' -f 2) 2>/dev/null || :

        if [ ! -e "/var/lib/kubelet/kubeadm-flags.env" ] && [ -n "$kubeadmFlags" ]; then
            echo "$kubeadmFlags" >> /var/lib/kubelet/kubeadm-flags.env
        fi

        systemctl restart kubelet

        logSuccess "Kubernetes node upgraded to version v$upgradeVersion"
    fi
}

#######################################
# Upgrade Kubernetes on remote workers to version
# Globals:
#   AIRGAP
# Arguments:
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
upgradeK8sWorkers() {
    k8sVersion="$1"
    semverParse "$k8sVersion"
    local upgradeMajor="$major"
    local upgradeMinor="$minor"

    local nodes=
    n=0
    while ! nodes="$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes 2>/dev/null)"; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "30" ]; then
            # this should exit script on non-zero exit code and print error message
            nodes="$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes)"
        fi
        sleep 2
    done
    # not an error if there are no workers
    local workers="$(echo "$nodes" | sed '1d' | grep -v master || :)"

    while read -r node; do
        if [ -z "$node" ]; then
            continue
        fi
        semverParse $(echo "$node" | awk '{ print $5 }' | sed 's/v//' )
        nodeMajor="$major"
        nodeMinor="$minor"
        if [ "$nodeMajor" -gt "$upgradeMajor" ]; then
            continue
        fi
        if [ "$nodeMajor" -eq "$upgradeMajor" ] && [ "$nodeMinor" -ge "$upgradeMinor" ]; then
            continue
        fi
        nodeName=$(echo "$node" | awk '{ print $1 }')

        # continue after timeout errors
        kubectl drain "$nodeName" --ignore-daemonsets --delete-local-data --force --grace-period=30 --timeout=300s || :
        printf "\n\n\tRun the upgrade script on remote node before proceeding: ${GREEN}$nodeName${NC}\n\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "\t${GREEN}cat kubernetes-node-upgrade.sh | sudo bash -s airgap kubernetes-version=$k8sVersion${NC}"
        else
            printf "\t${GREEN}curl {{ replicated_install_url }}/kubernetes-node-upgrade | sudo bash -s kubernetes-version=$k8sVersion${NC}"
        fi
        while true; do
            echo
            READ_TIMEOUT=""
            printf "Has script completed? "
            if confirmN; then
                break
            fi
        done
        kubectl uncordon $nodeName
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

    prepareK8sPackageArchives "$k8sVersion"

    # must use kubeadm binary to begin upgrade before upgrading kubeadm package
    # https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
    cp archives/kubeadm /usr/bin/kubeadm
    chmod a+rx /usr/bin/kubeadm

    kubeadm upgrade apply "v$k8sVersion" --yes --config=/opt/replicated/kubeadm.conf

    # upgrade master
    waitForNodes
    master=$(kubectl get nodes | grep master | awk '{ print $1 }')
    # ignore error about unmanaged pods
    kubectl drain $master --ignore-daemonsets --delete-local-data --grace-period=30 --timeout=300s 2>/dev/null || :

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i archives/*.deb
            ;;
        centos7.4|centos7.5|rhel7.4|rhel7.5)
            rpm --upgrade --force --nodeps archives/*.rpm
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
        ubuntu16.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i archives/*.deb
            ;;
        centos7.4|centos7.5|rhel7.4|rhel7.5)
            rpm --upgrade --force --nodeps archives/*.rpm
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
# Get k8s master version
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   version - e.g. 1.9.3
#######################################
getK8sMasterVersion() {
    _master="$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes 2>/dev/null | grep master | awk '{ print $5 }' | sed 's/v//')"
    until [ -n "$_master" ]; do
        _master="$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes 2>/dev/null | grep master | awk '{ print $5 }' | sed 's/v//')"
    done
    printf "$_master"
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
