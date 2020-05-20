# https://github.com/kubernetes/kubernetes/blob/v1.15.3/build/debian-base/Dockerfile.build

FROM k8s.gcr.io/kube-apiserver-amd64:v1.15.3

RUN clean-install \
    libcomerr2 \
    libidn11 \
    libapt-pkg5.0
