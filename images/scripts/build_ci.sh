#!/bin/bash

set -e

if [ -z "$BUILDKITE_ACCESS_TOKEN" ]; then
    echo >&2 "BUILDKITE_ACCESS_TOKEN required"
    exit 1
elif [ -z "$IMAGE_TARGET" ]; then
    echo >&2 "IMAGE_TARGET required"
    exit 1
elif [ ! -d "$IMAGE_TARGET" ]; then
    echo >&2 "IMAGE_TARGET=$IMAGE_TARGET invalid"
    exit 1
fi

COMMIT=${COMMIT:-HEAD}
BRANCH=${BRANCH:-master}
MESSAGE=${MESSAGE:-Building image $IMAGE_TARGET}

set -x
curl -X POST "https://api.buildkite.com/v2/organizations/replicated/pipelines/replicated-installer-image/builds" \
    -H "Authorization: Bearer $BUILDKITE_ACCESS_TOKEN" \
    -d "{
        \"commit\": \"$COMMIT\",
        \"branch\": \"$BRANCH\",
        \"message\": \"$MESSAGE\",
        \"env\": {
            \"IMAGE_TARGET\": \"$IMAGE_TARGET\"
        }
    }"
