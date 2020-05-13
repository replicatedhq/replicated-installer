SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(ENVOY_V1100_20200512)
	docker tag $(ENVOY_V1100_20200512) $(ENVOY_V1100)

.PHONY: build
build:
	docker build --pull -t $(ENVOY_V1100)-$(DATE) .
	docker tag $(ENVOY_V1100)-$(DATE) $(ENVOY_V1100)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(ENVOY_V1100)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(ENVOY_V1100)-$(DATE)
