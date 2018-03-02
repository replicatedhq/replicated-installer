FROM ubuntu:16.04
RUN apt-get update
RUN apt-get -y install wget curl apt-transport-https
RUN mkdir -p /packages
RUN wget -O /packages/cni.tar.gz https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz

FROM busybox:latest
COPY --from=0 /packages /packages
CMD cp -r /packages/* /out/
