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
UBUNTU_1604_K8S_15=ubuntu-1604-v1.15.0-20190627

UBUNTU_1804_K8S_13=ubuntu-1804-v1.13.5-20190411
UBUNTU_1804_K8S_15=ubuntu-1604-v1.15.0-20190627

RHEL7_K8S_9=rhel7-v1.9.3-20180806
RHEL7_K8S_10=rhel7-v1.10.6-20180806
RHEL7_K8S_11=rhel7-v1.11.5-20181204
RHEL7_K8S_12=rhel7-v1.12.3-20181211
RHEL7_K8S_13=rhel7-v1.13.5-20190411
RHEL7_K8S_15=rhel7-v1.15.0-20190627

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
            # 1.15.0
            k8sPatch="0"
    esac
    KUBERNETES_VERSION="$k8sMajor.$k8sMinor.$k8sPatch"
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
        ubuntu16.04|ubuntu18.04|rhel7.4|rhel7.5|rhel7.6|centos7.4|centos7.5|centos7.6)
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

    if [ "$AIRGAP" = "1" ]; then
        docker load < k8s-cni.tar
    fi

    docker run -v /tmp:/out quay.io/replicated/k8s-cni:0.6.0
    tar zxfv /tmp/cni.tar.gz -C /opt/cni/bin
    mkdir -p /etc/cni/net.d
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
                1.15.0)
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
                1.15.0)
                    echo "$UBUNTU_1804_K8S_15"
                    ;;
                *)
                    bail "Unsupported Kubernetes version $k8sVersion"
                    ;;
            esac
            ;;
        centos7.4|centos7.5|centos7.6|rhel7.4|rhel7.5|rhel7.6)
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
                1.15.0)
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

        centos7.4|centos7.5|centos7.6|rhel7.4|rhel7.5|rhel7.6)
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

    modprobe nf_conntrack_ipv4
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
        *)
            bail "Unsupported Kubernetes version $k8sVersion"
            ;;
    esac

    logSuccess "common images"
}

airgapLoadKubernetesCommonImages193() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "quay.io/replicated/k8s-images-common:v1.9.3-20180809"

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
        "quay.io/replicated/k8s-images-common:v1.10.6-20180809"

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
        "quay.io/replicated/k8s-images-common:v1.11.5-20181207"

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
        docker tag 376cb7e8748c quay.io/replicated/replicated-hostpath-provisioner:cd1d272
    )
}

# only the images needed for kubeadm to upgrade from 1.11 to 1.13
airgapLoadKubernetesCommonImages1123() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "quay.io/replicated/k8s-images-common:v1.12.3-20181207"

    docker tag ab97fa69b926 k8s.gcr.io/kube-proxy:v1.12.3
    docker tag 367cdc8433a4 k8s.gcr.io/coredns:1.2.2
}

airgapLoadKubernetesCommonImages1135() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "quay.io/replicated/k8s-images-common:v1.13.5-20190507"

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
        docker tag 376cb7e8748c quay.io/replicated/replicated-hostpath-provisioner:cd1d272
    )
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
        *)
            bail "Unsupported Kubernetes version $k8sVersion"
            ;;
    esac

    logSuccess "control plane images"
}

airgapLoadReplicatedAddonImagesWorker() {
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
    logSuccess "replicated addons"
}

airgapLoadKubernetesControlImages193() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "quay.io/replicated/k8s-images-control:v1.9.3-20180809"

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
        "quay.io/replicated/k8s-images-control:v1.10.6-20180809"

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
        "quay.io/replicated/k8s-images-control:v1.11.5-20181204"

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
        "quay.io/replicated/k8s-images-control:v1.12.3-20181210"

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
        "quay.io/replicated/k8s-images-control:v1.13.5-20190411"

    (
        set -x
        docker tag 90332c1b9a4b k8s.gcr.io/kube-apiserver:v1.13.5
        docker tag b6b315f4f34a k8s.gcr.io/kube-controller-manager:v1.13.5
        docker tag c629ac1dae38 k8s.gcr.io/kube-scheduler:v1.13.5
        docker tag 3cab8e1b9802 k8s.gcr.io/etcd:3.2.24
    )
}

airgapPushReplicatedImagesToRegistry() {
    logStep "Pushing images to registry at $1"

    dockerGetRepoTagFromTar replicated.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

    dockerGetRepoTagFromTar replicated-ui.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

    dockerGetRepoTagFromTar replicated-operator.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

    dockerGetRepoTagFromTar replicated-sidecar-controller.tar
    dockerRetagAndPushImageToRegistry "$REPO_TAG" "$1"

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
      "quay.io/replicated/k8s-packages:${pkgTag}"
}

#######################################
# Gets node name from kubectl ignoring errors
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   master
#######################################
k8sMasterNodeNames() {
    set +e
    _master="$(kubectl get nodes --show-labels 2>/dev/null | grep 'node-role.kubernetes.io/master' | awk '{ print $1 }')"
    until [ -n "$_master" ]; do
        _master="$(kubectl get nodes --show-labels 2>/dev/null | grep 'node-role.kubernetes.io/master' | awk '{ print $1 }')"
    done
    set -e
    printf "$_master"
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
    kubectl get namespaces | grep "$1" > /dev/null
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
        if [ "$_exit" -eq "0" ] && ! echo "$nodes" | grep -q "NotReady"; then
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
# Display a spinner until the master node is ready
# Globals:
#   AIRGAP
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerMasterNodeReady()
{
    logStep "Await node ready"
    spinnerNodesReady
    logSuccess "Master Node Ready!"
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
labelMasterNodeDeprecated()
{
    semverCompare "$REPLICATED_VERSION" "2.26.0"
    if [ "$SEMVER_COMPARE_RESULT" -ge 0 ]; then
        return
    fi
    if kubectl get nodes --show-labels | grep -q "$DAEMON_NODE_KEY" ; then
        return
    fi
    kubectl label nodes --overwrite "$(k8sMasterNodeNames)" "$DAEMON_NODE_KEY"=
}

#######################################
# Check if the node is a master
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if master node, else 1
#######################################
isMasterNode()
{
    if [ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
        return 0
    else
        return 1
    fi
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

    WEAVE_TAG=2.5.1
    DOCKER_BRIDGE=docker0

    # if we never unpacked/pulled the weave image, its unlikely we need to do any of this
    if ! dockerImageExists "weaveworks/weaveexec:${WEAVE_TAG}"; then
        return
    fi

    DOCKER_BRIDGE_IP=$(docker run --rm --pid host --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=/usr/bin/weaveutil weaveworks/weaveexec:$WEAVE_TAG bridge-ip $DOCKER_BRIDGE)


    for NETDEV in $BRIDGE $DATAPATH ; do
        if [ -d /sys/class/net/$NETDEV ] ; then
            if [ -d /sys/class/net/$NETDEV/bridge ] ; then
                ip link del $NETDEV
            else
                docker run --rm --pid host --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=/usr/bin/weaveutil weaveworks/weaveexec:$WEAVE_TAG delete-datapath $NETDEV
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
    if [ "$MASTER" -eq "1" ]; then
        cat << EOF >> /opt/replicated/kubeadm.conf
controlPlane: {}
EOF
    fi
}

exportKubeconfig() {
    chmod 444 /etc/kubernetes/admin.conf
    echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /etc/profile
    echo "source <(kubectl completion bash)" >> /etc/profile
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

    # prefer to configure using /etc/docker/daemon.json since that does not require a docker restart
    # but don't attempt to edit json if that file already exists.
    if [ ! -f "/etc/docker/daemon.json" ]; then
        cat <<EOF >/etc/docker/daemon.json
{
    "insecure-registries": ["$1"]
}
EOF
        systemctl kill -s HUP --kill-who=main docker.service
        ADDED_INSECURE_REGISTRY=1
        return
    fi
    mkdir -p /etc/systemd/system/docker.service.d
    local execStart=$(cat /etc/systemd/system/multi-user.target.wants/docker.service | sed -n '/ExecStart/,$p' | sed -E '/[^\\]$/q')

    cat <<EOF > /etc/systemd/system/docker.service.d/replicated-registry.conf
[Service]
ExecStart=
$execStart --insecure-registry $1
EOF
    systemctl daemon-reload
    systemctl restart docker
    spinnerNodesReady

    ADDED_INSECURE_REGISTRY=1
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
untaintMaster() {
    logStep "remove NoSchedule taint from master node"
    kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- || \
        echo "Taint not found or already removed. The above error can be ignored."
    logSuccess "master taint removed"
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
