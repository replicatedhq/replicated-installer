
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
# If kubernetes is installed and version is less than specified, upgrade. Kubeadm requires installing every minor version between current and target.
# Globals:
#   None
# Arguments:
#   upgradeVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
maybeUpgradeKubernetes() {
    local k8sTargetVersion="$1"
    semverParse "$k8sTargetVersion"
    local k8sTargetMajor="$major"
    local k8sTargetMinor="$minor"
    local k8sTargetPatch="$patch"

    local kubeletVersion="$(getKubeletVersion)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"

    if [ "$kubeletMajor" -ne "$k8sTargetMajor" ]; then
        printf "Cannot upgrade from %s to %s\n" "$kubeletVersion" "$k8sTargetVersion"
        return 1
    fi

    if [ "$kubeletMinor" -eq "9" ] && [ "$k8sTargetMinor" -eq "9" ]; then
        return 0
    fi

    if [ "$kubeletMinor" -eq "9" ] && [ "$k8sTargetMinor" -gt "9" ]; then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.10.6"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.10.6
            airgapLoadKubernetesControlImages 1.10.6
        fi
        upgradeK8sMaster "1.10.6"
        logSuccess "Kubernetes upgraded to version v1.10.6"
    fi

    upgradeK8sWorkers "1.10.6" "0"

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    if [ "$kubeletMinor" -eq "10" ] || ([ "$kubeletMinor" -eq "11" ] && [ "$k8sTargetVersion" -eq "11" ] && [ "$kubeletPatch" -lt "$k8sTargetPatch" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.11.5"
        upgradeK8sMaster "1.11.5" "$UBUNTU_1604_K8S_11" "$CENTOS_74_K8S_11"
        logSuccess "Kubernetes upgraded to version v1.11.5"
    fi

    upgradeK8sWorkers "1.11.5" "$K8S_UPGRADE_PATCH_VERSION"
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
    if [ "$kubeletMinor" -lt "$k8sTargetMinor" ] || ([ "$kubeletMinor" -eq "$k8sTargetMinor" ] && [ "$kubeletPatch" -lt "$k8sTargetPatch" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = 0 ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading node to version v$k8sTargetVersion"

        upgradeK8sNode "$k8sTargetVersion"

        if [ "$k8sTargetMinor" -gt 10 ]; then
            # kubeadm alpha phase kubelet write-env-file failed in airgap
            local cgroupDriver=$(sudo docker info 2> /dev/null | grep "Cgroup Driver" | cut -d' ' -f 3)
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

        systemctl restart kubelet

        logSuccess "Kubernetes node upgraded to version v$k8sTargetVersion"
    fi
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
    waitForNodes

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i --force-depends-version archives/*.deb
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
            dpkg -i --force-depends-version archives/*.deb
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
