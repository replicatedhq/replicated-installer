SHELL := /bin/bash

export DOCKER_USER := replicated

.PHONY: build
build:
	$(MAKE) -C weave-kube/2.5.2 build

.PHONY: scan
scan:
	$(MAKE) -C weave-kube/2.5.2 scan

.PHONY: push
push:
	$(MAKE) -C weave-kube/2.5.2 push
