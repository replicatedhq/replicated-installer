FROM ceph/ceph:v14.2.2-20191210

RUN yum install -y \
    nss \
    nss-softokn \
    nss-util \
    python3-pip \
    sqlite \
    sudo \
  && yum clean all \
  && rm -rf /var/cache/yum
