#!/bin/bash

set -e
AIRGAP=0

{% include 'common/common.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/log.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/system.sh' %}

#######################################
# Upgrade Kubernetes on remote workers to master version
# Globals:
#   AIRGAP
# Arguments:
#   None
# Returns:
#   None
#######################################
upgradeK8sWorkers() {
    masterVersion=$(getK8sMasterVersion)
    version="v${masterVersion}"

    workers=$(kubectl get nodes | sed '1d' | grep -v master | grep -v $version | awk '{ print $1 }')

    for node in $workers; do
        kubectl drain "$node" --ignore-daemonsets --delete-local-data --force
        printf "\n\n\tRun the upgrade script on remote node before proceeding: ${GREEN}$node${NC}\n\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "\t${GREEN}cat kubernetes-node-upgrade.sh | sudo bash -s kubernetes-version=$version${NC}"
        else
            printf "\t${GREEN}curl {{ replicated_install_url }}/kubernetes-node-upgrade | sudo bash -s kubernetes-version=$version${NC}"
        fi
        printf "\n\n\tContinue when script has completed\n\n"
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
#   k8sVersion - e.g. v1.10.5
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

    kubeadm upgrade apply $k8sVersion --yes --config=/opt/replicated/kubeadm.conf

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

    sed -i "s/kubernetesVersion:.*/kubernetesVersion: $k8sVersion/" /opt/replicated/kubeadm.conf
    
    spinnerNodeVersion $(kubectl get nodes | grep master | awk '{ print $1 }') $k8sVersion
    spinnerNodesReady
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
    echo $(kubectl get nodes | grep master | awk '{ print $5 }' | sed 's/v//')
}

################################################################################
# Execution starts here
################################################################################

require64Bit
requireRootUser
detectLsbDist
bailIfUnsupportedOS

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            AIRGAP=1
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

export KUBECONFIG=/etc/kubernetes/admin.conf

semverParse $(getK8sMasterVersion)

if [ "$major" -eq 1 ] && [ "$minor" -eq 9 ]; then
    upgradeK8sMaster v1.10.5 $UBUNTU_1604_K8S_10 $CENTOS_74_K8S_10
fi

upgradeK8sWorkers

semverParse $(getK8sMasterVersion)

if [ "$major" -eq 1 ] && [ "$minor" -eq 10 ]; then
    upgradeK8sMaster v1.11.0 $UBUNTU_1604_K8S_11 $CENTOS_74_K8S_11
fi

upgradeK8sWorkers

printf "\n"
printf "\t\t${GREEN} Upgrade Complete ✔${NC}\n"
printf "\n"
