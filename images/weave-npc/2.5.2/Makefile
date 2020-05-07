SHELL := /bin/bash

ANCHORE_VERSION := v0.7.1

include ../../manifest.mk

.PHONY: all
all: build scan push

.PHONY: build
build:
	docker build --pull -t $(WEAVE_NPC_252) .

export ANCHORE_VERSION

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
	docker push $(WEAVE_NPC_252)
