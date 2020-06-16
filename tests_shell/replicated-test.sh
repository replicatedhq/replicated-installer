#!/bin/bash

. ./install_scripts/templates/common/common.sh
. ./install_scripts/templates/common/replicated.sh

test_getReplicatedRegistryPrefix()
{
    getReplicatedRegistryPrefix "2.43.0"
    assertEquals "quay.io/replicated" "$REPLICATED_REGISTRY_PREFIX"

    getReplicatedRegistryPrefix "2.44.2"
    assertEquals "quay.io/replicated" "$REPLICATED_REGISTRY_PREFIX"

    getReplicatedRegistryPrefix "2.45.0"
    assertEquals "replicated" "$REPLICATED_REGISTRY_PREFIX"

    getReplicatedRegistryPrefix "2.46.0"
    assertEquals "replicated" "$REPLICATED_REGISTRY_PREFIX"
}

. shunit2
