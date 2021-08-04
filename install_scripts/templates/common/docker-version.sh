
#######################################
#
# docker-version.sh
#
# require common.sh, system.sh
#
#######################################

#######################################
# Gets docker server version.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   DOCKER_VERSION
#######################################
DOCKER_VERSION=
getDockerVersion() {
    if ! isDockerInstalled ; then
        return
    fi

    DOCKER_VERSION=$(docker version --format '{{ '{{' }}.Server.Version{{ '}}' }}' 2>/dev/null || docker -v | awk '{gsub(/,/, "", $3); print $3}')
}

#######################################
# Parses docker version.
# Globals:
#   None
# Arguments:
#   Docker Version
# Returns:
#   DOCKER_VERSION_MAJOR
#   DOCKER_VERSION_MINOR
#   DOCKER_VERSION_PATCH
#   DOCKER_VERSION_RELEASE
#######################################
DOCKER_VERSION_MAJOR=
DOCKER_VERSION_MINOR=
DOCKER_VERSION_PATCH=
DOCKER_VERSION_RELEASE=
parseDockerVersion() {
    # reset
    DOCKER_VERSION_MAJOR=
    DOCKER_VERSION_MINOR=
    DOCKER_VERSION_PATCH=
    DOCKER_VERSION_RELEASE=
    if [ -z "$1" ]; then
        return
    fi

    OLD_IFS="$IFS" && IFS=. && set -- $1 && IFS="$OLD_IFS"
    DOCKER_VERSION_MAJOR=$1
    DOCKER_VERSION_MINOR=$2
    OLD_IFS="$IFS" && IFS=- && set -- $3 && IFS="$OLD_IFS"
    DOCKER_VERSION_PATCH=$1
    DOCKER_VERSION_RELEASE=$2
}

#######################################
# Compare two docker versions ignoring the patch version.
# Returns -1 if A lt B, 0 if eq, 1 A gt B.
# Globals:
#   None
# Arguments:
#   Docker Version A
#   Docker Version B
# Returns:
#   COMPARE_DOCKER_VERSIONS_RESULT
#######################################
COMPARE_DOCKER_VERSIONS_RESULT=
compareDockerVersionsIgnorePatch() {
    # reset
    COMPARE_DOCKER_VERSIONS_RESULT=
    parseDockerVersion "$1"
    _a_major="$DOCKER_VERSION_MAJOR"
    _a_minor="$DOCKER_VERSION_MINOR"
    parseDockerVersion "$2"
    _b_major="$DOCKER_VERSION_MAJOR"
    _b_minor="$DOCKER_VERSION_MINOR"
    if [ "$_a_major" -lt "$_b_major" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=-1
        return
    fi
    if [ "$_a_major" -gt "$_b_major" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=1
        return
    fi
    if [ "$_a_minor" -lt "$_b_minor" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=-1
        return
    fi
    if [ "$_a_minor" -gt "$_b_minor" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=1
        return
    fi
    COMPARE_DOCKER_VERSIONS_RESULT=0
}

#######################################
# Compare two docker versions.
# Returns -1 if A lt B, 0 if eq, 1 A gt B.
# Globals:
#   None
# Arguments:
#   Docker Version A
#   Docker Version B
# Returns:
#   COMPARE_DOCKER_VERSIONS_RESULT
#######################################
COMPARE_DOCKER_VERSIONS_RESULT=
compareDockerVersions() {
    # reset
    COMPARE_DOCKER_VERSIONS_RESULT=
    compareDockerVersionsIgnorePatch "$1" "$2"
    if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -ne "0" ]; then
        return
    fi
    parseDockerVersion "$1"
    _a_patch="$DOCKER_VERSION_PATCH"
    parseDockerVersion "$2"
    _b_patch="$DOCKER_VERSION_PATCH"
    if [ "$_a_patch" -lt "$_b_patch" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=-1
        return
    fi
    if [ "$_a_patch" -gt "$_b_patch" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=1
        return
    fi
    COMPARE_DOCKER_VERSIONS_RESULT=0
}

#######################################
# Get max docker version for lsb dist/version.
# Globals:
#   LSB_DIST
#   DIST_VERSION_MAJOR
#   DIST_VERSION
# Arguments:
#   None
# Returns:
#   MAX_DOCKER_VERSION_RESULT
#######################################
MAX_DOCKER_VERSION_RESULT=
getMaxDockerVersion() {
    MAX_DOCKER_VERSION_RESULT=

    # Max Docker version on CentOS 6 is 1.7.1.
    if [ "$LSB_DIST" = "centos" ]; then
        if [ "$DIST_VERSION_MAJOR" = "6" ]; then
            MAX_DOCKER_VERSION_RESULT="1.7.1"
        fi
    fi
    # Max Docker version on RHEL 6 is 1.7.1.
    if [ "$LSB_DIST" = "rhel" ]; then
        if [ "$DIST_VERSION_MAJOR" = "6" ]; then
            MAX_DOCKER_VERSION_RESULT="1.7.1"
        fi
    fi
    if [ "$LSB_DIST" = "ubuntu" ]; then
        # Max Docker version on Ubuntu 14.04 is 18.06.1.
        # see https://github.com/docker/for-linux/issues/591
        if [ "$DIST_VERSION" = "14.04" ]; then
            MAX_DOCKER_VERSION_RESULT="18.06.1"
        # Max Docker version on Ubuntu 16.04 is 19.03.8.
        elif [ "$DIST_VERSION" = "16.04" ]; then
            MAX_DOCKER_VERSION_RESULT="19.03.8"
        fi
    fi
    if [ "$LSB_DIST" = "debian" ]; then
        # Max Docker version on Debian 7 is 18.03.1
        if [ "$DIST_VERSION" = "7" ]; then
            MAX_DOCKER_VERSION_RESULT="18.03.1"
        # Max Docker version on Debian 8 is 18.06.2.
        elif [ "$DIST_VERSION" = "8" ]; then
            MAX_DOCKER_VERSION_RESULT="18.06.2"
        # Max Docker version on Debian 9 is 19.03.8.
        elif [ "$DIST_VERSION" = "9" ]; then
            MAX_DOCKER_VERSION_RESULT="19.03.8"
        fi
    fi
    # 2019-01-07
    # Max Docker version on Amazon Linux 2 is 18.09.9.
    if [ "$LSB_DIST" = "amzn" ]; then
        MAX_DOCKER_VERSION_RESULT="18.09.9"
    fi
    # 2020-05-11
    # Max Docker version on SUSE Linux Enterprise Server 12 and 15 is 19.03.5.
    if [ "$LSB_DIST" = "sles" ]; then
        MAX_DOCKER_VERSION_RESULT="19.03.5"
    fi
    # Max Docker version on Oracle Linux 6.x seems to be 17.05.0.
    if [ "$LSB_DIST" = "ol" ]; then
        if [ "$DIST_VERSION_MAJOR" = "6" ]; then
            MAX_DOCKER_VERSION_RESULT="17.05.0"
        fi
    fi
}

#######################################
# Get min docker version for lsb dist/version.
# Globals:
#   LSB_DIST
#   DIST_VERSION_MAJOR
#   DIST_VERSION
# Arguments:
#   None
# Returns:
#   MIN_DOCKER_VERSION_RESULT
#######################################
MIN_DOCKER_VERSION_RESULT=
getMinDockerVersion() {
    MIN_DOCKER_VERSION_RESULT=

    if [ "$LSB_DIST" = "ubuntu" ]; then
        # Min Docker version on Ubuntu 20.04 is 19.03.9.
        if [ "$DIST_VERSION" = "20.04" ]; then
            MIN_DOCKER_VERSION_RESULT="19.03.11"
        fi
    fi

    if [ "$LSB_DIST" = "centos" ] || [ "$LSB_DIST" = "rhel" ] || [ "$LSB_DIST" = "ol" ]; then
        # Min Docker version on RHEL/CentOS/OL 8.x is 20.10.7
        if [ "$DIST_VERSION_MAJOR" = "8" ]; then
            MIN_DOCKER_VERSION_RESULT="20.10.7"
        fi
    fi

}
