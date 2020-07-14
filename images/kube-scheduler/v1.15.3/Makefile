SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(KUBE_SCHEDULER_V1153)

.PHONY: build
build: export BASEIMAGE = $(KUBE_BASE_V1153_20200713)
build:
	docker build --pull -t $(KUBE_SCHEDULER_V1153)-$(DATE) --build-arg BASEIMAGE .
	docker tag $(KUBE_SCHEDULER_V1153)-$(DATE) $(KUBE_SCHEDULER_V1153)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(KUBE_SCHEDULER_V1153)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(KUBE_SCHEDULER_V1153)-$(DATE)
	docker push $(KUBE_SCHEDULER_V1153)
