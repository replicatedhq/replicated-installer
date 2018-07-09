#!/bin/bash

set -e
AIRGAP=0

{% include 'common/common.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/log.sh' %}
{% include 'common/system.sh' %}

#######################################
# Upgrade Kubernetes on worker node
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. v1.10.5
# Returns:
#   None
#######################################
upgradeK8sNode() {
    k8sVersion=$1
    pkgTag=$(k8sPackageTag $k8sVersion)

    echo "Upgrading node to Kubernetes $k8sVersion"

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
        kubernetes-version|kubernetes_version)
            K8S_VERSION=${_value}
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

if [ -z "$K8S_VERSION" ]; then
    bail "kubernetes-version is required"
fi

upgradeK8sNode $K8S_VERSION

# not supportted in kubeadm < 1.11
kubeadm upgrade node config --kubelet-version $(kubelet --version | cut -d ' ' -f 2) 2>/dev/null || :

systemctl restart kubelet

printf "\n"
printf "\t\t${GREEN} Node Upgrade Complete ✔${NC}\n"
printf "\n"
