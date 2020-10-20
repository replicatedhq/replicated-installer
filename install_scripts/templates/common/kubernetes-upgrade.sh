
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
#   KUBERNETES_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
maybeUpgradeKubernetes() {
    if allNodesUpgraded "$KUBERNETES_VERSION"; then
        enableRookCephOperator
        rm -f /opt/replicated/upgrade
        return 0
    fi

    logStep "Preparing to upgrade Kubernetes"
    # indicates an incomplete upgrade
    touch /opt/replicated/upgrade

    upgradeKubernetes

    rm -f /opt/replicated/upgrade
    enableRookCephOperator
    waitCephHealthy
}

#######################################
# Kubeadm requires installing every minor version between current and target.
# kubeadm < 1.11 uses v1alpha1 config file format
# kubeadm 1.11 writes v1alpha2 configs and can also read v1alpha1
# kubeadm 1.12 writes v1alpha3 configs and can also read v1alpha2
# kubeadm 1.13 writes v1beta1 configs and can also read v1alpha3
# Globals:
#   KUBERNETES_ONLY
#   KUBERNETES_VERSION
#   KUBERNETES_TARGET_VERSION_MAJOR
#   KUBERNETES_TARGET_VERSION_MINOR
#   KUBERNETES_TARGET_VERSION_PATCH
# Arguments:
#   None
# Returns:
#   DID_UPGRADE_KUBERNETES
#######################################
DID_UPGRADE_KUBERNETES=0
upgradeKubernetes() {
    # attempt to stop Replicated to reduce Docker load during upgrade
    if [ "$KUBERNETES_ONLY" != "1" ]; then
        kubectl delete deploy --all --grace-period=30 --timeout=60s || true
    fi


    local kubeletVersion="$(getKubeletVersion)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"

    if [ "$kubeletMajor" -ne "$KUBERNETES_TARGET_VERSION_MAJOR" ]; then
        printf "Cannot upgrade from %s to %s\n" "$kubeletVersion" "$KUBERNETES_VERSION"
        return 1
    fi

    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -eq "9" ]; then
        return 0
    fi

    if [ "$kubeletMinor" -eq "9" ] && [ "$KUBERNETES_TARGET_VERSION_MINOR" -gt "9" ]; then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.10.6"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.10.6
            airgapLoadKubernetesControlImages 1.10.6
            airgapLoadReplicatedAddonImagesSecondary
        fi
        upgradeK8sPrimary "1.10.6"
        logSuccess "Kubernetes upgraded to version v1.10.6"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sSecondaries "1.10.6" "0"

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    if [ "$kubeletMinor" -eq "10" ] || ([ "$kubeletMinor" -eq "11" ] && [ "$KUBERNETES_TARGET_VERSION_MINOR" -eq "11" ] && [ "$kubeletPatch" -lt "$KUBERNETES_TARGET_VERSION_PATCH" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.11.5"
        upgradeK8sPrimary "1.11.5"
        logSuccess "Kubernetes upgraded to version v1.11.5"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sSecondaries "1.11.5" "$K8S_UPGRADE_PATCH_VERSION"

    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -eq "11" ]; then
        return 0
    fi

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    if [ "$kubeletMinor" -eq "11" ] &&  [ "$KUBERNETES_TARGET_VERSION_MINOR" -gt "11" ]; then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.12.3"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.12.3
            airgapLoadKubernetesControlImages 1.12.3
            airgapLoadReplicatedAddonImagesSecondary
        fi
        # must migrate alpha1 to alpha2 with kubeadm 1.11 while it's still available
        kubeadm config migrate --old-config /opt/replicated/kubeadm.conf --new-config /opt/replicated/kubeadm.conf
        upgradeK8sPrimary "1.12.3"
        logSuccess "Kubernetes upgraded to version v1.12.3"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sSecondaries "1.12.3" "0"

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    if [ "$kubeletMinor" -eq "12" ] || ([ "$kubeletMinor" -eq "13" ] && [ "$KUBERNETES_TARGET_VERSION_MINOR" -eq "13" ] && [ "$kubeletPatch" -lt "$KUBERNETES_TARGET_VERSION_PATCH" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.13.5"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.13.5
            airgapLoadKubernetesControlImages 1.13.5
            airgapLoadReplicatedAddonImagesSecondary
        fi
        : > /opt/replicated/kubeadm.conf
        makeKubeadmConfig "$KUBERNETES_VERSION"
        upgradeK8sPrimary "1.13.5"
        logSuccess "Kubernetes upgraded to version v1.13.5"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sRemotePrimaries "1.13.5" "$K8S_UPGRADE_PATCH_VERSION"
    upgradeK8sSecondaries "1.13.5" "$K8S_UPGRADE_PATCH_VERSION"

    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -eq "13" ]; then
        return 0
    fi

    enableRookCephOperator
    waitCephHealthy
    # the Rook operator moves mons off any nodes marked unschedulable. This can cause OSDs to become
    # disconnected and be marked down since upgrading requires draining.
    disableRookCephOperator

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    if [ "$kubeletMinor" -eq "13" ] && [ "$KUBERNETES_TARGET_VERSION_MINOR" -gt "13" ]; then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.14.3"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.14.3
            airgapLoadKubernetesControlImages 1.14.3
            airgapLoadReplicatedAddonImagesSecondary
        fi
        upgradeK8sPrimary "1.14.3"
        logSuccess "Kubernetes upgraded to version 1.14.3"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sRemotePrimaries "1.14.3" "0"
    upgradeK8sSecondaries "1.14.3"

    enableRookCephOperator
    waitCephHealthy
    disableRookCephOperator

    kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    kubeletMajor="$major"
    kubeletMinor="$minor"
    kubeletPatch="$patch"

    if [ "$kubeletMinor" -eq "14" ] || ([ "$kubeletMinor" -eq "15" ] && [ "$KUBERNETES_TARGET_VERSION_MINOR" -eq "15" ] && [ "$kubeletPatch" -lt "$KUBERNETES_TARGET_VERSION_PATCH" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading to version v1.15.12"
        if [ "$AIRGAP" = "1" ]; then
            airgapLoadKubernetesCommonImages 1.15.12
            airgapLoadKubernetesControlImages 1.15.12
            airgapLoadReplicatedAddonImagesSecondary
        fi
        kubeadm config migrate --old-config /opt/replicated/kubeadm.conf --new-config /opt/replicated/kubeadm.conf

        k8s_pull_and_retag_control_images 1.15.12
        k8s_pull_and_retag_kubeproxy_image 1.15.12

        upgradeK8sPrimary "1.15.12"
        logSuccess "Kubernetes upgraded to version v1.15.12"
        DID_UPGRADE_KUBERNETES=1
    fi

    upgradeK8sRemotePrimaries "1.15.12" "$K8S_UPGRADE_PATCH_VERSION"
    upgradeK8sSecondaries "1.15.12" "$K8S_UPGRADE_PATCH_VERSION"
}

#######################################
# prompt user to run scripts to change load balancer address on remote primary and secondary nodes
# Globals:
#   LOAD_BALANCER_ADDRESS
#   LOAD_BALANCER_PORT
# Arguments:
#   Replicated version
#   Channel name
# Returns:
#   None
#######################################
runUpgradeScriptOnAllRemoteNodes() {
    local channelName="$2"
    local numPrimaries="$(kubectl get nodes --selector='node-role.kubernetes.io/master' | sed '1d' | wc -l)"
    local numSecondaries="$(kubectl get nodes --selector='!node-role.kubernetes.io/master' | sed '1d' | wc -l)"

    if [ "$numPrimaries" -eq "0" ] && [ "$numSecondaries" -eq "0" ]; then
        return
    fi

    echo ""
    logStep "Kubernetes control plane endpoint updated, upgrading control plane..."
    echo ""

    if [ "$numPrimaries" -gt "1" ]; then
        if [ -n "$LOAD_BALANCER_ADDRESS_CHANGED" ]; then
            BOOTSTRAP_TOKEN="$(kubeadm token create)"
            KUBEADM_TOKEN_CA_HASH="sha256:$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')"

            echo ""
            printf "Run the following script to regenerate the api server certificate on all remote primary nodes before proceeding:\n\n${GREEN}"
            local prefix=""
            if [ -n "$channelName" ]; then
                prefix="/$channelName"
            fi
            if [ "$AIRGAP" = "1" ]; then
                printf "cat kubernetes-update-apiserver-certs.sh | sudo bash -s \\ \n"
            else
                getUrlCmd
                printf "$URLGET_CMD {{ replicated_install_url }}${prefix}/kubernetes-update-apiserver-certs | sudo bash -s"
            fi
            printf " \\ \n    load-balancer-address=$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
            printf " \\ \n    kubeadm-token=$BOOTSTRAP_TOKEN"
            if [ "$UNSAFE_SKIP_CA_VERIFICATION" = "1" ]; then
                printf " \\ \n    unsafe-skip-ca-verification"
            elif [ -n "$KUBEADM_TOKEN_CA_HASH" ]; then
                printf " \\ \n    kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH"
            fi
            if [ "$TAINT_CONTROL_PLANE" = "1" ]; then
                printf " \\ \n    taint-control-plane"
            fi
            printf "${NC}\n\n"
            kubectl get nodes --selector='node-role.kubernetes.io/master' | grep -v "$(node_name)"
            echo ""
            echo ""

            while true; do
                echo ""
                printf "${YELLOW}Have all primary nodes been updated?${NC} "
                if confirmN " "; then
                    break
                fi
            done
        fi
    fi

    if ! waitReplicatedReady "$1"; then
        bail "Replicated failed to report ready"
    fi

    primaryJoinArgs=" --master"
    secondaryJoinArgs=""

    if [ "$UNSAFE_SKIP_CA_VERIFICATION" = "1" ]; then
        replicated2Version
        # --unsafe-skip-ca-verification support as of 2.42.0
        semverCompare "2.42.0" "$INSTALLED_REPLICATED_VERSION"
        if [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
            primaryJoinArgs=$primaryJoinArgs" --unsafe-skip-ca-verification"
            secondaryJoinArgs=$secondaryJoinArgs" --unsafe-skip-ca-verification"
        fi
    fi

    if [ "$numPrimaries" -gt "1" ]; then
        local script="$(/usr/local/bin/replicatedctl cluster node-join-script${primaryJoinArgs} | sed "s/api-service-address=[^ ]*/api-service-address=$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/")"

        echo ""
        printf "Run the upgrade script on all remote primary nodes before proceeding:\n\n"
        printf "${GREEN}${script}${NC}\n\n"
        kubectl get nodes --selector='node-role.kubernetes.io/master' | grep -v "$(node_name)"
        echo ""
        echo ""

        while true; do
            echo ""
            printf "${YELLOW}Have all primary nodes been updated?${NC} "
            if confirmN " "; then
                break
            fi
        done

        spinnerNodesReady
    fi

    local numSecondaries="$(kubectl get nodes --selector='!node-role.kubernetes.io/master' | sed '1d' | wc -l)"
    if [ "$numSecondaries" -gt "0" ]; then
        echo ""
        printf "Run the upgrade script on all remote secondary nodes before proceeding:\n\n${GREEN}"
        /usr/local/bin/replicatedctl cluster node-join-script${secondaryJoinArgs} | sed "s/api-service-address=[^ ]*/api-service-address=$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/"
        printf "${NC}\n\n"
        kubectl get nodes --selector='!node-role.kubernetes.io/master'
        echo ""
        echo ""
        while true; do
            echo ""
            printf "${YELLOW}Have all secondary nodes been updated?${NC} "
            if confirmN " "; then
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
# If kubelet is installed and version is less than specified, upgrade.
# Globals:
#   None
# Arguments:
#   KUBERNETES_VERSION - e.g. 1.10.6
# Returns:
#   None
#######################################
maybeUpgradeKubernetesNode() {
    local KUBERNETES_VERSION="$1"

    local kubeletVersion="$(getK8sNodeVersion)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"

    if [ "$kubeletMajor" -ne "$KUBERNETES_TARGET_VERSION_MAJOR" ]; then
        printf "Cannot upgrade from %s to %s\n" "$kubeletVersion" "$KUBERNETES_VERSION"
        return 1
    fi

    if isCurrentNodePrimaryNode; then
        k8s_pull_and_retag_control_images "$KUBERNETES_VERSION"
    fi
    k8s_pull_and_retag_kubeproxy_image "$KUBERNETES_VERSION"

    if [ "$kubeletMinor" -lt "$KUBERNETES_TARGET_VERSION_MINOR" ] || ([ "$kubeletMinor" -eq "$KUBERNETES_TARGET_VERSION_MINOR" ] && [ "$kubeletPatch" -lt "$KUBERNETES_TARGET_VERSION_PATCH" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading node to version v$KUBERNETES_VERSION"

        upgradeKubeadmCmd "$KUBERNETES_VERSION"

        case "$KUBERNETES_TARGET_VERSION_MINOR" in
            15)
                kubeadm upgrade node

                if isCurrentNodePrimaryNode; then
                    patch_control_plane_images "$KUBERNETES_VERSION"

                    # correctly sets the --resolv-conf flag when systemd-resolver is running (Ubuntu 18)
                    # https://github.com/kubernetes/kubeadm/issues/273
                    kubeadm init phase kubelet-start
                fi

                upgradeK8sNodeHostPackages "$KUBERNETES_VERSION"

                logSuccess "Kubernetes node upgraded to version v1.15.12"
                return
                ;;
        esac

        if [ "$KUBERNETES_TARGET_VERSION_MINOR" -gt 10 ]; then
            # kubeadm alpha phase kubelet write-env-file failed in airgap
            local cgroupDriver=$(docker info 2> /dev/null | grep "Cgroup Driver" | cut -d' ' -f 3)
            local envFile="KUBELET_KUBEADM_ARGS=--cgroup-driver=%s --cni-bin-dir=/opt/cni/bin --cni-conf-dir=/etc/cni/net.d --network-plugin=cni\n"
            printf "$envFile" "$cgroupDriver" > /var/lib/kubelet/kubeadm-flags.env

            if isCurrentNodePrimaryNode; then
                : > /opt/replicated/kubeadm.conf
                makeKubeadmConfig "$KUBERNETES_VERSION"
                local n=0
                while ! kubeadm upgrade node experimental-control-plane ; do
                    n="$(( $n + 1 ))"
                    if [ "$n" -ge "10" ]; then
                        exit 1
                    fi
                    sleep 2
                done
            else
                local n=0
                while ! kubeadm upgrade node config --kubelet-version "$KUBERNETES_VERSION" ; do
                    n="$(( $n + 1 ))"
                    if [ "$n" -ge "10" ]; then
                        exit 1
                    fi
                    sleep 2
                done
            fi
        fi

        upgradeK8sNodeHostPackages "$KUBERNETES_VERSION"

        logSuccess "Kubernetes node upgraded to version v$KUBERNETES_VERSION"
    elif [ "$KUBERNETES_TARGET_VERSION_MINOR" -eq 13 ]; then
        # Sync the config in case it changed.
        logStep "Sync Kubernetes node config"
        if isCurrentNodePrimaryNode; then
            (set -x; kubeadm upgrade node experimental-control-plane)
            : > /opt/replicated/kubeadm.conf
            makeKubeadmConfig "$KUBERNETES_VERSION"
            updateKubernetesAPIServerCerts "$LOAD_BALANCER_ADDRESS" "$LOAD_BALANCER_PORT"
            updateKubeconfigs "https://$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
        else
            (set -x; kubeadm upgrade node config --kubelet-version v1.13.5)
            if [ -n "$LOAD_BALANCER_ADDRESS" ] && [ -n "$LOAD_BALANCER_PORT" ]; then
                sed -i "s/server: https.*/server: https:\/\/$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/" /etc/kubernetes/kubelet.conf
            fi
        fi
        logSuccess "Kubernetes node config upgraded"
    elif [ "$KUBERNETES_TARGET_VERSION_MINOR" -eq 15 ]; then
        logStep "Sync Kubernetes node config"

        rm -f /opt/replicated/kubeadm.conf
        makeKubeadmJoinConfigV1Beta2

        if isCurrentNodePrimaryNode; then
            joinUpdateApiServerCerts

            updateKubeconfigs "https://$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
        else
            sed -i "s/server: https.*/server: https:\/\/$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/" /etc/kubernetes/kubelet.conf
        fi

        kubeadm upgrade node

        if isCurrentNodePrimaryNode; then
            patch_control_plane_images "$KUBERNETES_VERSION"
        fi
    fi
}

#######################################
# Regenerates api server certs with "kubeadm join phase control-plane-prepare certs"
# Globals:
#   PRIVATE_ADDRESS
# Arguments:
#   None
# Returns:
#   None
#######################################
joinUpdateApiServerCerts() {
    logStep "Regenerate api server certs"
    rm -f /etc/kubernetes/pki/apiserver.*
    kubeadm join phase control-plane-prepare certs --config /opt/replicated/kubeadm.conf
    logSuccess "API server certs regenerated"

    restartK8sAPIServerContainer "$PRIVATE_ADDRESS" "6443"
}

#######################################
# Regenerates kubeconfig for control plane components "kubeadm join phase control-plane-prepare kubeconfig"
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
joinUpdateKubeconfigs() {
    logStep "Regenerate kubeconfig for control plane components"
    rm /etc/kubernetes/*.conf
    kubeadm join phase control-plane-prepare kubeconfig --config /opt/replicated/kubeadm.conf
    kubeadm join phase kubelet-start --config /opt/replicated/kubeadm.conf
    logSuccess "Kubeconfig for control plane components server certs regenerated"
}

#######################################
# Run `kubectl get nodes` until it succeeds or up to 1 minute
# Globals:
#   None
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
# Upgrade Kubernetes on remote secondary nodes to version. Never downgrades a secondary node.
# Globals:
#   KUBERNETES_TARGET_VERSION_MAJOR
#   KUBERNETES_TARGET_VERSION_MINOR
#   KUBERNETES_TARGET_VERSION_PATCH
# Arguments:
#   None
# Returns:
#   None
#######################################
allNodesUpgraded() {
    while read -r node; do
        local nodeVersion="$(echo "$node" | awk '{ print $5 }' | sed 's/v//' )"
        semverParse "$nodeVersion"
        local nodeMajor="$major"
        local nodeMinor="$minor"
        local nodePatch="$patch"

        if [ "$nodeMajor" -eq "$KUBERNETES_TARGET_VERSION_MAJOR" ] &&  [ "$nodeMinor" -lt "$KUBERNETES_TARGET_VERSION_MINOR" ]; then
            return 1
        fi
        if [ "$nodeMajor" -eq "$KUBERNETES_TARGET_VERSION_MAJOR" ] && [ "$nodeMinor" -eq "$KUBERNETES_TARGET_VERSION_MINOR" ] && [ "$nodePatch" -lt "$KUBERNETES_TARGET_VERSION_PATCH" ] && [ "$K8S_UPGRADE_PATCH_VERSION" = "1" ]; then
            return 1
        fi
    done <<< "$(listNodes)"

    return 0
}

#######################################
# Upgrade Kubernetes on remote secondary nodes to version. Never downgrades a secondary node.
# Globals:
#   AIRGAP
# Arguments:
#   k8sVersion - e.g. 1.10.6
#   shouldUpgradePatch
# Returns:
#   None
#######################################
upgradeK8sSecondaries() {
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
    # not an error if there are no secondaries
    # TODO better primary identification
    local secondaries="$(echo "$nodes" | sed '1d' | grep -v " master " || :)"

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
        local upgradeArgs="hostname-check=${nodeName} kubernetes-version=${k8sVersion}"
        if [ "$shouldUpgradePatch" = "1" ]; then
            upgradeArgs=$upgradeArgs" kubernetes-upgrade-patch-version"
        fi
        if [ "$UNSAFE_SKIP_CA_VERIFICATION" = "1" ]; then
            upgradeArgs=$upgradeArgs" unsafe-skip-ca-verification"
        fi

        if [ "$AIRGAP" = "1" ]; then
            printf "\t${GREEN}cat kubernetes-node-upgrade.sh | sudo bash -s airgap ${upgradeArgs} ${NC}"
        else
            printf "\t${GREEN}curl {{ replicated_install_url }}/kubernetes-node-upgrade | sudo bash -s ${upgradeArgs} ${NC}"
        fi
        while true; do
            echo ""
            printf "Has script completed? "
            if confirmN " "; then
                break
            fi
        done
        kubectl uncordon "$nodeName"
    done <<< "$secondaries"

    spinnerNodesReady
}

#######################################
# Upgrade Kubernetes on remote primary nodes to version. Never downgrades.
# Globals:
#   AIRGAP
# Arguments:
#   k8sVersion - e.g. 1.10.6
#   shouldUpgradePatch
# Returns:
#   None
#######################################
upgradeK8sRemotePrimaries() {
    k8sVersion="$1"
    shouldUpgradePatch="$2"

    semverParse "$k8sVersion"
    local upgradeMajor="$major"
    local upgradeMinor="$minor"
    local upgradePatch="$patch"

    local nodes=
    n=0
    while ! nodes="$(kubectl get nodes --show-labels 2>/dev/null)"; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "30" ]; then
            # this should exit script on non-zero exit code and print error message
            nodes="$(kubectl get nodes --show-labels)"
        fi
        sleep 2
    done
    # not an error if there are no remote primary nodes
    local primaries="$(echo "$nodes" | sed '1d' | grep "node-role.kubernetes.io/master" || :)"

    while read -r node; do
        if [ -z "$node" ]; then
            continue
        fi
        nodeName=$(echo "$node" | awk '{ print $1 }')
        if [ "$nodeName" = "$(hostname | tr '[:upper:]' '[:lower:]')" ]; then
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
        if [ "$nodeMinor" -eq "$upgradeMinor" ] && [ "$nodePatch" -ge "$upgradePatch" ]; then
            continue
        fi
        if [ "$nodeMinor" -eq "$upgradeMinor" ] && [ "$shouldUpgradePatch" != "1" ]; then
            continue
        fi
        kubectl drain "$nodeName" \
            --delete-local-data \
            --ignore-daemonsets \
            --force \
            --grace-period=30 \
            --timeout=300s \
            --pod-selector 'app notin (rook-ceph-mon,rook-ceph-osd,rook-ceph-osd-prepare,rook-ceph-operator,rook-ceph-agent)' || true


        printf "\n\n\tRun the upgrade script on remote primary node before proceeding: ${GREEN}$nodeName${NC}\n\n"
        local upgradePatchFlag=""
        if [ "$shouldUpgradePatch" = "1" ]; then
            upgradePatchFlag=" kubernetes-upgrade-patch-version"
        fi
        if [ "$AIRGAP" = "1" ]; then
            printf "\t${GREEN}cat kubernetes-node-upgrade.sh | sudo bash -s airgap hostname-check=${nodeName} kubernetes-version=${k8sVersion}${upgradePatchFlag}${NC}"
        else
            printf "\t${GREEN}curl {{ replicated_install_url }}/kubernetes-node-upgrade | sudo bash -s hostname-check=${nodeName} kubernetes-version=${k8sVersion}${upgradePatchFlag}${NC}"
        fi
        while true; do
            echo ""
            printf "Has script completed? "
            if confirmN " "; then
                break
            fi
        done
        kubectl uncordon "$nodeName"
    done <<< "$primaries"

    spinnerNodesReady
}

#######################################
# Upgrade Kubernetes on primary node
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
upgradeK8sPrimary() {
    k8sVersion=$1
    local node=$(hostname | tr '[:upper:]' '[:lower:]')

    prepareK8sPackageArchives "$k8sVersion"

    # must use kubeadm binary to begin upgrade before upgrading kubeadm package
    # https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
    cp archives/kubeadm /usr/bin/kubeadm
    chmod a+rx /usr/bin/kubeadm

    spinnerK8sAPIHealthy
    kubeadm upgrade apply "v$k8sVersion" --yes --config /opt/replicated/kubeadm.conf --force

    patch_control_plane_images "$k8sVersion"

    waitForNodes

    if [ "$k8sVersion" = "1.15.12" ]; then
        kubectl -n kube-system patch daemonset/kube-proxy -p '{"spec":{"template":{"spec":{"containers":[{"name":"kube-proxy","image":"{{ images.kube_proxy_V11512.name }}"}]}}}}'
    fi

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
        centos7.4|centos7.5|centos7.6|centos7.7|centos7.8|rhel7.4|rhel7.5|rhel7.6|rhel7.7|rhel7.8)
            rpm --upgrade --force --nodeps archives/*.rpm
            ;;
        *)
            bail "Unsuported OS: $LSB_DIST$DIST_VERSION"
            ;;
    esac

    rm -rf archives

    systemctl daemon-reload
    systemctl start kubelet
    spinnerK8sAPIHealthy
    kubectl uncordon "$node"

    sed -i "s/kubernetesVersion:.*/kubernetesVersion: v$k8sVersion/" /opt/replicated/kubeadm.conf

    waitForNodes
    spinnerNodeVersion "$node" "$k8sVersion"
    spinnerNodesReady
}

#######################################
# Upgrade Kubernetes packages on node
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
upgradeK8sNodeHostPackages() {
    k8sVersion=$1

    systemctl stop kubelet

    prepareK8sPackageArchives "$k8sVersion"

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04|ubuntu18.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i --force-depends-version archives/*.deb
            ;;
        centos7.4|centos7.5|centos7.6|centos7.7|centos7.8|rhel7.4|rhel7.5|rhel7.6|rhel7.7|rhel7.8)
            rpm --upgrade --force --nodeps archives/*.rpm
            ;;
        *)
            bail "Unsuported OS: $LSB_DIST$DIST_VERSION"
            ;;
    esac

    rm -rf archives

    systemctl daemon-reload
    systemctl start kubelet
}

#######################################
# Upgrade kubeadm binary, which is used to upgrade nodes before upgrading host packages.
# Globals:
#   None
# Arguments:
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
upgradeKubeadmCmd() {
    local k8sVersion="$1"
    prepareK8sPackageArchives "$k8sVersion"
    cp archives/kubeadm /usr/bin/kubeadm
    chmod a+rx /usr/bin/kubeadm
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

updateKubernetesAPIServerCerts()
{
    if ! certHasSAN /etc/kubernetes/pki/apiserver.crt "$1"; then
        logStep "Regenerate api server certs"
        rm -f /etc/kubernetes/pki/apiserver.*
        kubeadm init phase certs apiserver --config /opt/replicated/kubeadm.conf
        logSuccess "API server certs regenerated"

        restartK8sAPIServerContainer "$PRIVATE_ADDRESS" "6443"
    fi
}

restartK8sAPIServerContainer()
{
    logStep "Restart kubernetes api server"
    # admin.conf may not have been updated yet so kubectl may not work
    docker ps | grep k8s_kube-apiserver | awk '{print $1}' | xargs docker stop &>/dev/null || true
    docker ps -a | grep k8s_kube-apiserver | awk '{print $1}' | xargs docker rm -f &>/dev/null || true
    while ! curl -skf "https://$1:$2/healthz" >/dev/null ; do
        sleep 1
    done
    logSuccess "Kubernetes api server restarted"
}

updateKubeconfigs()
{
    if ! confHasEndpoint /etc/kubernetes/admin.conf "$1"; then
        sed -i "s/server: https.*/server: https:\/\/$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/" /etc/kubernetes/admin.conf
    fi

    if ! confHasEndpoint /etc/kubernetes/kubelet.conf "$1"; then
        sed -i "s/server: https.*/server: https:\/\/$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/" /etc/kubernetes/kubelet.conf
    fi

    if ! confHasEndpoint /etc/kubernetes/scheduler.conf "$1"; then
        sed -i "s/server: https.*/server: https:\/\/$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/" /etc/kubernetes/scheduler.conf
    fi

    if ! confHasEndpoint /etc/kubernetes/controller-manager.conf "$1"; then
        sed -i "s/server: https.*/server: https:\/\/$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT/" /etc/kubernetes/controller-manager.conf
    fi
}

upgradeInProgress()
{
    test -e /opt/replicated/upgrade
}
