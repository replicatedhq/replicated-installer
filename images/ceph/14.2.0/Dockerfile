# https://github.com/ceph/ceph-container

FROM ceph/ceph:v14.2.0

RUN yum update -y \
  && yum install -y \
    bind-license \
  && yum clean all
