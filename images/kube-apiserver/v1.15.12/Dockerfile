ARG BASEIMAGE

FROM k8s.gcr.io/kube-apiserver-amd64:v1.15.12 AS base

FROM $BASEIMAGE

COPY --from=base /usr/local/bin/kube-apiserver /usr/local/bin/kube-apiserver
