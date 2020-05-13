SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

.PHONY: all
all: build scan push

.PHONY: build
build:
	docker build --pull -t $(ROOK_CEPH_106) .

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 1200
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export IMAGE_NAME = $(ROOK_CEPH_106)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(ROOK_CEPH_106)
