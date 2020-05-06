SHELL := /bin/bash

DOCKER_IMAGE := weave-kube
DOCKER_TAG := 2.5.2-20200505

.PHONY: build
build:
	docker build --pull -t $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG) .

.PHONY: push
push:
	docker push $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG)
