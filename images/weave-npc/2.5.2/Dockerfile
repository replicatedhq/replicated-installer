# https://github.com/weaveworks/weave/blob/v2.5.2/prog/weave-npc/Dockerfile.template

FROM weaveworks/weave-npc:2.5.2 AS base

FROM alpine:3.13

RUN apk add --update \
    iptables \
    ipset \
    ulogd \
  && rm -rf /var/cache/apk/* \
  && mknod /var/log/ulogd.pcap p

COPY --from=base /usr/bin/weave-npc /usr/bin/weave-npc
COPY --from=base /etc/ulogd.conf /etc/ulogd.conf

ENTRYPOINT ["/usr/bin/weave-npc"]
