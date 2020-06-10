#!/bin/bash

. ./install_scripts/templates/common/common.sh
. ./install_scripts/templates/common/log.sh
. ./install_scripts/templates/common/prompt.sh
. ./install_scripts/templates/common/registryproxy.sh

test_configureRegistryProxyAddressOverride_UrlPrefix()
{
    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=url-prefix \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX= \
        configureRegistryProxyAddressOverride
    assertEquals "localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "docker-remote/" "$REGISTRY_PATH_PREFIX"

    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=url-prefix \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX=quay.io/replicated \
        configureRegistryProxyAddressOverride
    assertEquals "localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "quay-remote/" "$REGISTRY_PATH_PREFIX"

    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=url-prefix \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY=docker-custom \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX= \
        configureRegistryProxyAddressOverride
    assertEquals "localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "docker-custom/" "$REGISTRY_PATH_PREFIX"

    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=url-prefix \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY=quay-custom \
        REPLICATED_REGISTRY_PREFIX=quay.io/replicated \
        configureRegistryProxyAddressOverride
    assertEquals "localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "quay-custom/" "$REGISTRY_PATH_PREFIX"

    # default access method is url-prefix
    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD= \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY=docker-custom \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX= \
        configureRegistryProxyAddressOverride
    assertEquals "localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "docker-custom/" "$REGISTRY_PATH_PREFIX"

    # default access method is url-prefix
    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD= \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY=quay-custom \
        REPLICATED_REGISTRY_PREFIX=quay.io/replicated \
        configureRegistryProxyAddressOverride
    assertEquals "localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "quay-custom/" "$REGISTRY_PATH_PREFIX"

    # empty artifactory-address
    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD= \
        ARTIFACTORY_ADDRESS= \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX=quay.io/replicated \
        configureRegistryProxyAddressOverride
    assertEquals "" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "" "$REGISTRY_PATH_PREFIX"
}

test_configureRegistryProxyAddressOverride_Subdomain()
{
    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=subdomain \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX= \
        configureRegistryProxyAddressOverride
    assertEquals "docker-remote.localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "" "$REGISTRY_PATH_PREFIX"

    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=subdomain \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX=quay.io/replicated \
        configureRegistryProxyAddressOverride
    assertEquals "quay-remote.localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "" "$REGISTRY_PATH_PREFIX"

    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=subdomain \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY=docker-custom \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX= \
        configureRegistryProxyAddressOverride
    assertEquals "docker-custom.localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "" "$REGISTRY_PATH_PREFIX"

    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=subdomain \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY=quay-custom \
        REPLICATED_REGISTRY_PREFIX=quay.io/replicated \
        configureRegistryProxyAddressOverride
    assertEquals "quay-custom.localhost:8081" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "" "$REGISTRY_PATH_PREFIX"
}

test_configureRegistryProxyAddressOverride_Port()
{
    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=port \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY=8000 \
        ARTIFACTORY_QUAY_REPO_KEY= \
        REPLICATED_REGISTRY_PREFIX= \
        configureRegistryProxyAddressOverride
    assertEquals "localhost:8000" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "" "$REGISTRY_PATH_PREFIX"

    REGISTRY_ADDRESS_OVERRIDE=
    REGISTRY_PATH_PREFIX=
    ARTIFACTORY_ACCESS_METHOD=port \
        ARTIFACTORY_ADDRESS=localhost:8081 \
        ARTIFACTORY_DOCKER_REPO_KEY= \
        ARTIFACTORY_QUAY_REPO_KEY=8000 \
        REPLICATED_REGISTRY_PREFIX=quay.io/replicated \
        configureRegistryProxyAddressOverride
    assertEquals "localhost:8000" "$REGISTRY_ADDRESS_OVERRIDE"
    assertEquals "" "$REGISTRY_PATH_PREFIX"
}

test_maybePromptForArtifactoryAuth()
{
    ARTIFACTORY_AUTH="<ARTIFACTORY_SECRET>"
    maybePromptForArtifactoryAuth "admin" "password"
    assertEquals "YWRtaW46cGFzc3dvcmQ=" "$ARTIFACTORY_AUTH"
}

test_parseBasicAuth()
{
    parseBasicAuth "YWRtaW46cGFzc3dvcmQ="
    assertEquals "admin" "$BASICAUTH_USERNAME"
    assertEquals "password" "$BASICAUTH_PASSWORD"
}

test_writeRegistryProxyConfig()
{
    tempTestingFile="$(mktemp)"
    ARTIFACTORY_ADDRESS="localhost:8081"
    ARTIFACTORY_AUTH="YWRtaW46cGFzc3dvcmQ="
    ARTIFACTORY_ACCESS_METHOD="url-prefix"
    ARTIFACTORY_DOCKER_REPO_KEY="dockerio"
    ARTIFACTORY_QUAY_REPO_KEY=
    _writeRegistryProxyConfig "$tempTestingFile"

    read -r -d '' expected <<EOF
{
  "artifactory": {
    "address": "localhost:8081",
    "auth": "YWRtaW46cGFzc3dvcmQ=",
    "access_method": "url-prefix",
    "repository_key_map": {
      "docker.io": "dockerio"
    }
  }
}
EOF
    assertEquals "$expected" "$(cat $tempTestingFile)"

    tempTestingFile="$(mktemp)"
    ARTIFACTORY_ADDRESS="localhost:8081"
    ARTIFACTORY_AUTH="YWRtaW46cGFzc3dvcmQ="
    ARTIFACTORY_ACCESS_METHOD="url-prefix"
    ARTIFACTORY_DOCKER_REPO_KEY=
    ARTIFACTORY_QUAY_REPO_KEY="quayio"
    _writeRegistryProxyConfig "$tempTestingFile"

    read -r -d '' expected <<EOF
{
  "artifactory": {
    "address": "localhost:8081",
    "auth": "YWRtaW46cGFzc3dvcmQ=",
    "access_method": "url-prefix",
    "repository_key_map": {
      "quay.io": "quayio"
    }
  }
}
EOF
    assertEquals "$expected" "$(cat $tempTestingFile)"
}

test_writeRegistryProxyConfigQuayRepoKeyEmpty()
{
    tempTestingFile="$(mktemp)"
    ARTIFACTORY_ADDRESS="localhost:8081"
    ARTIFACTORY_AUTH="YWRtaW46cGFzc3dvcmQ="
    ARTIFACTORY_ACCESS_METHOD="url-prefix"
    ARTIFACTORY_DOCKER_REPO_KEY=
    ARTIFACTORY_QUAY_REPO_KEY=
    _writeRegistryProxyConfig "$tempTestingFile"

    read -r -d '' expected <<EOF
{
  "artifactory": {
    "address": "localhost:8081",
    "auth": "YWRtaW46cGFzc3dvcmQ=",
    "access_method": "url-prefix"
  }
}
EOF
    assertEquals "$expected" "$(cat $tempTestingFile)"
}

. shunit2
