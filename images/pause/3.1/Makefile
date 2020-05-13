SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

.PHONY: pull
pull:
	docker pull $(PAUSE_31)

.PHONY: build
build:
	# kubeadm config dictates that all images must be in the same repo
	docker pull k8s.gcr.io/pause:3.1
	docker tag k8s.gcr.io/pause:3.1 $(PAUSE_31)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export IMAGE_NAME = $(PAUSE_31)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(PAUSE_31)
