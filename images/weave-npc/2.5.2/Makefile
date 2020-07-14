SHELL := /bin/bash

include ../../common.mk
include ../../manifest.mk

DATE := $(shell date '+%Y%m%d')

.PHONY: pull
pull:
	docker pull $(WEAVE_NPC_252_20200713)
	docker tag $(WEAVE_NPC_252_20200713) $(WEAVE_NPC_252)

.PHONY: build
build:
	docker build --pull -t $(WEAVE_NPC_252)-$(DATE) .
	docker tag $(WEAVE_NPC_252)-$(DATE) $(WEAVE_NPC_252)

.PHONY: scan
scan: export POLICY_FAILURE = true
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(WEAVE_NPC_252)
scan:
	bash ../../scripts/inline_scan.sh

.PHONY: push
push:
	docker push $(WEAVE_NPC_252)-$(DATE)
