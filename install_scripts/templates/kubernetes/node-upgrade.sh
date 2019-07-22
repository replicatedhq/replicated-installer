#!/bin/bash

set -e
AIRGAP=0
K8S_UPGRADE_PATCH_VERSION="{{ k8s_upgrade_patch_version }}"
HOSTNAME_CHECK=

{% include 'common/common.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/log.sh' %}
{% include 'common/system.sh' %}
{% include 'common/kubernetes-upgrade.sh' %}

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
            KUBERNETES_VERSION="$_value"
            ;;
        kubernetes-upgrade-patch-version|kubernetes_upgrade_patch_version)
            K8S_UPGRADE_PATCH_VERSION=1
            ;;
        hostname-check)
            HOSTNAME_CHECK="$_value"
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

if [ -n "$HOSTNAME_CHECK" ]; then
    if [ "$HOSTNAME_CHECK" != "$(hostname)" ]; then
        bail "this script should be executed on host $HOSTNAME_CHECK"
    fi
fi

export KUBECONFIG=/etc/kubernetes/admin.conf

parseKubernetesTargetVersion
setK8sPatchVersion
checkDockerK8sVersion
loadIPVSKubeProxyModules

if [ "$AIRGAP" = "1" ]; then
    airgapLoadKubernetesCommonImages "$KUBERNETES_VERSION"
    if isMasterNode; then
        airgapLoadKubernetesControlImages "$KUBERNETES_VERSION"
    fi

    # Pre-load images for the next version if the current upgrade is an even version.
    # This prevents CoreDNS and Kube-Proxy from getting into ImagePullBackoff state
    # on this node when the upgrade to the next version begins on the primary master.
    case "$KUBERNETES_VERSION" in
        "1.10.6")
            airgapLoadKubernetesCommonImages 1.11.5
            ;;
        "1.12.3")
            airgapLoadKubernetesCommonImages 1.13.5
            ;;
        "1.14.3")
            airgapLoadKubernetesCommonImages 1.15.0
            ;;
    esac

    addInsecureRegistry "$SERVICE_CIDR"
fi

maybeUpgradeKubernetesNode "$KUBERNETES_VERSION"
