SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(KUBE_APISERVER_V1153)

.PHONY: build
build:
	docker build --pull -t $(KUBE_APISERVER_V1153)-$(DATE) .

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export IMAGE_NAME = $(KUBE_APISERVER_V1153)-$(DATE)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(KUBE_APISERVER_V1153)-$(DATE)
	docker tag $(KUBE_APISERVER_V1153)-$(DATE) $(KUBE_APISERVER_V1153)
	docker push $(KUBE_APISERVER_V1153)
