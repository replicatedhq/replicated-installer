
UBUNTU_1604_K8S_9=ubuntu-1604-v1.9.3-20180416
UBUNTU_1604_K8S_10=ubuntu-1604-v1.10.5-20180709
UBUNTU_1604_K8S_11=ubuntu-1604-v1.11.0-20180709

RHEL_74_K8S_9=rhel-74-v1.9.3-20180712
RHEL_74_K8S_10=rhel-74-v1.10.5-20180711
RHEL_74_K8S_11=rhel-74-v1.11.0-20180711

#######################################
#
# kubernetes.sh
#
# require selinux.sh
#
#######################################

DAEMON_NODE_KEY=replicated.com/daemon

command_exists() {
	command -v "$@" > /dev/null 2>&1
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
        ubuntu16.04|rhel7.4|centos7.4)
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

    # 0.6.0 is the latest as of k8s 1.11.0
    docker run -v /tmp:/out quay.io/replicated/k8s-cni:v1.9.3
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
                1.10.5)
                    echo "$UBUNTU_1604_K8S_10"
                    ;;
                1.11.0)
                    echo "$UBUNTU_1604_K8S_11"
                    ;;
                *)
                    bail "Unsupported Kubernetes version $k8sVersion"
                    ;;
            esac
            ;;
        centos7.4|rhel7.*)
            case "$k8sVersion" in
                1.9.3)
                    echo "$RHEL_74_K8S_9"
                    ;;
                1.10.5)
                    echo "$RHEL_74_K8S_10"
                    ;;
                1.11.0)
                    echo "$RHEL_74_K8S_11"
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
# Install K8s components for OS
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

    if commandExists "kubeadm"; then
        return
    fi

    logStep "Install kubernetes components"

    must_disable_selinux

    prepareK8sPackageArchives $k8sVersion

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i archives/*.deb
            ;;

        centos7.4|rhel7.4)
            # This needs to be run on Linux 3.x nodes for Rook
            modprobe rbd
            echo 'rbd' > /etc/modules-load.d/replicated.conf

            # tabs in heredoc stripped
            cat <<-EOF >  /etc/sysctl.d/k8s.conf
			net.bridge.bridge-nf-call-ip6tables = 1
			net.bridge.bridge-nf-call-iptables = 1
			EOF

            sysctl --system
            service docker restart

            rpm --upgrade --force archives/*.rpm
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
# Unpack kubernetes images
# Globals:
#   None
# Arguments:
#   k8sVersion - e.g. 1.9.3
# Returns:
#   None
#######################################
airgapLoadKubernetesCommonImages() {
    logStep "common images"

    k8sVersion=$1

    docker load < k8s-images-common.tar
    case "$k8sVersion" in
        1.9.3)
            airgapLoadKubernetesCommonImages193
            ;;
        1.10.5)
            bail "Unsupported Kubernetes version v$k8sVersion" # TODO
            ;;
        1.11.0)
            bail "Unsupported Kubernetes version v$k8sVersion" # TODO
            ;;
        *)
            bail "Unsupported Kubernetes version $k8sVersion"
            ;;
    esac
}

airgapLoadKubernetesCommonImages193() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "quay.io/replicated/k8s-images-common:v1.9.3-20180523"

    # uh. its kind of insane that we have to do this. the linuxkit pkg
    # comes to us without tags, which seems super useless... we should build our own bundler maybe
    docker tag 35fdc6da5fd8 gcr.io/google_containers/kube-proxy-amd64:v1.9.3
    docker tag db76ee297b85 gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.7
    docker tag 5d049a8c4eec gcr.io/google_containers/k8s-dns-kube-dns-amd64:1.14.7
    docker tag 5feec37454f4 gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64:1.14.7
    docker tag 99e59f495ffa gcr.io/google_containers/pause-amd64:3.0
    docker tag 222ab9e78a83 weaveworks/weave-kube:2.2.0
    docker tag 765b48853ac0 weaveworks/weave-npc:2.2.0
    docker tag 09747e7cdd74 weaveworks/weaveexec:2.2.0
    docker tag d1fd7d86a825 registry:2
    docker tag 6521ac58ca80 envoyproxy/envoy-alpine:v1.6.0
    docker tag 6a9ec4bcb60e gcr.io/heptio-images/contour:v0.5.0

    docker load < rook.tar

    docker images | grep google_containers
    logSuccess "common images"
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
    logStep "control plane images"

    k8sVersion=$1

    docker load < k8s-images-control.tar
    case "$k8sVersion" in
        v1.9.3)
            airgapLoadKubernetesControlImages193
            ;;
        v1.10.5)
            bail "Unsupported Kubernetes version v$k8sVersion" # TODO
            ;;
        v1.11.0)
            bail "Unsupported Kubernetes version v$k8sVersion" # TODO
            ;;
        *)
            bail "Unsupported Kubernetes version $k8sVersion"
            ;;
    esac
}

airgapLoadKubernetesControlImages193() {
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "quay.io/replicated/k8s-images-control:v1.9.3-20180222"
    # uh. its kind of insane that we have to do this. the linuxkit pkg
    # comes to us without tags, which seems super useless... we should build our own bundler maybe
    docker tag 83dbda6ee810 gcr.io/google_containers/kube-controller-manager-amd64:v1.9.3
    docker tag 360d55f91cbf gcr.io/google_containers/kube-apiserver-amd64:v1.9.3
    docker tag d3534b539b76 gcr.io/google_containers/kube-scheduler-amd64:v1.9.3
    docker tag 59d36f27cceb gcr.io/google_containers/etcd-amd64:3.1.11


    docker images | grep google_containers
    logSuccess "control plane images"

    logStep "replicated addons"
    docker load < replicated-sidecar-controller.tar
    docker load < replicated-operator.tar
    logSuccess "replicated addons"

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
    local delay=0.75
    local spinstr='|/-\'
    while ! $(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes 2>/dev/null >/dev/null) || [ "$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes | grep NotReady)" ]; do
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
#   k8sVersion - e.g. 1.10.5
# Returns:
#   None
#######################################
spinnerNodeVersion()
{
    node=$1
    k8sVersion=$2

    local delay=0.75
    local spinstr='|/-\'
    while ! $(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes 2>/dev/null >/dev/null) || [ "$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get node $node | sed '1d' | awk '{ print $5 }')" != "v$k8sVersion" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}


#######################################
# Display a spinner until the master node is ready and labels master if airgap
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

    if [ "$AIRGAP" = "1" ]; then
        node_name=$(kubectl get nodes -o=jsonpath='{.items[0].metadata.name}')
        kubectl label nodes "$node_name" "$DAEMON_NODE_KEY"=
    fi

    printf "    \b\b\b\b"
    logSuccess "Master Node Ready!"
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
    while [ ! $(kubectl -n "$namespace" get pods 2> /dev/null | grep "^$podPrefix" | awk '{ print $3}' | grep '^Running$' ) ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

#######################################
# Spinner Replicated Ready
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerReplicatedReady()
{
    logStep "Await replicated ready"
    spinnerPodRunning default replicated
    logSuccess "Replicated Ready!"
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
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(kubectl -n rook-system get pods | grep rook-operator | grep -E "ContainerCreating|Pending")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    logSuccess "Rook Ready!"
}

#######################################
# Spinner kube-system ready
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerKubeSystemReady()
{
    logStep "Await kube-system services ready"
    spinnerPodRunning kube-system weave-net
    spinnerPodRunning kube-system kube-dns
    spinnerPodRunning kube-system kube-proxy
    logStep "Kube system services ready"
}

weave_reset()
{
    BRIDGE=weave
    DATAPATH=datapath
    CONTAINER_IFNAME=ethwe

    WEAVE_TAG=2.2.0
    DOCKER_BRIDGE=docker0
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

k8s_reset() {
    if commandExists "kubectl" && [ -f "/opt/replicated/kubeadm.conf" ]; then
        set +e
        nodes=$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes --output=go-template --template="{{ '{{' }}range .items{{ '}}{{' }}.metadata.name{{ '}}' }} {{ '{{' }}end{{ '}}' }}")
        for node in $nodes; do
            KUBECONFIG=/etc/kubernetes/admin.conf kubectl drain "$node" --delete-local-data --force --ignore-daemonsets
            KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete node "$node"
        done
        set -e
    fi

    if commandExists "kubeadm"; then
        kubeadm reset
    fi

    weave_reset

    rm -rf /opt/replicated
    rm -rf /opt/cni
    rm -rf /etc/kubernetes
    rm -rf /var/lib/replicated
    rm -rf /var/lib/etcd
    rm -f /usr/bin/kubeadm /usr/bin/kubelet /usr/bin/kubectl
}
