SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(ROOK_CEPH_103_20200512)
	docker tag $(ROOK_CEPH_103_20200512) $(ROOK_CEPH_103)

.PHONY: build
build:
	docker build --pull -t $(ROOK_CEPH_103)-$(DATE) .
	docker tag $(ROOK_CEPH_103)-$(DATE) $(ROOK_CEPH_103)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 6000
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(ROOK_CEPH_103)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(ROOK_CEPH_103)-$(DATE)
