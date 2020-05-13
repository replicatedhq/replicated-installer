SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(CEPH_1420_20200512)
	docker tag $(CEPH_1420_20200512) $(CEPH_1420)

.PHONY: build
build:
	docker build --pull -t $(CEPH_1420)-$(DATE) .
	docker tag $(CEPH_1420)-$(DATE) $(CEPH_1420)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 6000
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(CEPH_1420)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(CEPH_1420)-$(DATE)
