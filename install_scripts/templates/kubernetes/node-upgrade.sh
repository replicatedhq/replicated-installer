#!/bin/bash

set -e
AIRGAP=0

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

maybeUpgradeKubernetesNode "$KUBERNETES_VERSION"

if [ "$AIRGAP" = "1" ]; then
    airgapLoadKubernetesCommonImages "$KUBERNETES_VERSION"

    # When the master upgrades to 1.11.1 it may try to schedule coreDNS pods on
    # this node and will hang until they start, so we need to preload those
    # images. Need to figure this out for future upgrades.
    if [ "$KUBERNETES_VERSION" = "1.10.6" ]; then
        airgapLoadKubernetesCommonImages 1.11.1
    fi
fi
