# https://github.com/rook/rook/blob/v1.0.3/images/ceph/Dockerfile

FROM rook/ceph:v1.0.3 AS base

FROM ceph/ceph:v14.2.1

RUN yum install -y \
    bind-license \
    \
    \
    curl \
    glib2 \
    glibc \
    glibc-common \
    libcurl \
    libldb \
    libwbclient \
    nettle \
    nss \
    nss-sysinit \
    nss-tools \
    openldap \
    openssl \
    openssl-libs \
    perl \
    perl-libs \
    perl-macros \
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

COPY --from=base /tini /tini

COPY --from=base /usr/local/bin/rook /usr/local/bin/rookflex /usr/local/bin/toolbox.sh /usr/local/bin/
COPY --from=base /etc/ceph-csi /etc/ceph-csi

ENTRYPOINT ["/tini", "--", "/usr/local/bin/rook"]
CMD [""]
