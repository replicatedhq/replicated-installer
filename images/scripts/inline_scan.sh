#!/bin/bash

set -e

run_cmd="curl -s https://ci-tools.anchore.io/inline_scan-${ANCHORE_VERSION} | bash -s -- -r -t $TIMEOUT"
if $POLICY_FAILURE; then
    run_cmd="$run_cmd -f"
fi
if [[ ! -z $POLICY_BUNDLE_PATH ]] && [[ -f $POLICY_BUNDLE_PATH ]]; then
    run_cmd="$run_cmd -b $POLICY_BUNDLE_PATH"
else
    echo "ERROR - could not find policy bundle $POLICY_BUNDLE_PATH - using default policy bundle."
fi
if [[ ! -z $DOCKERFILE_PATH ]] && [[ -f $DOCKERFILE_PATH ]]; then
    run_cmd="$run_cmd -d $DOCKERFILE_PATH"
else
    echo "ERROR - could not find Dockerfile $DOCKERFILE_PATH - Dockerfile not included in scan."
fi
run_cmd="$run_cmd $IMAGE_NAME"
docker pull docker.io/anchore/inline-scan:${ANCHORE_VERSION}
eval "set -x; $run_cmd"
