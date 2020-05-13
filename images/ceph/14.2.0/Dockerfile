FROM ceph/ceph:v14.2.0-20190410

RUN yum install -y \
    nss \
    nss-softokn \
    nss-util \
    python3-pip \
    sqlite \
    sudo \
  && yum clean all \
  && rm -rf /var/cache/yum
