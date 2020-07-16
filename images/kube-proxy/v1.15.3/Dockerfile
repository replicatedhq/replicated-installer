# https://github.com/kubernetes/kubernetes/blob/v1.15.3/build/debian-iptables/Dockerfile

ARG BASEIMAGE

FROM k8s.gcr.io/kube-proxy-amd64:v1.15.3 AS base

FROM $BASEIMAGE

RUN clean-install \
    conntrack \
    ebtables \
    ipset \
    iptables \
    kmod \
    netbase

COPY --from=base /usr/local/bin/kube-proxy /usr/local/bin/kube-proxy
