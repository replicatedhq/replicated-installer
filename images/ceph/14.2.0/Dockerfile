# https://github.com/ceph/ceph-container

FROM ceph/ceph:v14.2.0

RUN yum install -y \
    bind-license \
    \
    \
    binutils \
    curl \
    glib2 \
    libcurl \
    libldb \
    libwbclient \
    libxml2 \
    libxml2-python \
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
    sudo \
  && yum clean all
