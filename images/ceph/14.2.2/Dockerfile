# https://github.com/ceph/ceph-container

FROM ceph/ceph:v14.2.2

RUN yum install -y \
    bind-license \
    \
    \
    curl \
    libcurl \
    libwbclient \
    openssl \
    openssl-libs \
    python \
    python-devel \
    python-libs \
    python-rtslib \
    python3 \
    samba-client-libs \
    samba-common \
    samba-common-libs \
  && yum clean all
