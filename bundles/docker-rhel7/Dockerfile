FROM centos:7
RUN mkdir -p /packages/archives
RUN yumdownloader --resolve --destdir=/packages/archives -y docker

FROM scratch
COPY --from=0 /packages /
