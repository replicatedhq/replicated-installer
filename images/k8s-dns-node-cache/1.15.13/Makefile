SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(K8S_DNS_NODE_CACHE_11513_20200604)
	docker tag $(K8S_DNS_NODE_CACHE_11513_20200604) $(K8S_DNS_NODE_CACHE_11513)

.PHONY: build
build:
	docker build --pull -t $(K8S_DNS_NODE_CACHE_11513)-$(DATE) .
	docker tag $(K8S_DNS_NODE_CACHE_11513)-$(DATE) $(K8S_DNS_NODE_CACHE_11513)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(K8S_DNS_NODE_CACHE_11513)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(K8S_DNS_NODE_CACHE_11513)-$(DATE)
