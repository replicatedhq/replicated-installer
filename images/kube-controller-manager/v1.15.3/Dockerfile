ARG BASEIMAGE

FROM k8s.gcr.io/kube-controller-manager-amd64:v1.15.3 AS base

FROM $BASEIMAGE

COPY --from=base /usr/local/bin/kube-controller-manager /usr/local/bin/kube-controller-manager
