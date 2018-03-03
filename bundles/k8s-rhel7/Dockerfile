FROM centos:7
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives
RUN yumdownloader --resolve --destdir=/packages/archives -y kubelet kubeadm kubectl kubernetes-cni

FROM busybox:latest
COPY --from=0 /packages /packages
CMD cp -r /packages/* /out/
