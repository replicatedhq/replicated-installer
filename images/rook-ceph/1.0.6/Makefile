SHELL := /bin/bash

include ../../common.mk

ID := ROOK_CEPH_106
IMAGE := replicated/rook-ceph:v1.0.6
VERSIONED := $(shell cat ../../../Manifest | grep $(ID) | awk '{print $$2}')
DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(VERSIONED)
	docker tag $(VERSIONED) $(IMAGE)

.PHONY: build
build:
	docker build --no-cache --pull -t $(IMAGE)-$(DATE) .
	docker tag $(IMAGE)-$(DATE) $(IMAGE)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 6000
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(IMAGE)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(IMAGE)-$(DATE)
