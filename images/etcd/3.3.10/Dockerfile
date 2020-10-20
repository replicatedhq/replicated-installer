# https://github.com/kubernetes/kubernetes/blob/v1.15.12/cluster/images/etcd/Dockerfile

FROM k8s.gcr.io/etcd-amd64:3.3.10 AS base

FROM busybox:1.31

EXPOSE 2379 2380 4001 7001

COPY --from=base /usr/local/bin/etcd* /usr/local/bin/etcdctl* /usr/local/bin/
COPY --from=base /usr/local/bin/migrate-if-needed.sh /usr/local/bin/migrate /usr/local/bin/
