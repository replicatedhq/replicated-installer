#!/bin/bash

set -e
AIRGAP=0
K8S_UPGRADE_PATCH_VERSION="{{ k8s_upgrade_patch_version }}"
HOSTNAME_CHECK=

{% include 'common/common.sh' %}
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
loadIPVSKubeProxyModules
maybeUpgradeKubernetesNode "$KUBERNETES_VERSION"

if [ "$AIRGAP" = "1" ]; then
    airgapLoadKubernetesCommonImages "$KUBERNETES_VERSION"
    if isMasterNode; then
        airgapLoadKubernetesControlImages "$KUBERNETES_VERSION"
    fi

    # When the master upgrades to 1.11.5 it may try to schedule coreDNS pods on
    # this node and will hang until they start, so we need to preload those
    # images. Need to figure this out for future upgrades.
    if [ "$KUBERNETES_VERSION" = "1.10.6" ]; then
        airgapLoadKubernetesCommonImages 1.11.5
    fi
    addInsecureRegistry "$SERVICE_CIDR"
fi
