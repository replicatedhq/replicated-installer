ARG BASEIMAGE

FROM k8s.gcr.io/kube-proxy-amd64:v1.15.3 AS base

FROM $BASEIMAGE

COPY --from=base /usr/local/bin/kube-proxy /usr/local/bin/kube-proxy
