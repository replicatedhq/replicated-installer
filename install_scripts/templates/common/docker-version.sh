
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
    if ! commandExists "docker"; then
        return
    fi

    DOCKER_VERSION=$(docker -v | awk '{gsub(/,/, "", $3); print $3}')
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
    parseDockerVersion "$1"
    _a_major="$DOCKER_VERSION_MAJOR"
    _a_minor="$DOCKER_VERSION_MINOR"
    _a_patch="$DOCKER_VERSION_PATCH"
    parseDockerVersion "$2"
    _b_major="$DOCKER_VERSION_MAJOR"
    _b_minor="$DOCKER_VERSION_MINOR"
    _b_patch="$DOCKER_VERSION_PATCH"
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
# Arguments:
#   None
# Returns:
#   MAX_DOCKER_VERSION_RESULT
#######################################
MAX_DOCKER_VERSION_RESULT=
getMaxDockerVersion() {
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
    # Max Docker version on Fedora 21 is 1.9.1.
    if [ "$LSB_DIST" = "fedora" ]; then
        if [ "$DIST_VERSION_MAJOR" = "21" ]; then
            MAX_DOCKER_VERSION_RESULT="1.9.1"
        fi
    fi
    # Max Docker version on Ubuntu 15.04 is 1.9.1.
    if [ "$LSB_DIST" = "ubuntu" ]; then
        if [ "$DIST_VERSION" = "15.04" ]; then
            MAX_DOCKER_VERSION_RESULT="1.9.1"
        fi
    fi
    # Amazon has their own repo and 1.12.6 and 17.06.2 are available there for now.
    if [ "$LSB_DIST" = "amzn" ]; then
        if [ "$_version" = "2017.03" ]; then 
           MAX_DOCKER_VERSION_RESULT="17.03.2"
        else 
           MAX_DOCKER_VERSION_RESULT="17.06.2"
        fi
    fi
    # Max Docker version on SUSE Linux Enterprise Server 12 SP1 is 1.12.6.
    if [ "$LSB_DIST" = "sles" ]; then
        MAX_DOCKER_VERSION_RESULT="1.12.6"
    fi
    # Max Docker version on Oracle Linux 6.x seems to be 17.03.1.
    if [ "$LSB_DIST" = "ol" ]; then
        if [ "$DIST_VERSION_MAJOR" = "6" ]; then
            MAX_DOCKER_VERSION_RESULT="17.03.1"
        fi
    fi
}
