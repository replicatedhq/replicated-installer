SHELL := /bin/bash

include ../../common.mk

IMAGE := k8s.gcr.io/coredns:1.3.1

.PHONY: pull
pull:
	docker pull $(IMAGE)

.PHONY: build
build:
	@echo nothing to do

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export IMAGE_NAME = $(IMAGE)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	@echo nothing to do
