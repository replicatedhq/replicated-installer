SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: all
all: build scan push

.PHONY: build
build:
	docker build --pull -t $(KUBE_SCHEDULER_V1153)-$(DATE) .

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export IMAGE_NAME = $(KUBE_SCHEDULER_V1153)-$(DATE)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(KUBE_SCHEDULER_V1153)-$(DATE)
	docker tag $(KUBE_SCHEDULER_V1153)-$(DATE) $(KUBE_SCHEDULER_V1153)
	docker push $(KUBE_SCHEDULER_V1153)
