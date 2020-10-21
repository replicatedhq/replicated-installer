# https://github.com/kubernetes/release/blob/e9c035ea20e43797b11b863d716b865c6f559390/images/build/debian-iptables/buster/Dockerfile

ARG BASEIMAGE

FROM k8s.gcr.io/kube-proxy-amd64:v1.15.12 AS base
FROM k8s.gcr.io/kube-proxy-amd64:v1.18.8 AS base-buster

FROM $BASEIMAGE

# Install iptables and ebtables packages from buster-backports
ARG IPTABLES_VERSION=1.8.5
RUN echo deb http://deb.debian.org/debian buster-backports main >> /etc/apt/sources.list \
    && apt-get update \
    && apt-get -t buster-backports -y --no-install-recommends install \
        iptables=${IPTABLES_VERSION}* \
        ebtables

# Install other dependencies and then clean up apt caches
RUN clean-install \
    conntrack \
    ipset \
    kmod \
    netbase

# Install iptables wrapper scripts to detect the correct iptables mode
# the first time any of them is run
COPY --from=base-buster /usr/sbin/iptables-wrapper /usr/sbin/iptables-wrapper

RUN update-alternatives \
	--install /usr/sbin/iptables iptables /usr/sbin/iptables-wrapper 100 \
	--slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-wrapper \
	--slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-wrapper
RUN update-alternatives \
	--install /usr/sbin/ip6tables ip6tables /usr/sbin/iptables-wrapper 100 \
	--slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/iptables-wrapper \
	--slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/iptables-wrapper

COPY --from=base /usr/local/bin/kube-proxy /usr/local/bin/kube-proxy
