# https://github.com/kubernetes/kubernetes/blob/v1.15.3/build/debian-base/Dockerfile.build
# https://github.com/kubernetes/kubernetes/blob/v1.15.3/build/debian-iptables/Dockerfile

FROM k8s.gcr.io/kube-proxy-amd64:v1.15.3

RUN clean-install \
    libcomerr2 \
    libidn11
