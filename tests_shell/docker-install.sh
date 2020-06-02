#!/bin/bash

. ./install_scripts/templates/common/docker-version.sh
. ./install_scripts/templates/common/docker-install.sh

testDockerGetBestVersion()
{
    BEST_DOCKER_VERSION_RESULT=
    LSB_DIST=ubuntu
    DIST_VERSION=18.04
    _dockerGetBestVersion "18.09.3"
    assertEquals "no min max" "18.09.3" "$BEST_DOCKER_VERSION_RESULT"

    BEST_DOCKER_VERSION_RESULT=
    LSB_DIST=ubuntu
    DIST_VERSION=14.04
    _dockerGetBestVersion "17.05.0"
    assertEquals "less than max" "17.05.0" "$BEST_DOCKER_VERSION_RESULT"

    BEST_DOCKER_VERSION_RESULT=
    LSB_DIST=ubuntu
    DIST_VERSION=20.04
    _dockerGetBestVersion "18.09.3"
    assertEquals "min" "19.03.11" "$BEST_DOCKER_VERSION_RESULT"

    BEST_DOCKER_VERSION_RESULT=
    LSB_DIST=ubuntu
    DIST_VERSION=14.04
    _dockerGetBestVersion "18.09.3"
    assertEquals "max" "18.06.1" "$BEST_DOCKER_VERSION_RESULT"
}

. shunit2
