SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

.PHONY: pull
pull:
	docker pull $(REPLICATED_HOSTPATH_PROVISIONER_CD1D272)

.PHONY: build
build:
	@echo nothing to do

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export IMAGE_NAME = $(REPLICATED_HOSTPATH_PROVISIONER_CD1D272)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	@echo nothing to do
