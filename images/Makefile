SHELL := /bin/bash

export BUILDKITE_ACCESS_TOKEN
export IMAGE_TARGET

export COMMIT := HEAD
export BRANCH := master
export MESSAGE = Build image $(IMAGE_TARGET)

.PHONY: build_ci
build_ci:
	./scripts/build_ci.sh
