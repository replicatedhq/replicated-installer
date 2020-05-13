SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(REGISTRY_262_20200512)
	docker tag $(REGISTRY_262_20200512) $(REGISTRY_262)

.PHONY: build
build:
	docker build --pull -t $(REGISTRY_262)-$(DATE) .
	docker tag $(REGISTRY_262)-$(DATE) $(REGISTRY_262)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(REGISTRY_262)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(REGISTRY_262)-$(DATE)
