SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

.PHONY: all
all: build scan push

.PHONY: build
build:
	docker build --pull -t $(ETCD_3310) .

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export IMAGE_NAME = $(ETCD_3310)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(ETCD_3310)
