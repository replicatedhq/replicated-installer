SHELL := /bin/bash

DOCKER_USER ?= replicated

.PHONY: build
build:
	make -C weave-kube/2.5.2 build

.PHONY: push
push:
	make -C weave-kube/2.5.2 push
