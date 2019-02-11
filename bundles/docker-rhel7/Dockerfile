FROM centos:7

RUN yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
RUN mkdir -p /packages/archives
RUN yumdownloader --resolve --destdir=/packages/archives -y docker-ce-18.06.2.ce-3.el7

FROM scratch
COPY --from=0 /packages /
