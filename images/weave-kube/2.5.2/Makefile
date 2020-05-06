SHELL := /bin/bash

DOCKER_USER := replicated
DOCKER_IMAGE := weave-kube
DOCKER_TAG := 2.5.2-20200505

ANCHORE_VERSION := v0.7.1

.PHONY: all
all: build scan push

.PHONY: build
build:
	docker build --pull -t $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG) .

export ANCHORE_VERSION

.PHONY: scan
scan: export POLICY_FAILURE = 1
scan: export TIMEOUT = 300
scan: export POLICY_BUNDLE_PATH = ../../policy-bundle.json
scan: export DOCKERFILE_PATH = ./Dockerfile
scan: export IMAGE_NAME = $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG)
scan:
	bash ../../inline_scan.sh

.PHONY: push
push:
	docker push $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG)
