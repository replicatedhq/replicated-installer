# https://github.com/docker/distribution-library-image/blob/release/2.6/amd64/Dockerfile

FROM registry:2.6.2 AS base

FROM alpine:3.14

RUN apk add --update \
    ca-certificates \
    apache2-utils \
  && rm -rf /var/cache/apk/*

COPY --from=base /bin/registry /bin/registry
COPY --from=base /etc/docker/registry/config.yml /etc/docker/registry/config.yml

VOLUME ["/var/lib/registry"]
EXPOSE 5000

COPY --from=base /entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

CMD ["/etc/docker/registry/config.yml"]
