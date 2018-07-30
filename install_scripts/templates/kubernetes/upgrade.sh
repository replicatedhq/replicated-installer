#!/bin/bash

set -e
AIRGAP=0
KUBERNETES_VERSION="{{ kubernetes_version }}"

{% include 'common/common.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/log.sh' %}
{% include 'common/prompt.sh' %}
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

maybeUpgradeKubernetes "$KUBERNETES_VERSION"
