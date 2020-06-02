SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(ETCD_347_20200602)
	docker tag $(ETCD_347_20200602) $(ETCD_347)

.PHONY: build
build:
	docker build --pull -t $(ETCD_347)-$(DATE) .
	docker tag $(ETCD_347)-$(DATE) $(ETCD_347)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(ETCD_347)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(ETCD_347)-$(DATE)
