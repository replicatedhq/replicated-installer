ARG BASEIMAGE

FROM k8s.gcr.io/kube-scheduler-amd64:v1.15.3 AS base

FROM $BASEIMAGE

COPY --from=base /usr/local/bin/kube-scheduler /usr/local/bin/kube-scheduler
