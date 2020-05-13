SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

.PHONY: pull
pull:
	docker pull $(CEPH_1422)

.PHONY: build
build:
	docker build --pull -t $(CEPH_1422) .

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 6000
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export IMAGE_NAME = $(CEPH_1422)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(CEPH_1422)
