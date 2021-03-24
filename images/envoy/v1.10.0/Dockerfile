# https://github.com/envoyproxy/envoy/blob/v1.10.0/ci/Dockerfile-envoy-alpine
# https://hub.docker.com/r/frolvlad/alpine-glibc/tags

FROM envoyproxy/envoy-alpine:v1.10.0 AS base

FROM frolvlad/alpine-glibc:alpine-3.13

RUN apk add --no-cache --upgrade \
	\
	\
	libcrypto1.1 \
	libssl1.1 \
	musl \
	musl-utils

RUN mkdir -p /etc/envoy

COPY --from=base /usr/local/bin/envoy /usr/local/bin/envoy
COPY --from=base /etc/envoy/envoy.yaml /etc/envoy/envoy.yaml

EXPOSE 10000

COPY --from=base /docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["envoy", "-c", "/etc/envoy/envoy.yaml"]
