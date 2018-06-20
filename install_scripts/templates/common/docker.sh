
#######################################
#
# docker.sh
#
# require common.sh, system.sh
#
#######################################

RESTART_DOCKER=0

#######################################
# Starts docker.
# Globals:
#   LSB_DIST
#   INIT_SYSTEM
# Arguments:
#   None
# Returns:
#   None
#######################################
startDocker() {
    if [ "$LSB_DIST" = "amzn" ]; then
        service docker start
        return
    fi
    case "$INIT_SYSTEM" in
        systemd)
            systemctl enable docker
            systemctl start docker
            ;;
        upstart|sysvinit)
            service docker start
            ;;
    esac
}

#######################################
# Restarts docker.
# Globals:
#   LSB_DIST
#   INIT_SYSTEM
# Arguments:
#   None
# Returns:
#   None
#######################################
restartDocker() {
    if [ "$LSB_DIST" = "amzn" ]; then
        service docker restart
        return
    fi
    case "$INIT_SYSTEM" in
        systemd)
            systemctl daemon-reload
            systemctl restart docker
            ;;
        upstart|sysvinit)
            service docker restart
            ;;
    esac
}

#######################################
# Checks support for docker driver.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
checkDockerDriver() {
    if ! commandExists "docker"; then
        echo >&2 "Error: docker is not installed."
        exit 1
    fi

    if [ "$(ps -ef | grep "docker" | grep -v "grep" | wc -l)" = "0" ]; then
        startDocker
    fi

    _driver=$(docker info 2>/dev/null | grep 'Execution Driver' | awk '{print $3}' | awk -F- '{print $1}')
    if [ "$_driver" = "lxc" ]; then
        echo >&2 "Error: the running Docker daemon is configured to use the '${_driver}' execution driver."
        echo >&2 "This installer only supports the 'native' driver (AKA 'libcontainer')."
        echo >&2 "Check your Docker daemon options."
        exit 1
    fi
}

#######################################
# Checks support for docker storage driver.
# Globals:
#   BYPASS_STORAGEDRIVER_WARNINGS
# Arguments:
#   None
# Returns:
#   None
#######################################
BYPASS_STORAGEDRIVER_WARNINGS=
checkDockerStorageDriver() {
    if [ "$BYPASS_STORAGEDRIVER_WARNINGS" = "1" ]; then
        return
    fi

    if ! commandExists "docker"; then
        echo >&2 "Error: docker is not installed."
        exit 1
    fi

    if [ "$(ps -ef | grep "docker" | grep -v "grep" | wc -l)" = "0" ]; then
        startDocker
    fi

    HARD_FAIL="{{ hard_fail }}"

    _driver=$(docker info 2>/dev/null | grep 'Storage Driver' | awk '{print $3}' | awk -F- '{print $1}')
    if [ "$_driver" = "devicemapper" ] && docker info 2>/dev/null | grep -Fqs 'Data loop file:' ; then
        printf "${RED}The running Docker daemon is configured to use the 'devicemapper' storage driver \
in loopback mode.\nThis is not recommended for production use. Please see to the following URL for more \
information.\n\nhttps://help.replicated.com/docs/kb/developer-resources/devicemapper-warning/.${NC}\n\n\
"
        if [ "$HARD_FAIL" ]; then
            exit 1
        fi
    fi
}

#######################################
# Get the docker group ID.
# Default to 0 for root group.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   DOCKER_GROUP_ID
#   None
#######################################
DOCKER_GROUP_ID=0
detectDockerGroupId() {
    # Parse the docker group from the docker.sock file
    # On most systems this will be a group called `docker`
    if [ -e /var/run/docker.sock ]; then
        DOCKER_GROUP_ID="$(stat -c '%g' /var/run/docker.sock)"
    # If the docker.sock file doesn't fall back to the docker group.
    elif [ "$(getent group docker)" ]; then
        DOCKER_GROUP_ID="$(getent group docker | cut -d: -f3)"
    fi
}
