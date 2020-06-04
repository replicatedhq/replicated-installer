# https://github.com/kubernetes/dns/blob/1.15.13/Dockerfile.node-cache

FROM k8s.gcr.io/k8s-dns-node-cache:1.15.13 AS base

FROM debian:buster-slim

# Use --no-install-recommends to not install nftables and work around https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=956655
# Use iptables-legacy only until https://bugzilla.netfilter.org/show_bug.cgi?id=1422 is resolved
# once fixed we will switch to k8s.gcr.io/debian-iptables-$(ARCH) to choose iptables-legacy or iptables-nft at run time
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 \
    iptables \
  && update-alternatives --set iptables /usr/sbin/iptables-legacy \
  && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy \
  && rm -rf /var/lib/apt/lists/*

COPY --from=base /node-cache /node-cache

EXPOSE 53 53/udp
EXPOSE 53 53/tcp

ENTRYPOINT ["/node-cache"]
