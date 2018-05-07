FROM ubuntu:16.04
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get -y install curl apt-transport-https
RUN mkdir -p /packages
RUN  curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
COPY ./kubernetes.list /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update
RUN apt-get install -d -y kubeadm=1.9.3-00 kubelet=1.9.3-00 kubectl=1.9.3-00 kubernetes-cni -oDebug::NoLocking=1 -o=dir::cache=/packages/


FROM busybox:latest
COPY --from=0 /packages /packages
CMD cp -r /packages/* /out/

