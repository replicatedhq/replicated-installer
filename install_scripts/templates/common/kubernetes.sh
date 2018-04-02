
#######################################
#
# kubernetes.sh
#
# require selinux.sh
#
#######################################

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

#######################################
# Print a "no proxy" message and exit 1
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
bailNoProxy() {
    bail "Kubernetes installs behind a proxy are not supported at this time"
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

    docker run -v /tmp:/out replicated/k8s-cni:v1.9.3
    tar zxfv /tmp/cni.tar.gz -C /opt/cni/bin
    mkdir -p /etc/cni/net.d
}


#######################################
# Install K8s components for OS
# Globals:
#   LSB_DIST
#   LSB_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
installKubernetesComponents() {
    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            export DEBIAN_FRONTEND=noninteractive
            installComponentsApt
            return
            ;;
        centos7|rhel7.*)
            # This needs to be run on Linux 3.x nodes for Rook
            modprobe rbd
            echo 'rbd' > /etc/modules-load.d/replicated.conf
            installComponentsYum
            return
            ;;
        *)
    esac

    # intentionally mixed spaces and tabs here -- tabs are stripped by "<<-'EOF'", spaces are kept in the output
    cat >&2 <<-'EOF'
      Either your platform is not easily detectable, is not supported by this
      installer script (yet - PRs welcome! [hack/install.sh]), or does not yet have
      a package for Docker.  Please visit the following URL for more detailed
      installation instructions:
        https://docs.docker.com/engine/installation/
EOF
    exit 1
}

#######################################
# Download Components Using Apt. At least works on Ubuntu16
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
installComponentsApt() {
    if commandExists "kubeadm"; then
        return
    fi

    logStep "Install kubernetes components"
    if [ "$AIRGAP" == "1" ]; then
        docker load < packages-kubernetes-ubuntu1604.tar
    fi

    docker run \
      -v $PWD:/out \
      "replicated/k8s-packages:ubuntu-1604-{{ kubernetes_version }}"

    pushd archives
        dpkg -i *.deb
    popd
    rm -rf archives
    systemctl enable kubelet && systemctl start kubelet

    logSuccess "Kubernetes components installed"
}

#######################################
# Unpack kubernetes images
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
airgapLoadKubernetesImages() {
    logStep "common images"

    docker load < k8s-images-common.tar
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-common:v1.9.3-20180222"

    # uh. its kind of insane that we have to do this. the linuxkit pkg
    # comes to us without tags, which seems super useless... we should build our own bundler maybe
    docker tag 35fdc6da5fd8 gcr.io/google_containers/kube-proxy-amd64:v1.9.3
    docker tag db76ee297b85 gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.7
    docker tag 5d049a8c4eec gcr.io/google_containers/k8s-dns-kube-dns-amd64:1.14.7
    docker tag 5feec37454f4 gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64:1.14.7
    docker tag 99e59f495ffa gcr.io/google_containers/pause-amd64:3.0
    docker tag 222ab9e78a83 weaveworks/weave-kube:2.2.0
    docker tag 765b48853ac0 weaveworks/weave-npc:2.2.0


    docker images | grep google_containers
    logSuccess "common images"


    logStep "control plane images"

    docker load < k8s-images-control.tar
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "replicated/k8s-images-control:v1.9.3-20180222"
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
    docker load < rook.tar
    docker load < replicated-operator.tar
    logSuccess "replicated addons"

}


#######################################
# Download Components Using Yum. At least works on Centos7
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
installComponentsYum() {
    if commandExists "kubeadm"; then
        return
    fi

    logStep "Install kubernetes components"

    if [ "$AIRGAP" == "1" ]; then
        docker load < packages-kubernetes-rhel7.tar
    fi

    # iptables stuff
    cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
    sysctl --system
    service docker restart

    must_disable_selinux

    docker run \
      -v $PWD:/out \
      "replicated/k8s-packages:rhel-7-{{ kubernetes_version }}"

    pushd archives
        yum install -y -q *.rpm
    popd
    rm -rf archives
    systemctl enable kubelet && systemctl start kubelet
    logSuccess "Kubernetes components downloaded"
}


#######################################
# Display a spinner until the node is ready, TODO timeout
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerNodeReady()
{
    logStep "Await node ready"
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(kubectl get nodes | grep NotReady)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    logSuccess "Master Node Ready!"
}

#######################################
# Spinner Replicated Ready,
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
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(kubectl get pods | grep replicated | grep -E "ContainerCreating|Pending")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
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
