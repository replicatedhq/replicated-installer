#######################################
#
# kubernetes.sh
#
# require selinux.sh common.sh docker.sh cli-script.sh
#
#######################################

UBUNTU_1604_K8S_9=ubuntu-1604-v1.9.3-20181112
UBUNTU_1604_K8S_10=ubuntu-1604-v1.10.6-20181112
UBUNTU_1604_K8S_11=ubuntu-1604-v1.11.5-20181204
UBUNTU_1604_K8S_12=ubuntu-1604-v1.12.3-20181211
UBUNTU_1604_K8S_13=ubuntu-1604-v1.13.5-20190411
UBUNTU_1604_K8S_14=ubuntu-1604-v1.14.3-20190702
UBUNTU_1604_K8S_15=ubuntu-1604-v1.15.12-20201021

UBUNTU_1804_K8S_13=ubuntu-1804-v1.13.5-20190411
UBUNTU_1804_K8S_14=ubuntu-1804-v1.14.3-20190702
UBUNTU_1804_K8S_15=ubuntu-1804-v1.15.12-20201021

RHEL7_K8S_9=rhel7-v1.9.3-20180806
RHEL7_K8S_10=rhel7-v1.10.6-20180806
RHEL7_K8S_11=rhel7-v1.11.5-20181204
RHEL7_K8S_12=rhel7-v1.12.3-20181211
RHEL7_K8S_13=rhel7-v1.13.5-20190411
RHEL7_K8S_14=rhel7-v1.14.3-20190702
RHEL7_K8S_15=rhel7-v1.15.12-20201021

DAEMON_NODE_KEY=replicated.com/daemon

#######################################
# Set the patch version in KUBERNETES_VERSION.
# Globals:
#   KUBERNETES_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
setK8sPatchVersion() {
    semverParse "$KUBERNETES_VERSION"
    local k8sMajor="$major"
    local k8sMinor="$minor"
    local k8sPatch="$patch"

    case "$k8sMinor" in
        9)
            # 1.9.3
            k8sPatch="3"
            ;;
        11)
            # 1.11.5
            k8sPatch="5"
            ;;
        13)
            # 1.13.5
            k8sPatch="5"
            ;;
        15)
            # 1.15.12
            k8sPatch="12"
    esac
    KUBERNETES_VERSION="$k8sMajor.$k8sMinor.$k8sPatch"
}

#######################################
# Parse Kubernetes version that should be installed after the script completes
# Globals:
#   KUBERNETES_VERSION
# Arguments:
#   None
# Returns:
#   KUBERNETES_TARGET_VERSION_MAJOR
#   KUBERNETES_TARGET_VERSION_MINOR
#   KUBERNETES_TARGET_VERSION_PATCH
#######################################
parseKubernetesTargetVersion() {
    semverParse "$KUBERNETES_VERSION"
    KUBERNETES_TARGET_VERSION_MAJOR="$major"
    KUBERNETES_TARGET_VERSION_MINOR="$minor"
    KUBERNETES_TARGET_VERSION_PATCH="$patch"
}

#######################################
# Print an unsupported OS message and exit 1
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
bailIfUnsupportedOS() {
    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04|ubuntu18.04)
            ;;
        centos7.4|centos7.5|centos7.6|centos7.7|centos7.8|rhel7.4|rhel7.5|rhel7.6|rhel7.7|rhel7.8)
            ;;
        *)
            bail "Kubernetes install is not supported on ${LSB_DIST} ${DIST_VERSION}"
            ;;
    esac
}


#######################################
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
installCNIPlugins() {
    logStep "configure CNI"
    mkdir -p /tmp/cni-plugins
    mkdir -p /opt/cni/bin


    case "$KUBERNETES_TARGET_VERSION_MINOR" in
        13|14|15)
            if [ "$AIRGAP" = "1" ]; then
                docker load < k8s-cni-0-7-5.tar
            fi
            docker run -v /tmp:/out replicated/k8s-cni:0.7.5
            ;;
        *)
            if [ "$AIRGAP" = "1" ]; then
                docker load < k8s-cni.tar
            fi
            docker run -v /tmp:/out replicated/k8s-cni:0.6.0
            ;;
    esac

    tar zxfv /tmp/cni.tar.gz -C /opt/cni/bin
    mkdir -p /etc/cni/net.d
    logSuccess "CNI configured"
}

#######################################
# Lookup package tag for kubernetes version and distribution
# Globals:
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. 1.9.3
# Returns:
#   pkgTag
#######################################
k8sPackageTag() {
    k8sVersion=$1

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            case "$k8sVersion" in
                1.9.3)
                    echo "$UBUNTU_1604_K8S_9"
                    ;;
                1.10.6)
                    echo "$UBUNTU_1604_K8S_10"
                    ;;
                1.11.5)
                    echo "$UBUNTU_1604_K8S_11"
                    ;;
                1.12.3)
                    echo "$UBUNTU_1604_K8S_12"
                    ;;
                1.13.5)
                    echo "$UBUNTU_1604_K8S_13"
                    ;;
                1.14.3)
                    echo "$UBUNTU_1604_K8S_14"
                    ;;
                1.15.12)
                    echo "$UBUNTU_1604_K8S_15"
                    ;;
                *)
                    bail "Unsupported Kubernetes version $k8sVersion"
                    ;;
            esac
            ;;
        ubuntu18.04)
            case "$k8sVersion" in
                1.13.5)
                    echo "$UBUNTU_1804_K8S_13"
                    ;;
                1.14.3)
                    echo "$UBUNTU_1804_K8S_14"
                    ;;
                1.15.12)
                    echo "$UBUNTU_1804_K8S_15"
                    ;;
                *)
                    bail "Unsupported Kubernetes version $k8sVersion"
                    ;;
            esac
            ;;
        centos7.4|centos7.5|centos7.6|centos7.7|centos7.8|rhel7.4|rhel7.5|rhel7.6|rhel7.7|rhel7.8)
            case "$k8sVersion" in
                1.9.3)
                    echo "$RHEL7_K8S_9"
                    ;;
                1.10.6)
                    echo "$RHEL7_K8S_10"
                    ;;
                1.11.5)
                    echo "$RHEL7_K8S_11"
                    ;;
                1.12.3)
                    echo "$RHEL7_K8S_12"
                    ;;
                1.13.5)
                    echo "$RHEL7_K8S_13"
                    ;;
                1.14.3)
                    echo "$RHEL7_K8S_14"
                    ;;
                1.15.12)
                    echo "$RHEL7_K8S_15"
                    ;;
                *)
                    bail "Unsupported Kubernetes version $k8sVersion"
                    ;;
            esac
            ;;
        *)
            bail "Unsupported distribution $LSB_DIST$DIST_VERSION"
            ;;
    esac

}

#######################################
# Install K8s host commands for OS
# Globals:
#   LSB_DIST
#   LSB_VERSION
# Arguments:
#   k8sVersion - e.g. 1.9.3
# Returns:
#   None
#######################################
installKubernetesComponents() {
    k8sVersion=$1

    logStep "Install kubelet, kubeadm, kubectl and cni binaries"

    if kubernetesHostCommandsOK; then
        logSuccess "Kubernetes components already installed"
        return
    fi

    prepareK8sPackageArchives $k8sVersion

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04|ubuntu18.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i --force-depends-version archives/*.deb
            ;;

        centos7.4|centos7.5|centos7.6|centos7.7|centos7.8|rhel7.4|rhel7.5|rhel7.6|rhel7.7|rhel7.8)
            # This needs to be run on Linux 3.x nodes for Rook
            modprobe rbd
            echo 'rbd' > /etc/modules-load.d/replicated-rook.conf

            # tabs in heredoc stripped
            cat <<-EOF >  /etc/sysctl.d/k8s.conf
			net.bridge.bridge-nf-call-ip6tables = 1
			net.bridge.bridge-nf-call-iptables = 1
			net.ipv4.conf.all.forwarding = 1
			EOF

            sysctl --system

            rpm --upgrade --force --nodeps archives/*.rpm
            service docker restart
            ;;

        *)
            bail "Kubernetes install is not supported on ${LSB_DIST} ${DIST_VERSION}"
            ;;
    esac

    rm -rf archives

    if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
        sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    fi
    systemctl enable kubelet && systemctl start kubelet

    logSuccess "Kubernetes components installed"
}

#######################################
# Returns 0 if all Kubernetes host commands exist
# Globals:
#   KUBERNETES_VERSION
# Arguments:
#   None
# Returns:
#   1 if any host command version is missing, 0 if all are available
#######################################
kubernetesHostCommandsOK() {
    if ! commandExists kubelet; then
        printf "kubelet command missing - will install host components\n"
        return 1
    fi
    if ! commandExists kubeadm; then
        printf "kubeadm command missing - will install host components\n"
        return 1
    fi
    if ! commandExists kubectl; then
        printf "kubectl command missing - will install host components\n"
        return 1
    fi

    return 0
}

#######################################
# Load kernel modules for kube proxy's IPVS mode
# Globals:
#   IPVS
# Arguments:
#   None
# Returns:
#   None
#######################################
loadIPVSKubeProxyModules() {
    if [ "$IPVS" != "1" ]; then
        return
    fi
    if lsmod | grep -q ip_vs ; then
        return
    fi

    kernel_major=$(uname -r | cut -d'.' -f1)
    kernel_minor=$(uname -r | cut -d'.' -f2)
    if [ "$kernel_major" -lt "4" ] || ([ "$kernel_major" -eq "4" ] && [ "$kernel_minor" -lt "19" ]); then
        modprobe nf_conntrack_ipv4
    else
        modprobe nf_conntrack
    fi

    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh

    echo 'nf_conntrack_ipv4' > /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_rr' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_wrr' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_sh' >> /etc/modules-load.d/replicated-ipvs.conf
}

#######################################
# Unpack kubernetes images
# Globals:
#   None
# Arguments:
#   k8sVersion - e.g. 1.9.3
# Returns:
#   None
#######################################
airgapLoadKubernetesCommonImages() {
    local k8sVersion="$1"
    logStep "common images"

    # TODO if the install is 1.11.1 and is not being upgraded to 1.11.5 this will unnecessarily load the 1.11.5 images

    docker load < k8s-images-common-${k8sVersion}.tar
    case "$k8sVersion" in
        1.9.3)
            airgapLoadKubernetesCommonImages193
            ;;
        1.10.6)
            airgapLoadKubernetesCommonImages1106
            ;;
        1.11.5)
            airgapLoadKubernetesCommonImages1115
            ;;
        1.12.3)
            airgapLoadKubernetesCommonImages1123
            ;;
        1.13.5)
            airgapLoadKubernetesCommonImages1135
            ;;
        1.14.3)
            airgapLoadKubernetesCommonImages1143
            ;;
        1.15.12)
            airgapLoadKubernetesCommonImages11512
            ;;
        *)
            bail "Unsupported Kubernetes version $k8sVersion"
            ;;
    esac

    logSuccess "common images"
}

airgapLoadKubernetesCommonImages193() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-common:v1.9.3-20180809"

    # uh. its kind of insane that we have to do this. the linuxkit pkg
    # comes to us without tags, which seems super useless... we should build our own bundler maybe
    (
        set -x
        docker tag 35fdc6da5fd8 gcr.io/google_containers/kube-proxy-amd64:v1.9.3
        docker tag db76ee297b85 gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.7
        docker tag 5d049a8c4eec gcr.io/google_containers/k8s-dns-kube-dns-amd64:1.14.7
        docker tag 5feec37454f4 gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64:1.14.7
        docker tag 99e59f495ffa gcr.io/google_containers/pause-amd64:3.0
        docker tag 86ff1a48ce14 weaveworks/weave-kube:2.4.0
        docker tag 647ad6d59818 weaveworks/weave-npc:2.4.0
        docker tag bf0c403ea58d weaveworks/weaveexec:2.4.0
        docker tag 9c1f09fe9a86 docker.io/registry:2
        docker tag 6521ac58ca80 envoyproxy/envoy-alpine:v1.6.0
        docker tag 6a9ec4bcb60e gcr.io/heptio-images/contour:v0.5.0
        docker tag b5c343f1a3a6 rook/ceph:v0.8.1
    )
}

# only the images needed for kubeadm to upgrade from 1.9 to 1.11
airgapLoadKubernetesCommonImages1106() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-common:v1.10.6-20180809"

    (
        set -x
        docker tag 8a9a40dda603 k8s.gcr.io/kube-proxy-amd64:v1.10.6
        docker tag c2ce1ffb51ed k8s.gcr.io/k8s-dns-dnsmasq-nanny-amd64:1.14.8
        docker tag 6f7f2dc7fab5 k8s.gcr.io/k8s-dns-sidecar-amd64:1.14.8
        docker tag 80cc5ea4b547 k8s.gcr.io/k8s-dns-kube-dns-amd64:1.14.8
        docker tag da86e6ba6ca1 k8s.gcr.io/pause-amd64:3.1
    )
}

airgapLoadKubernetesCommonImages1115() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-common:v1.11.5-20181207"

    # kube-proxy is a daemon set so clusters that started at v1.11.1 will need this available on all nodes
    (
        set -x
        docker tag d5c25579d0ff k8s.gcr.io/kube-proxy-amd64:v1.11.1
        docker tag aa7b610992c0 k8s.gcr.io/kube-proxy-amd64:v1.11.5
        docker tag da86e6ba6ca1 k8s.gcr.io/pause:3.1
        docker tag b3b94275d97c k8s.gcr.io/coredns:1.1.3
        docker tag 86ff1a48ce14 weaveworks/weave-kube:2.4.0
        docker tag 647ad6d59818 weaveworks/weave-npc:2.4.0
        docker tag bf0c403ea58d weaveworks/weaveexec:2.4.0
        docker tag 9c1f09fe9a86 docker.io/registry:2
        docker tag 6521ac58ca80 docker.io/envoyproxy/envoy-alpine:v1.6.0
        docker tag 6a9ec4bcb60e gcr.io/heptio-images/contour:v0.5.0
        docker tag b5c343f1a3a6 rook/ceph:v0.8.1
        docker tag 376cb7e8748c replicated/replicated-hostpath-provisioner:cd1d272
    )
}

# only the images needed for kubeadm to upgrade from 1.11 to 1.13
airgapLoadKubernetesCommonImages1123() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-common:v1.12.3-20181207"

    docker tag ab97fa69b926 k8s.gcr.io/kube-proxy:v1.12.3
    docker tag 367cdc8433a4 k8s.gcr.io/coredns:1.2.2
}

airgapLoadKubernetesCommonImages1135() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-common:v1.13.5-20190507"

    (
        set -x
        docker tag 2ee69cad74bf k8s.gcr.io/kube-proxy:v1.13.5
        docker tag da86e6ba6ca1 k8s.gcr.io/pause:3.1
        docker tag f59dcacceff4 k8s.gcr.io/coredns:1.2.6
        docker tag 1f394ae9e226 docker.io/weaveworks/weave-kube:2.5.1
        docker tag 789b7f496034 docker.io/weaveworks/weave-npc:2.5.1
        docker tag 4cccd7ef6421 docker.io/weaveworks/weaveexec:2.5.1
        docker tag d5ef411ad932 docker.io/registry:2
        docker tag 1186b980992e docker.io/envoyproxy/envoy-alpine:v1.9.1
        docker tag 0a0aad7cff75 gcr.io/heptio-images/contour:v0.11.0
        docker tag eb6fe47e91ae docker.io/rook/ceph:v1.0.0
        docker tag 243030ce8ef0 docker.io/ceph/ceph:v14.2.0-20190410
        docker tag 376cb7e8748c replicated/replicated-hostpath-provisioner:cd1d272
    )
}

# only the images needed for kubeadm to upgrade from 1.13 to 1.15
airgapLoadKubernetesCommonImages1143() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-common:v1.14.3-20190702"

    (
        set -x
        docker tag 004666307c5b k8s.gcr.io/kube-proxy:v1.14.3
        docker tag eb516548c180 k8s.gcr.io/coredns:1.3.1
    )
}

airgapListKubernetesCommonImages11512() {
    echo "{{ images.kube_proxy_v11512.id }} {{ images.kube_proxy_v11512.name }}"
    echo "{{ images.pause_31.id }} {{ images.pause_31.name }}"
    echo "{{ images.coredns_131.id }} {{ images.coredns_131.name }}"
    echo "{{ images.weave_kube_265.id }} {{ images.weave_kube_265.name }}"
    echo "{{ images.weave_npc_265.id }} {{ images.weave_npc_265.name }}"
    echo "{{ images.weaveexec_265.id }} {{ images.weaveexec_265.name }}"
    echo "{{ images.registry_262.id }} {{ images.registry_262.name }}"
    echo "{{ images.envoy_v1100.id }} {{ images.envoy_v1100.name }}"
    echo "{{ images.contour_v0130.id }} {{ images.contour_v0130.name }}"
    echo "{{ images.rook_ceph_103.id }} {{ images.rook_ceph_103.name }}"
    echo "{{ images.rook_ceph_106.id }} {{ images.rook_ceph_106.name }}"
    echo "{{ images.ceph_1420.id }} {{ images.ceph_1420.name }}"
    echo "{{ images.ceph_1422.id }} {{ images.ceph_1422.name }}"
    echo "{{ images.replicated_hostpath_provisioner_cd1d272.id }} {{ images.replicated_hostpath_provisioner_cd1d272.name }}"
    echo "{{ images.k8s_dns_node_cache_11513.id }} {{ images.k8s_dns_node_cache_11513.name }}"
}

airgapLoadKubernetesCommonImages11512() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-common:v1.15.12-20201028"

    while read -r image; do
        (set -x; docker tag $image)
    done <<< "$(airgapListKubernetesCommonImages11512)"
}

#######################################
# Unpack kubernetes images
# Globals:
#   None
# Arguments:
#   k8sVersion - e.g. 1.9.3
# Returns:
#   None
#######################################
airgapLoadKubernetesControlImages() {
    local k8sVersion="$1"
    logStep "control plane images"

    # TODO if the install is 1.11.1 and is not being upgraded to 1.11.5 this will unnecessarily load the 1.11.5 images

    docker load < k8s-images-control-${k8sVersion}.tar
    case "$k8sVersion" in
        1.9.3)
            airgapLoadKubernetesControlImages193
            ;;
        1.10.6)
            airgapLoadKubernetesControlImages1106
            ;;
        1.11.5)
            airgapLoadKubernetesControlImages1115
            ;;
        1.12.3)
            airgapLoadKubernetesControlImages1123
            ;;
        1.13.5)
            airgapLoadKubernetesControlImages1135
            ;;
        1.14.3)
            airgapLoadKubernetesControlImages1143
            ;;
        1.15.12)
            airgapLoadKubernetesControlImages11512
            ;;
        *)
            bail "Unsupported Kubernetes version $k8sVersion"
            ;;
    esac

    logSuccess "control plane images"
}

airgapLoadReplicatedAddonImagesSecondary() {
    semverCompare "{{ replicated_version }}" "2.34.0"
    if [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
        return
    fi

    airgapLoadReplicatedAddonImages
}

airgapLoadReplicatedAddonImages() {
    logStep "replicated addons"
    docker load < replicated-sidecar-controller.tar
    docker load < replicated-operator.tar

    if [ -f volume-mount-checker.tar ]; then
        docker load < volume-mount-checker.tar
    fi

    logSuccess "replicated addons"
}

airgapLoadKubernetesControlImages193() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-control:v1.9.3-20180809"

    (
        set -x
        docker tag 83dbda6ee810 gcr.io/google_containers/kube-controller-manager-amd64:v1.9.3
        docker tag 360d55f91cbf gcr.io/google_containers/kube-apiserver-amd64:v1.9.3
        docker tag d3534b539b76 gcr.io/google_containers/kube-scheduler-amd64:v1.9.3
        docker tag 59d36f27cceb gcr.io/google_containers/etcd-amd64:3.1.11
    )
}

airgapLoadKubernetesControlImages1106() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-control:v1.10.6-20180809"

    (
        set -x
        docker tag 6e29896cbeca k8s.gcr.io/kube-apiserver-amd64:v1.10.6
        docker tag dd246160bf59 k8s.gcr.io/kube-scheduler-amd64:v1.10.6
        docker tag 3224e7c2de11 k8s.gcr.io/kube-controller-manager-amd64:v1.10.6
        docker tag 52920ad46f5b k8s.gcr.io/etcd-amd64:3.1.12
    )
}

airgapLoadKubernetesControlImages1115() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-control:v1.11.5-20181204"

    (
        set -x
        docker tag 3a239c93cfbe k8s.gcr.io/kube-apiserver-amd64:v1.11.5
        docker tag 67fbf264abce k8s.gcr.io/kube-controller-manager-amd64:v1.11.5
        docker tag 3280f0c09d18 k8s.gcr.io/kube-scheduler-amd64:v1.11.5
        docker tag b8df3b177be2 k8s.gcr.io/etcd-amd64:3.2.18
    )
}

airgapLoadKubernetesControlImages1123() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-control:v1.12.3-20181210"

    (
        set -x
        docker tag 6b54f7bebd72 k8s.gcr.io/kube-apiserver:v1.12.3
        docker tag 5e75513787b1 k8s.gcr.io/kube-scheduler:v1.12.3
        docker tag c79022eb8bc9 k8s.gcr.io/kube-controller-manager:v1.12.3
        docker tag 3cab8e1b9802 k8s.gcr.io/etcd:3.2.24
    )
}

airgapLoadKubernetesControlImages1135() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-control:v1.13.5-20190411"

    (
        set -x
        docker tag 90332c1b9a4b k8s.gcr.io/kube-apiserver:v1.13.5
        docker tag b6b315f4f34a k8s.gcr.io/kube-controller-manager:v1.13.5
        docker tag c629ac1dae38 k8s.gcr.io/kube-scheduler:v1.13.5
        docker tag 3cab8e1b9802 k8s.gcr.io/etcd:3.2.24
    )
}

airgapLoadKubernetesControlImages1143() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-control:v1.14.3-20190702"

    (
        set -x
        docker tag 9946f563237c k8s.gcr.io/kube-apiserver:v1.14.3
        docker tag 953364a3ae7a k8s.gcr.io/kube-scheduler:v1.14.3
        docker tag ac2ce44462bc k8s.gcr.io/kube-controller-manager:v1.14.3
        docker tag 2c4adeb21b4f k8s.gcr.io/etcd:3.3.10
    )
}

airgapListKubernetesControlImages11512() {
    echo "{{ images.kube_apiserver_v11512.id }} {{ images.kube_apiserver_v11512.name }}"
    echo "{{ images.kube_controller_manager_v11512.id }} {{ images.kube_controller_manager_v11512.name }}"
    echo "{{ images.kube_scheduler_v11512.id }} {{ images.kube_scheduler_v11512.name }}"
    echo "{{ images.etcd_3310.id }} {{ images.etcd_3310.name }}"
    echo "{{ images.etcd_347.id }} {{ images.etcd_347.name }}"
}

airgapLoadKubernetesControlImages11512() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-control:v1.15.12-20201028"

    while read -r image; do
        (set -x; docker tag $image)
    done <<< "$(airgapListKubernetesControlImages11512)"
}

function list_all_required_images() {
    local k8sVersion="$1"
    local nodeName="$2"

    case "$k8sVersion" in
        1.15.12)
            airgapListKubernetesCommonImages11512 | awk '{print $2}'
            if is_primary_node "$nodeName" ; then
                airgapListKubernetesControlImages11512 | awk '{print $2}'
            fi
            ;;
        *)
            # unsupported
            ;;
    esac
}

function patch_control_plane_images() {
    local k8sVersion="$1"

    case "$k8sVersion" in
        1.15.12)
            patch_control_plane_images_11512
            ;;
    esac
}

function patch_control_plane_images_11512() {
    # patch all control plane manifests with versioned images
    sed -i "s/image:.*kube-apiserver:.*$/image: $(echo {{ images.kube_apiserver_v11512.name }} | sed 's/\//\\\//g')/" /etc/kubernetes/manifests/kube-apiserver.yaml
    sed -i "s/image:.*kube-controller-manager:.*$/image: $(echo {{ images.kube_controller_manager_v11512.name }} | sed 's/\//\\\//g')/" /etc/kubernetes/manifests/kube-controller-manager.yaml
    sed -i "s/image:.*kube-scheduler:.*$/image: $(echo {{ images.kube_scheduler_v11512.name }} | sed 's/\//\\\//g')/" /etc/kubernetes/manifests/kube-scheduler.yaml
}

function get_kubeadm_config_image() {
    kubeadm config images list --config=/opt/replicated/kubeadm.conf 2>/dev/null | grep "$1"
}

airgapPushReplicatedImagesToRegistry() {
    logStep "Pushing images to registry at $1"

    dockerGetRepoTagFromTar replicated.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

    dockerGetRepoTagFromTar replicated-ui.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

    if [ -f replicated-operator.tar ]; then
        dockerGetRepoTagFromTar replicated-operator.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    if [ -f replicated-sidecar-controller.tar ]; then
        dockerGetRepoTagFromTar replicated-sidecar-controller.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    if [ -f volume-mount-checker.tar ]; then
        dockerGetRepoTagFromTar volume-mount-checker.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    dockerGetRepoTagFromTar cmd.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

    dockerGetRepoTagFromTar statsd-graphite.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

    dockerGetRepoTagFromTar premkit.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

    if [ -f debian.tar ]; then
        dockerGetRepoTagFromTar debian.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    if [ -f support-bundle.tar ]; then
        dockerGetRepoTagFromTar support-bundle.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    # these have been monocontainer'd since 2.24.0
    if [ -f retraced.tar ]; then
        dockerGetRepoTagFromTar retraced.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-postgres.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-nsqd.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    # these have been included together prior to 2.21.0
    if [ -f retraced-processor.tar ]; then
        dockerGetRepoTagFromTar retraced-processor.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-db.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-api.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-cron.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    # single retraced bundle no longer included since 2.21.0
    if [ -f retraced-bundle.tar.gz ]; then
        dockerGetRepoTagFromTar retraced-processor.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-postgres.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-nsqd.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-db.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-api.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

        dockerGetRepoTagFromTar retraced-cron.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    # redis is included in Retraced <= 1.1.10
    if [ -f retraced-redis.tar ]; then
        dockerGetRepoTagFromTar retraced-redis.tar
        dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"
    fi

    logSuccess "Images pushed to registry at $1 successfully"
}

#######################################
# Creates an archives directory with the correct K8s packages for a given
# version of K8s on the current distribution.
# Globals:
#   AIRGAP
#   LSB_DIST
#   DIST_VERSION
# Arguments:
#   k8sVersion - e.g. 1.9.3
# Returns:
#   None
#######################################
prepareK8sPackageArchives() {
    k8sVersion=$1
    pkgTag=$(k8sPackageTag $k8sVersion)

    if [ "$AIRGAP" = "1" ]; then
        docker load < packages-kubernetes-${pkgTag}.tar
    fi
    docker run \
      -v $PWD:/out \
      "replicated/k8s-packages:${pkgTag}"
}

#######################################
# Gets node name from kubectl ignoring errors
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   primary node names
#######################################
k8sPrimaryNodeNames() {
    set +e
    _primary="$(kubectl get nodes --show-labels 2>/dev/null | grep 'node-role.kubernetes.io/master' | awk '{ print $1 }')"
    until [ -n "$_primary" ]; do
        _primary="$(kubectl get nodes --show-labels 2>/dev/null | grep 'node-role.kubernetes.io/master' | awk '{ print $1 }')"
    done
    set -e
    printf "$_primary"
}

#######################################
# Return status code 0 if a namespace exists, else 1
# Globals:
#   None
# Arguments:
#   namespace
# Returns:
#   None
#######################################
k8sNamespaceExists() {
    kubectl get namespaces | grep -q "$1"
}

#######################################
# Return status code 0 if there is a storageclass with the default annotation, else 1
# Globals:
#   None
# Arguments:
#   provisioner
# Returns:
#   None
#######################################
defaultStorageClassExists() {
    kubectl get storageclass -o=jsonpath='{.items[*].metadata.annotations}' | grep -q "storageclass.kubernetes.io/is-default-class":"true"
}


#######################################
# Display a spinner until all nodes are ready, TODO timeout
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerNodesReady()
{
    waitForNodes

    local delay=0.75
    local spinstr='|/-\'
    while true; do
        set +e
        local nodes="$(kubectl get nodes 2>/dev/null)"
        local _exit="$?"
        set -e
        if [ "$_exit" -eq "0" ]; then
            local numNodes="$(kubectl get nodes 2>/dev/null | awk 'NR > 1' | wc -l)"
            if [ "$numNodes" -gt "0" ] && ! echo "$nodes" | grep -q "NotReady"; then
                break
            fi
        fi
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

#######################################
# Display a spinner until the Kubernetes API /healthz endpoint returns ok.
# Kubeadm preflight checks fail unless healthz returns ok.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerK8sAPIHealthy()
{
    local addr="${PRIVATE_ADDRESS}:6443"
    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        addr="${LOAD_BALANCER_ADDRESS}:${LOAD_BALANCER_PORT}"
    fi

    local delay=1
    local elapsed=0
    local spinstr='|/-\'
    while [ "$(curl --noproxy "*" -sk https://$addr/healthz)" != "ok" ]; do
        elapsed=$(($elapsed + $delay))
        if [ "$elapsed" -gt 120 ]; then
            bail "Kubernetes API failed to report healthy"
        fi
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

#######################################
# Display a spinner until a node reaches a version
# Globals:
#   None
# Arguments:
#   node
#   k8sVersion - e.g. 1.10.6
# Returns:
#   None
#######################################
spinnerNodeVersion()
{
    node=$1
    k8sVersion=$2

    local delay=0.75
    local spinstr='|/-\'
    while true; do
        set +e
        local nout="$(kubectl get node $node 2>/dev/null)"
        local _exit="$?"
        set -e
        if [ "$_exit" -eq "0" ] && [ "$(echo "$nout" | sed '1d' | awk '{ print $5 }')" == "v$k8sVersion" ]; then
            break
        fi
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

#######################################
# Will wait for the get nodes call to return success
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
waitForNodes()
{
    n=0
    while ! kubectl get nodes >/dev/null 2>&1; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "120" ]; then
            # this should exit script on non-zero exit code and print error message
            kubectl get nodes 1>/dev/null
        fi
        sleep 2
    done
}

#######################################
# Display a spinner until the primary node is ready
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerPrimaryNodeReady()
{
    logStep "Await node ready"
    spinnerNodesReady
    logSuccess "Primary Node Ready!"
}

#######################################
# Replicated < 2.26 uses the replicated.com/daemon label to generate the node join script.
#
# Globals:
#   DAEMON_NODE_KEY, REPLICATED_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
labelPrimaryNodeDeprecated()
{
    semverCompare "$REPLICATED_VERSION" "2.26.0"
    if [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
        return
    fi
    if kubectl get nodes --show-labels | grep -q "$DAEMON_NODE_KEY" ; then
        return
    fi
    kubectl label nodes --overwrite "$(k8sPrimaryNodeNames)" "$DAEMON_NODE_KEY"=
}

#######################################
# Check if the current node is a primary
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if primary node, else 1
#######################################
isCurrentNodePrimaryNode()
{
    if [ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
        return 0
    else
        return 1
    fi
}


#######################################
# Check if the node is a primary running in a non-HA cluster
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if single node primary, else 1
#######################################
isSingleNodePrimary()
{
    if ! isCurrentNodePrimaryNode; then
        return 1
    fi
    if [ "$HA_CLUSTER" = "1" ]; then
        return 1
    fi
    # joined primary nodes do not have HA_CLUSTER set
    if cat /opt/replicated/kubeadm.conf | grep -q 'JoinConfiguration' && cat /opt/replicated/kubeadm.conf | grep -q 'controlPlane:'; then
        return 1
    fi

    return 0
}

#######################################
# Spinner Pod Running
# Globals:
#   None
# Arguments:
#   Namespace, Pod prefix
# Returns:
#   None
#######################################
spinnerPodRunning()
{
    namespace=$1
    podPrefix=$2

    local delay=0.75
    local spinstr='|/-\'
    while ! kubectl -n "$namespace" get pods 2>/dev/null | grep "^$podPrefix" | awk '{ print $3}' | grep '^Running$' > /dev/null ; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

#######################################
# Blocks until Replicated is ready
# Globals:
#   None
# Arguments:
#   Replicated version
# Returns:
#   None
#######################################
waitReplicatedReady() {
    kubectl rollout status deployment/replicated

    waitReplicatedctlReady "$REPLICATED_VERSION"
}

#######################################
# Blocks until replicatedctl is ready
# Globals:
#   None
# Arguments:
#   Replicated version
# Returns:
#   None
#######################################
waitReplicatedctlReady() {
    # TODO: spinner
    logSubstep "wait for replicated to report ready"
    for i in {1..60}; do
        if isReplicatedctlReady "$1"; then
            return 0
        fi
        sleep 2
    done
    return 1
}

#######################################
# Spinner Replicated Ready
# Globals:
#   None
# Arguments:
#   Replicated version
# Returns:
#   None
#######################################
spinnerReplicatedReady()
{
    logStep "Await replicated ready"
    sleep 2
    if ! waitReplicatedReady "$1"; then
        bail "Replicated failed to report ready"
    fi
    logSuccess "Replicated Ready!"
}

#######################################
# Return code 0 unless `replicatedctl system status` succeeds
# Globals:
#   None
# Arguments:
#   Replicated version
# Returns:
#   None
#######################################
isReplicatedctlReady() {
    semverCompare "$1" "2.26.0"
    if [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
        /usr/local/bin/replicatedctl system status 2>/dev/null | grep -q '"ready"'
    else
        /usr/local/bin/replicatedctl task ls > /dev/null 2>&1
    fi
}

#######################################
# Spinner Rook Ready,
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerRookReady()
{
    logStep "Await rook ready"
    spinnerPodRunning rook-ceph-system rook-ceph-operator
    spinnerPodRunning rook-ceph-system rook-ceph-agent
    spinnerPodRunning rook-ceph-system rook-discover
    spinnerRookFlexVolumePluginReady
    logSuccess "Rook Ready!"
}

#######################################
# Spinner Rook FlexVolume plugin ready
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerRookFlexVolumePluginReady()
{
    local delay=0.75
    local spinstr='|/-\'
    while [ ! -e /usr/libexec/kubernetes/kubelet-plugins/volume/exec/ceph.rook.io~rook-ceph-system/rook-ceph-system ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

#######################################
# Spinner Hostpath Provisioner Ready,
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerHostpathProvisionerReady()
{
    logStep "Await hostpath provisioner ready"
    spinnerPodRunning kube-system replicated-hostpath-provisioner
    logSuccess "Hostpath Provisioner Ready!"
}

#######################################
# Spinner kube-system ready
# Globals:
#   None
# Arguments:
#   k8sVersion - e.g. 1.9.3
# Returns:
#   None
#######################################
spinnerKubeSystemReady()
{
    k8sVersion=$1

    logStep "Await kube-system services ready"
    spinnerPodRunning kube-system weave-net
    if [ "$k8sVersion" = "1.9.3" ]; then
        spinnerPodRunning kube-system kube-dns
    else
        spinnerPodRunning kube-system coredns
    fi
    spinnerPodRunning kube-system kube-proxy
    logStep "Kube system services ready"
}

weave_reset()
{
    BRIDGE=weave
    DATAPATH=datapath
    CONTAINER_IFNAME=ethwe

    WEAVEKUBE_IMAGE="{{ images.weave_kube_265.name }}"
    WEAVEEXEC_IMAGE="{{ images.weaveexec_265.name }}"
    DOCKER_BRIDGE=docker0

    # if we never unpacked/pulled the weave image, its unlikely we need to do any of this
    if ! dockerImageExists "$WEAVEKUBE_IMAGE"; then
        return
    fi

    docker pull "$WEAVEEXEC_IMAGE"

    DOCKER_BRIDGE_IP=$(docker run --rm --pid host --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=/usr/bin/weaveutil $WEAVEEXEC_IMAGE bridge-ip $DOCKER_BRIDGE)

    for NETDEV in $BRIDGE $DATAPATH ; do
        if [ -d /sys/class/net/$NETDEV ] ; then
            if [ -d /sys/class/net/$NETDEV/bridge ] ; then
                ip link del $NETDEV
            else
                docker run --rm --pid host --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=/usr/bin/weaveutil $WEAVEEXEC_IMAGE delete-datapath $NETDEV
            fi
        fi
    done

    # Remove any lingering bridged fastdp, pcap and attach-bridge veths
    for VETH in $(ip -o link show | grep -o v${CONTAINER_IFNAME}[^:@]*) ; do
        ip link del $VETH >/dev/null 2>&1 || true
    done

    if [ "$DOCKER_BRIDGE" != "$BRIDGE" ] ; then
        run_iptables -t filter -D FORWARD -i $DOCKER_BRIDGE -o $BRIDGE -j DROP 2>/dev/null || true
    fi

    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dport 53  -j ACCEPT  >/dev/null 2>&1 || true
    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p tcp --dport 53  -j ACCEPT  >/dev/null 2>&1 || true

    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p tcp --dst $DOCKER_BRIDGE_IP --dport $PORT          -j DROP >/dev/null 2>&1 || true
    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dst $DOCKER_BRIDGE_IP --dport $PORT          -j DROP >/dev/null 2>&1 || true
    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dst $DOCKER_BRIDGE_IP --dport $(($PORT + 1)) -j DROP >/dev/null 2>&1 || true

    run_iptables -t filter -D FORWARD -i $BRIDGE ! -o $BRIDGE -j ACCEPT 2>/dev/null || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    run_iptables -t filter -D FORWARD -i $BRIDGE -o $BRIDGE -j ACCEPT 2>/dev/null || true
    run_iptables -F WEAVE-NPC >/dev/null 2>&1 || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -j WEAVE-NPC 2>/dev/null || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -m state --state NEW -j NFLOG --nflog-group 86 2>/dev/null || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -j DROP 2>/dev/null || true
    run_iptables -X WEAVE-NPC >/dev/null 2>&1 || true

    run_iptables -F WEAVE-EXPOSE >/dev/null 2>&1 || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -j WEAVE-EXPOSE 2>/dev/null || true
    run_iptables -X WEAVE-EXPOSE >/dev/null 2>&1 || true

    run_iptables -t nat -F WEAVE >/dev/null 2>&1 || true
    run_iptables -t nat -D POSTROUTING -j WEAVE >/dev/null 2>&1 || true
    run_iptables -t nat -D POSTROUTING -o $BRIDGE -j ACCEPT >/dev/null 2>&1 || true
    run_iptables -t nat -X WEAVE >/dev/null 2>&1 || true

    for LOCAL_IFNAME in $(ip link show | grep v${CONTAINER_IFNAME}pl | cut -d ' ' -f 2 | tr -d ':') ; do
        ip link del ${LOCAL_IFNAME%@*} >/dev/null 2>&1 || true
    done
}

#######################################
# Attempt to remove replicated and kubernetes from the system
# Globals:
#   none
# Arguments:
#   FORCE_RESET
# Returns:
#   None
#######################################
k8s_reset() {
    # if FORCE_RESET is set, skip this
    if [ "$1" != 1 ]; then
        printf "${YELLOW}"
        printf "WARNING: \n"
        printf "\n"
        printf "    The \"reset\" command will attempt to remove replicated and kubernetes from this system.\n"
        printf "\n"
        printf "    This command is intended to be used only for \n"
        printf "    increasing iteration speed on development servers. It has the \n"
        printf "    potential to leave your machine in an unrecoverable state. It is \n"
        printf "    not recommended unless you will easily be able to discard this server\n"
        printf "    and provision a new one if something goes wrong.\n${NC}"
        printf "\n"
        printf "Would you like to continue? "

        if ! confirmN; then
            printf "Not resetting\n"
            exit 1
        fi
    fi

    if commandExists "kubectl" && [ -f "/opt/replicated/kubeadm.conf" ]; then
        set +e
        kubectl delete all --all
        appNSs=$(kubectl get ns | grep replicated- | awk '{ print $1 }')
        for appNS in "$appNSs"; do
            kubectl delete ns "$appNS"
        done
        nodes=$(kubectl get nodes --output=go-template --template="{{ '{{' }}range .items{{ '}}{{' }}.metadata.name{{ '}}' }} {{ '{{' }}end{{ '}}' }}")
        for node in $nodes; do
            # continue after timeout errors
            kubectl drain "$node" --delete-local-data --force --ignore-daemonsets --grace-period=30 --timeout=300s || :
            kubectl delete node "$node"
        done
        set -e
    fi

    if commandExists "kubeadm"; then
        kubeadm reset --force
    fi

    weave_reset

    rm -rf /opt/replicated
    rm -rf /opt/cni
    rm -rf /etc/kubernetes
    rm -rf /var/lib/replicated
    rm -rf /var/lib/rook
    rm -rf /var/lib/etcd
    rm -f /usr/bin/kubeadm /usr/bin/kubelet /usr/bin/kubectl
    kill $(ps aux | grep '[k]ubelet' | awk '{print $2}') 2> /dev/null
}

#######################################
# Get kubelet version
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   version - e.g. 1.11.5
#######################################
getKubeletVersion() {
    kubelet --version | cut -d ' ' -f 2 | sed 's/v//'
}

#######################################
# Get kubectl client command version
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   version - e.g. 1.11.5
#######################################
getKubectlVersion() {
    kubectl version | grep 'Client Version' | tr " " "\n" | grep GitVersion | cut -d'"' -f2 | sed 's/v//'
}

#######################################
# Get kubeadm command version
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   version - e.g. 1.11.5
#######################################
getKubeadmVersion() {
    kubeadm version | tr " " "\n" | grep GitVersion | cut -d'"' -f2 | sed 's/v//'
}

#######################################
# Generate kubeadm ClusterConfiguration v1beta1 and KubeProxyConfiguration v1alpha1
# Globals:
#   KUBERNETES_VERSION
#   PRIVATE_ADDRESS
#   PUBLIC_ADDRESS
#   IPVS
#   HA_CLUSTER
#   LOAD_BALANCER_ADDRESS
#   LOAD_BALANCER_PORT
# Arguments:
#   KUBERNETES_VERSION - e.g. 1.11.5
# Returns:
#   version - e.g. 1.11.5
#######################################
makeKubeadmConfig() {
    local k8sVersion="$1"
    cat << EOF >> /opt/replicated/kubeadm.conf
---
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta1
kubernetesVersion: v$k8sVersion
networking:
  serviceSubnet: $SERVICE_CIDR
apiServer:
  extraArgs:
    service-node-port-range: "80-60000"
  certSANs:
EOF
    if [ -n "$PUBLIC_ADDRESS" ]; then
        cat <<EOF >> /opt/replicated/kubeadm.conf
  - $PUBLIC_ADDRESS
EOF
    fi
    if [ -n "$LOAD_BALANCER_ADDRESS" ] && [ -n "$LOAD_BALANCER_PORT" ]; then
        cat <<EOF >> /opt/replicated/kubeadm.conf
  - $LOAD_BALANCER_ADDRESS
controlPlaneEndpoint: "$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
EOF
    else
        cat <<EOF >> /opt/replicated/kubeadm.conf
  - $PRIVATE_ADDRESS
EOF
    fi

    if [ "$IPVS" = "1" ]; then
        cat <<EOF >> /opt/replicated/kubeadm.conf
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
EOF
    fi
}

appendKubeadmClusterConfigV1Beta2() {
    k8sVersion=$1

    etcdVersion=$2
    local etcdImageTag=
    case $etcdVersion in
        3.3) etcdImageTag='{{ images.etcd_3310.name.split(":")[1] }}' ;;
        *)   etcdImageTag='{{ images.etcd_347.name.split(":")[1] }}' ;;
    esac

    cat <<EOF >> /opt/replicated/kubeadm.conf
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: v$k8sVersion
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
imageRepository: docker.io/replicated
controllerManager: {}
dns:
  type: CoreDNS
  imageRepository: k8s.gcr.io
etcd:
  local:
    dataDir: /var/lib/etcd
    imageRepository: docker.io/replicated
    imageTag: $etcdImageTag
networking:
  serviceSubnet: $SERVICE_CIDR
apiServer:
  extraArgs:
    service-node-port-range: "80-60000"
  certSANs:
  - $PRIVATE_ADDRESS
EOF
    if [ -n "$PUBLIC_ADDRESS" ]; then
        cat <<EOF >> /opt/replicated/kubeadm.conf
  - $PUBLIC_ADDRESS
EOF
    fi
    if [ -n "$LAST_LOAD_BALANCER_ADDRESS" ] && [ "$LAST_LOAD_BALANCER_ADDRESS" != "$LOAD_BALANCER_ADDRESS" ]; then
        cat <<EOF >> /opt/replicated/kubeadm.conf
  - $LAST_LOAD_BALANCER_ADDRESS
EOF
    fi
    if [ -n "$LOAD_BALANCER_ADDRESS" ] && [ -n "$LOAD_BALANCER_PORT" ]; then
        cat <<EOF >> /opt/replicated/kubeadm.conf
  - $LOAD_BALANCER_ADDRESS
controlPlaneEndpoint: "$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
EOF
    fi
}

appendKubeProxyConfigV1Alpha1() {
    if [ "$IPVS" != "1" ]; then
        return
    fi
    cat <<EOF >> /opt/replicated/kubeadm.conf
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
EOF
}

appendKubeletConfigV1Beta1() {
    if [ "$IPVS" != "1" ]; then
        return
    fi
    if [ "$NODELOCAL_DNSCACHE" != "1" ]; then
        return
    fi
    cat <<EOF >> /opt/replicated/kubeadm.conf
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
clusterDNS:
- $NODELOCAL_ADDRESS
EOF
}

#######################################
# Generate kubeadm JoinConfiguration
# Globals:
#   PRIVATE_ADDRESS
#   KUBEADM_TOKEN
#   KUBEADM_TOKEN_CA_HASH
#   API_SERVICE_ADDRESS
# Arguments:
#   None
# Returns:
#   None
#######################################
makeKubeadmJoinConfig() {
    cat << EOF > /opt/replicated/kubeadm.conf
---
kind: JoinConfiguration
apiVersion: kubeadm.k8s.io/v1beta1
nodeRegistration:
  kubeletExtraArgs:
    node-ip: $PRIVATE_ADDRESS
discovery:
  bootstrapToken:
    token: $KUBEADM_TOKEN
    apiServerEndpoint: $API_SERVICE_ADDRESS
    caCertHashes:
    - $KUBEADM_TOKEN_CA_HASH
EOF
    if [ "$PRIMARY" = "1" ]; then
        cat << EOF >> /opt/replicated/kubeadm.conf
controlPlane: {}
EOF
    fi
}

#######################################
# Generate kubeadm JoinConfiguration v1beta2
# Globals:
#   PRIVATE_ADDRESS
#   KUBEADM_TOKEN
#   KUBEADM_TOKEN_CA_HASH
#   API_SERVICE_ADDRESS
#   UNSAFE_SKIP_CA_VERIFICATION
# Arguments:
#   None
# Returns:
#   None
#######################################
makeKubeadmJoinConfigV1Beta2() {
    cat << EOF > /opt/replicated/kubeadm.conf
---
kind: JoinConfiguration
apiVersion: kubeadm.k8s.io/v1beta2
nodeRegistration:
EOF
    if [ "$PRIMARY" != "1" ] || [ "$TAINT_CONTROL_PLANE" != "1" ]; then
        cat << EOF >> /opt/replicated/kubeadm.conf
  taints: []
EOF
    fi
    cat << EOF >> /opt/replicated/kubeadm.conf
  kubeletExtraArgs:
    node-ip: $PRIVATE_ADDRESS
discovery:
  bootstrapToken:
    token: $KUBEADM_TOKEN
    apiServerEndpoint: $API_SERVICE_ADDRESS
EOF
    if [ "$UNSAFE_SKIP_CA_VERIFICATION" = "1" ]; then
        cat << EOF >> /opt/replicated/kubeadm.conf
    unsafeSkipCAVerification: true
EOF
    else
        cat << EOF >> /opt/replicated/kubeadm.conf
    caCertHashes:
    - $KUBEADM_TOKEN_CA_HASH
EOF
    fi
    if [ "$PRIMARY" = "1" ]; then
        cat << EOF >> /opt/replicated/kubeadm.conf
controlPlane: {}
EOF
    fi
}

exportKubeconfig() {
    cp /etc/kubernetes/admin.conf $HOME/admin.conf
    chown $SUDO_USER:$SUDO_GID $HOME/admin.conf
    chmod 444 /etc/kubernetes/admin.conf
    if ! grep -q "kubectl completion bash" /etc/profile; then
        echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /etc/profile
        echo "source <(kubectl completion bash)" >> /etc/profile
    fi
}

#######################################
# Add insecure registry to Docker
# Globals:
#   None
# Arguments:
#   registry host
# Returns:
#   ADDED_INSECURE_REGISTRY
#######################################
ADDED_INSECURE_REGISTRY=0
addInsecureRegistry() {
    if grep -q "insecure-registry $1" /etc/systemd/system/docker.service.d/replicated-registry.conf 2>/dev/null ; then
        return
    fi
    if grep "insecure-registries" /etc/docker/daemon.json 2>/dev/null | grep -q "$1" ; then
        return
    fi

    # configure using /etc/docker/daemon.json since that does not require a docker restart
    if insertJSONArray "/etc/docker/daemon.json" "insecure-registries" "$1" ; then
        systemctl kill -s HUP --kill-who=main docker.service
        ADDED_INSECURE_REGISTRY=1
        return
    fi

    bail "Docker could not be configured to use in-cluster registry $1"
}

#######################################
# Allow scheduling on control plane nodes
# Globals:
#   None
# Arguments:
#   registry host
# Returns:
#   None
#######################################
untaintPrimary() {
    logStep "remove node-role.kubernetes.io/master:NoSchedule taint from primary node"
    kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- || \
        echo "Taint not found or already removed. The above error can be ignored."
    logSuccess "primary taint removed"
}

#######################################
# Check if a cert has an IP or Domain in its SANs
# Globals:
#   None
# Arguments:
#   cert filepath, IP
# Returns:
#   None
#######################################
certHasSAN()
{
    openssl x509 -in "$1" -noout -text | grep -Eq "DNS:$2|IP Address:$2"
}

#######################################
# Check if a kubeconfig points to a specific endpoint
# Globals:
#   None
# Arguments:
#   cert filepath, endpoint
# Returns:
#   None
#######################################
confHasEndpoint()
{
    if [ "$(cat $1 | grep 'server:' | awk '{ print $2 }')" = "$2" ]; then
        return 0
    fi
    return 1
}


#######################################
# Check if Rook 1.0+ is installed
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None, exits 0 if Rook 1.0+ is detected
#######################################
isRook1()
{
    kubectl -n rook-ceph get cephblockpools replicapool &>/dev/null
}

#######################################
# Check if Rook 1.0.3+ is installed
# Globals:
#   ROOK_VERSION
# Arguments:
#   None
# Returns:
#   None, exits 0 if Rook 1.0.3+ is detected
#######################################
isRook103Plus()
{
    getRookVersion
    semverCompare "1.0.3" "$ROOK_VERSION"
    if [ "$SEMVER_COMPARE_RESULT" -gt "0" ]; then
        return 1
    fi
    return 0
}

#######################################
# Check if Rook is installed
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None, exits 0 if Rook is installed
#######################################
isRookInstalled()
{
    if kubectl get ns rook-ceph &>/dev/null ; then
        return 0
    else
        return 1
    fi
}

#######################################
# Check if Rook 1.0.6+ is installed
# Globals:
#   ROOK_VERSION
# Arguments:
#   None
# Returns:
#   None, exits 0 if Rook 1.0.6+ is detected
#######################################
isRook106Plus()
{
    getRookVersion
    semverCompare "1.0.6" "$ROOK_VERSION"
    if [ "$SEMVER_COMPARE_RESULT" -gt "0" ]; then
        return 1
    fi
    return 0
}

#######################################
# Check if Rook 1.0.3 is installed
# Globals:
#   ROOK_VERSION
# Arguments:
#   None
# Returns:
#   None, exits 0 if Rook 1.0.3 is detected
#######################################
isRook103()
{
    getRookVersion
    if [ "$ROOK_VERSION" = "1.0.3" ]; then
        return 0
    fi
    return 1
}

#######################################
# Get rook version
# Globals:
#   ROOK_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
ROOK_VERSION=
getRookVersion()
{
    ROOK_VERSION="$(kubectl -n rook-ceph-system get deploy rook-ceph-operator -oyaml 2>/dev/null \
        | grep ' image: ' \
        | awk -F':' 'NR==1 { print $3 }' \
        | sed 's/v\([^-]*\).*/\1/')"
}

#######################################
# Check if Rook 0.8 is installed
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None, exits 0 if Rook 0.8 is detected
#######################################
isRook08()
{
    kubectl -n rook-ceph get pool replicapool &>/dev/null
}

#######################################
# Check if Etcd 3.3 is installed
# Globals:
#   ETCD_VERSION
# Arguments:
#   None
# Returns:
#   None, exits 0 if Etcd 3.3 is detected
#######################################
isEtcd33()
{
    getEtcdVersion
    semverCompare "3.3.0" "$ETCD_VERSION"
    if [ "$SEMVER_COMPARE_RESULT" -gt "0" ]; then
        return 1
    fi
    semverCompare "3.4.0" "$ETCD_VERSION"
    if [ "$SEMVER_COMPARE_RESULT" -le "0" ]; then
        return 1
    fi
    return 0
}

#######################################
# Get etcd version
# Globals:
#   ETCD_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
ETCD_VERSION=
getEtcdVersion()
{
    ETCD_VERSION="$(kubectl -n kube-system get pod -l tier=control-plane -l component=etcd -oyaml 2>/dev/null \
        | grep ' image: ' \
        | awk -F':' 'NR==1 { print $3 }' \
        | sed 's/\([^-]*\).*/\1/')"
}

#######################################
# Check if Etcd is installed
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None, exits 0 if Etcd is installed
#######################################
isEtcdInstalled()
{
    if kubectl -n kube-system get pods 2>/dev/null | grep -q etcd ; then
        return 0
    else
        return 1
    fi
}

#######################################
# Wait until Ceph status is healthy
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
waitCephHealthy()
{
    if ! isRook1; then
        return
    fi

    # log output of `ceph health` once, but only if a wait is needed
    local logged=0
    while true; do
        spinnerPodRunning "rook-ceph-system" "rook-ceph-operator"
        local rookOperatorPod=$(kubectl -n rook-ceph-system get pods | grep rook-ceph-operator | awk '{ print $1 }')
        local health=$(kubectl -n rook-ceph-system exec "$rookOperatorPod" -- /bin/sh -c 'ceph health 2>/dev/null || true')
        local status=$(echo $health | awk '{ print $1 }')
        if [ "$status" = "HEALTH_OK" ]; then
            return 0
        fi
        if [ "$logged" = "0" ] && [ -n "$health" ]; then
            logStep "Waiting for Rook/Ceph to report health OK, got: $status"
            logged=1
        fi
        sleep 2
    done
}

#######################################
# disable rook operator
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
disableRookCephOperator()
{
    if isRook1 || isRook08; then
        kubectl -n rook-ceph-system scale deployment rook-ceph-operator --replicas=0
    fi

}

#######################################
# enable rook operator
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
enableRookCephOperator()
{
    if isRook1 || isRook08; then
        kubectl -n rook-ceph-system scale deployment rook-ceph-operator --replicas=1
    fi
}

#######################################
# bail if Docker version is incompatible with K8s version
# Globals:
#   KUBERNETES_TARGET_VESION_MINOR
# Arguments:
#   None
# Returns:
#   None
#######################################
checkDockerK8sVersion()
{
    getDockerVersion
    if [ -z "$DOCKER_VERSION" ]; then
        return
    fi

    case "$KUBERNETES_TARGET_VERSION_MINOR" in 
        14|15)
            compareDockerVersions "$DOCKER_VERSION" 1.13.1
            if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
                bail "Minimum Docker version for Kubernetes $KUBERNETES_VERSION is 1.13.1."
            fi
            ;;
    esac
}

writeAKAExecStop()
{
    cat >/opt/replicated/shutdown.sh <<EOF
#!/bin/bash

KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl cordon \$(hostname | tr '[:upper:]' '[:lower:]')

EOF

    if isSingleNodePrimary; then
        cat >>/opt/replicated/shutdown.sh <<EOF
# only on primary of single-node clusters
KUBECONFIG=/etc/kubernetes/admin.conf /usr/local/bin/replicatedctl app stop || true
KUBECONFIG=/etc/kubernetes/admin.conf kubectl scale deploy replicated-shared-fs-snapshotter --replicas=0 || true

EOF
    fi

    if isCurrentNodePrimaryNode; then
        cat >>/opt/replicated/shutdown.sh <<EOF
DAEMON_SELECTOR=\$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get deploy replicated -ojsonpath='{.spec.template.spec.nodeSelector.kubernetes\.io\/hostname }')
if [ "\$DAEMON_SELECTOR" = "\$(hostname | tr '[:upper:]' '[:lower:]')" ]; then
    KUBECONFIG=/etc/kubernetes/admin.conf kubectl patch deploy replicated --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/nodeSelector", "value":{"node-role.kubernetes.io/master":""}}]'
fi

EOF
    fi


    cat >>/opt/replicated/shutdown.sh <<EOF
# delete local pods with PVCs
while read -r uid; do
        pod=\$(KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\\t"}{.metadata.uid}{"\\t"}{.metadata.namespace}{"\\n"}{end}' | grep \$uid )
        KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl delete pod \$(echo \$pod | awk '{ print \$1 }') --namespace=\$(echo \$pod | awk '{ print \$3 }') --wait=false
done < <(lsblk | grep '^rbd[0-9]' | awk '{ print \$7 }' | awk -F '/' '{ print \$6 }')

# delete local pods using the Ceph filesystem
while read -r uid; do
        pod=\$(KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\\t"}{.metadata.uid}{"\\t"}{.metadata.namespace}{"\\n"}{end}' | grep \$uid )
        KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl delete pod \$(echo \$pod | awk '{ print \$1 }') --namespace=\$(echo \$pod | awk '{ print \$3 }') --wait=false
done < <(cat /proc/mounts | grep ':6789:/' | awk '{ print \$2 }' | awk -F '/' '{ print \$6 }')

while \$(lsblk | grep -q '^rbd[0-9]'); do
        echo "Waiting for Ceph block devices to unmount"
        sleep 1
done

while \$(cat /proc/mounts | grep -q ':6789:/'); do
        echo "Waiting for Ceph shared filesystems to unmount"
        sleep 1
done

# remove ceph-operator and mds pods from this node so they can continue to service the cluster
thisHost=\$(hostname | tr '[:upper:]' '[:lower:]')
while read -r row; do
    podName=\$(echo \$row | awk '{ print \$1 }')
    ns=\$(echo \$row | awk '{ print \$2 }')

    if echo \$podName | grep -q "rook-ceph-operator"; then
        KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl -n \$ns delete pod \$podName
    fi
    if echo \$podName | grep -q "rook-ceph-mds-rook-shared-fs"; then
        KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl -n \$ns delete pod \$podName
    fi
done < <(KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\\t"}{.metadata.namespace}{"\\t"}{.spec.nodeName}{"\\n"}{end}' | grep -E "\${thisHost}\$")

EOF

    chmod u+x /opt/replicated/shutdown.sh
}

writeAKAExecStart()
{
    cat >/opt/replicated/start.sh <<EOF
#!/bin/bash

# wait for Kubernets API
primary=\$(cat /etc/kubernetes/kubelet.conf | grep server | awk '{ print \$2 }')
while [ "\$(curl --noproxy "*" -sk \$primary/healthz)" != "ok" ]; do
        sleep 1
done

KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl uncordon \$(hostname | tr '[:upper:]' '[:lower:]')
EOF

    chmod u+x /opt/replicated/start.sh
}

writeAKAService()
{
    cat >/etc/systemd/system/aka-reboot.service <<EOF
[Unit]
After=kubelet.service
After=docker.service

[Service]
ExecStart=/opt/replicated/start.sh
ExecStop=/opt/replicated/shutdown.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

installAKAService()
{
    writeAKAExecStop
    writeAKAExecStart
    writeAKAService
    systemctl daemon-reload
    systemctl enable aka-reboot.service
    systemctl start aka-reboot.service
}

LOAD_BALANCER_ADDRESS_CHANGED=0
LAST_LOAD_BALANCER_ADDRESS=
promptForLoadBalancerAddress() {
    local isK8sInstalled=
    local lastLoadBalancerAddress=

    lastLoadBalancerAddress="$LAST_LOAD_BALANCER_ADDRESS"
    if kubeadm config view >/dev/null 2>&1; then
        isK8sInstalled=1
        if [ -z "$lastLoadBalancerAddress" ]; then
            lastLoadBalancerAddress="$(kubeadm config view | grep 'controlPlaneEndpoint:' | sed 's/controlPlaneEndpoint: \|"//g')"
        fi
    fi
    if [ -n "$lastLoadBalancerAddress" ]; then
        splitHostPort "$lastLoadBalancerAddress"
        LAST_LOAD_BALANCER_ADDRESS="$HOST"
        if [ "$HOST" = "$lastLoadBalancerAddress" ]; then
            lastLoadBalancerAddress="$lastLoadBalancerAddress:6443"
        fi
    fi

    if [ -n "$LOAD_BALANCER_ADDRESS" ] && [ -n "$lastLoadBalancerAddress" ]; then
        splitHostPort "$LOAD_BALANCER_ADDRESS"
        if [ "$HOST" = "$LOAD_BALANCER_ADDRESS" ]; then
            LOAD_BALANCER_ADDRESS="$LOAD_BALANCER_ADDRESS:6443"
        fi
    fi

    if [ -z "$LOAD_BALANCER_ADDRESS" ] && [ -n "$lastLoadBalancerAddress" ]; then
        LOAD_BALANCER_ADDRESS="$lastLoadBalancerAddress"
    fi

    if [ -z "$LOAD_BALANCER_ADDRESS" ]; then
        printf "Please enter a load balancer address to route external and internal traffic to the API servers.\n"
        printf "In the absence of a load balancer address, all traffic will be routed to the first primary.\n"
        printf "Load balancer address: "
        prompt
        LOAD_BALANCER_ADDRESS="$PROMPT_RESULT"
        if [ -z "$LOAD_BALANCER_ADDRESS" ]; then
            LOAD_BALANCER_ADDRESS="$PRIVATE_ADDRESS"
            LOAD_BALANCER_PORT=6443
        fi
    fi

    if [ -z "$LOAD_BALANCER_PORT" ]; then
        splitHostPort "$LOAD_BALANCER_ADDRESS"
        LOAD_BALANCER_ADDRESS="$HOST"
        LOAD_BALANCER_PORT="$PORT"
    fi
    if [ -z "$LOAD_BALANCER_PORT" ]; then
        LOAD_BALANCER_PORT=6443
    fi

    if [ "$isK8sInstalled" = "1" ] && [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        if [ "$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT" != "$lastLoadBalancerAddress" ]; then
            LOAD_BALANCER_ADDRESS_CHANGED=1
        fi
    fi
}

promptForToken() {
    if [ -n "$KUBEADM_TOKEN" ]; then
        return
    fi

    printf "Please enter the kubernetes discovery token.\n"
    while true; do
        printf "Kubernetes join token: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBEADM_TOKEN="$PROMPT_RESULT"
            return
        fi
    done
}

promptForTokenCAHash() {
    if [ -n "$KUBEADM_TOKEN_CA_HASH" ]; then
        return
    fi
    if [ "$UNSAFE_SKIP_CA_VERIFICATION" = "1" ]; then
        return
    fi

    printf "Please enter the discovery token CA's hash.\n"
    while true; do
        printf "Kubernetes discovery token CA hash: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBEADM_TOKEN_CA_HASH="$PROMPT_RESULT"
            return
        fi
    done
}

kubernetesDiscoverPrivateIp()
{
    if [ -n "$PRIVATE_ADDRESS" ]; then
        return 0
    fi
    PRIVATE_ADDRESS=$(cat /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | grep advertise-address | awk -F'=' '{ print $2 }')
}

maybeSetTaintControlPlane()
{
    if [ "$TAINT_CONTROL_PLANE" = "1" ]; then
        return
    fi
    # is this a primary node
    if [ "$PRIMARY" != "1" ]; then
        return
    fi

    waitForNodes

    # do the other primary nodes have NoSchedule taints?
    if kubectl get nodes --selector=node-role.kubernetes.io/master -ojsonpath --template='{.items[*].spec.taints[?(@.key == "node-role.kubernetes.io/master")].effect}' | grep -q NoSchedule ; then
        TAINT_CONTROL_PLANE=1
    fi
}

maybeTaintControlPlaneNodeJoin()
{
    maybeSetTaintControlPlane
    if [ "$TAINT_CONTROL_PLANE" = "1" ]; then
        makeKubeadmJoinConfigV1Beta2
        kubeadm join phase control-plane-join mark-control-plane --config /opt/replicated/kubeadm.conf
    fi
}

function k8s_load_images() {
    local k8sVersion="$1"
    airgapLoadKubernetesCommonImages "$k8sVersion"
    if isCurrentNodePrimaryNode; then
        airgapLoadKubernetesControlImages "$k8sVersion"

        retag_control_images "$k8sVersion"

        # technically this is not just loading images but this will upgrade images in control plane
        # components which we cant do from the first primary
        patch_control_plane_images "$k8sVersion"
    fi
    retag_kubeproxy_image "$k8sVersion"
}

function k8s_pull_and_retag_control_images() {
    local k8sVersion="$1"

    case "$k8sVersion" in
        1.15.12)
            if [ "$AIRGAP" != "1" ]; then
                docker pull "{{ images.kube_apiserver_v11512.name }}"
                docker pull "{{ images.kube_controller_manager_v11512.name }}"
                docker pull "{{ images.kube_scheduler_v11512.name }}"
            fi
            retag_control_images "$k8sVersion"
            ;;
    esac
}

function k8s_pull_and_retag_kubeproxy_image() {
    local k8sVersion="$1"

    case "$k8sVersion" in
        1.15.12)
            if [ "$AIRGAP" != "1" ]; then
                docker pull "{{ images.kube_proxy_v11512.name }}"
            fi
            retag_kubeproxy_image "$k8sVersion"
            ;;
    esac
}

function retag_control_images() {
    local k8sVersion="$1"

    case "$k8sVersion" in
        1.15.12)
            docker tag "{{ images.kube_apiserver_v11512.name }}" replicated/kube-apiserver:v1.15.12
            docker tag "{{ images.kube_controller_manager_v11512.name }}" replicated/kube-controller-manager:v1.15.12
            docker tag "{{ images.kube_scheduler_v11512.name }}" replicated/kube-scheduler:v1.15.12
            ;;
    esac
}

function retag_kubeproxy_image() {
    local k8sVersion="$1"

    case "$k8sVersion" in
        1.15.12)
            docker tag "{{ images.kube_proxy_v11512.name }}" replicated/kube-proxy:v1.15.12
            ;;
    esac
}

function is_primary_node() {
    local nodeName="$1"
    kubectl get nodes --no-headers --show-labels "$nodeName" 2>/dev/null | grep -q 'node-role.kubernetes.io/master'
}

# if remote nodes are in the cluster and this is an airgap install, prompt the user to run the
# load-images task on all remotes before proceeding because remaining steps may cause pods to
# be scheduled on those nodes with new images.
function prompt_airgap_preload_images() {
    if [ "$AIRGAP" != "1" ]; then
        return 0
    fi

    if ! kubernetes_has_remotes; then
        return 0
    fi

    local k8sVersion="$1"
 
    while read -r node; do
        local nodeName=$(echo "$node" | awk '{ print $1 }')
        if [ "$nodeName" = "$(hostname)" ]; then
            continue
        fi
        if kubernetes_node_has_all_images "$k8sVersion" "$nodeName"; then
            continue
        fi
        printf "\nDownload the Replicated airgap bundle and run the following script on node ${GREEN}${nodeName}${NC} to load required images before proceeding:\n"
        printf "\n"
        printf "${GREEN}\tcat ./kubernetes-init.sh | sudo bash -s load-images kubernetes-version=${KUBERNETES_VERSION}${NC}"
        printf "\n"

        while true; do
            echo ""
            printf "Have images been loaded on node ${nodeName}? "
            if confirmY " "; then
                break
            fi
        done
    done <<< "$(kubectl get nodes --no-headers)"
}

function kubernetes_node_has_all_images() {
    local k8sVersion="$1"
    local nodeName="$2"

    while read -r image; do
        if ! kubernetes_node_has_image "$nodeName" "$image"; then
            printf "\n${YELLOW}Node $nodeName missing image $image${NC}\n"
            return 1
        fi
    done <<< "$(list_all_required_images "$k8sVersion" "$nodeName")"
}

function kubernetes_node_has_image() {
    local nodeName="$1"
    # docker.io/envoyproxy/envoy-alpine:v1.10.0 -> envoyproxy/envoy-alpine:v1.10.0
    local image=$(echo $2 | sed 's/^docker.io\///')

    while read -r nodeImage; do
        nodeImage=$(echo $nodeImage | sed 's/^docker.io\///')
        if [ "$nodeImage" = "$image" ]; then
            return 0
        fi
    done <<< "$(kubernetes_node_images "$nodeName")"

    return 1
}

# exit 0 if there are any remote primary or secondary nodes
function kubernetes_has_remotes() {
    if ! kubernetes_api_is_healthy; then
        # assume this is a new install
        return 1
    fi

    local count=$(kubectl get nodes --no-headers --selector="kubernetes.io/hostname!=$(hostname)" 2>/dev/null | wc -l)
    if [ "$count" -gt "0" ]; then
        return 0
    fi

    return 1
}

function kubernetes_api_is_healthy() {
    curl --noproxy "*" --fail --silent --insecure "https://$(kubernetes_api_address)/healthz" >/dev/null
}

function kubernetes_api_address() {
    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        echo "${LOAD_BALANCER_ADDRESS}:${LOAD_BALANCER_PORT}"
        return
    fi
    echo "${PRIVATE_ADDRESS}:6443"
}

function kubernetes_node_images() {
    local nodeName="$1"

    kubectl get node "$nodeName" -ojsonpath="{range .status.images[*]}{ range .names[*] }{ @ }{'\n'}{ end }{ end }"
}

function node_name() {
    echo "$(hostname | tr '[:upper:]' '[:lower:]')"
}

function label_node() {
    local nodeName="$1"
    local label="$2"
    if kubectl get nodes --show-labels --no-headers "$nodeName" | grep -q "$label" ; then
        return
    fi
    kubectl label nodes --overwrite "$nodeName" "$label"
}
