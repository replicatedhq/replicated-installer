#!/bin/bash

set -e

if [ -z "$IMAGE_TARGET" ]; then
    echo >&2 "env IMAGE_TARGET required"
    exit 1
fi

COMMIT=${COMMIT:-HEAD}
BRANCH=${BRANCH:-master}
MESSAGE=${MESSAGE:-Building image $IMAGE_TARGET}

set -x
curl -X POST "https://api.buildkite.com/v2/organizations/replicated/pipelines/replicated-installer-image/builds" \
  -d $'{
    "commit": "$COMMIT",
    "branch": "$BRANCH",
    "message": "$MESSAGE",
    "env": {
      "IMAGE_TARGET": "$IMAGE_TARGET"
    }
  }'
