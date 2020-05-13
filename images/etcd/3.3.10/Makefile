SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(ETCD_3310_20200512)
	docker tag $(ETCD_3310_20200512) $(ETCD_3310)

.PHONY: build
build:
	docker build --pull -t $(ETCD_3310)-$(DATE) .
	docker tag $(ETCD_3310)-$(DATE) $(ETCD_3310)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(ETCD_3310)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(ETCD_3310)-$(DATE)
