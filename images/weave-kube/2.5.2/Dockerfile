# https://github.com/weaveworks/weave/blob/v2.5.2/prog/weaver/Dockerfile.template
# https://github.com/weaveworks/weave/blob/v2.5.2/prog/weave-kube/Dockerfile.template

FROM weaveworks/weave-kube:2.5.2 AS base

FROM alpine:3.12

RUN apk add --update \
    curl \
    ethtool \
    iptables \
    ipset \
    iproute2 \
    util-linux \
    conntrack-tools \
    bind-tools \
    ca-certificates \
  && rm -rf /var/cache/apk/*

COPY --from=base /home/weave /home/weave
COPY --from=base /usr/bin/weaveutil /usr/bin/weaveutil
COPY --from=base /weavedb /weavedb

ENTRYPOINT ["/home/weave/launch.sh"]
WORKDIR /home/weave
