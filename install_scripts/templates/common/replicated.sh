
#######################################
#
# replicated.sh
#
# require prompt.sh
#
#######################################

#######################################
# Reads a value from the /etc/replicated.conf file
# Globals:
#   None
# Arguments:
#   Variable to read
# Returns:
#   REPLICATED_CONF_VALUE
#######################################
readReplicatedConf() {
    unset REPLICATED_CONF_VALUE
    if [ -f /etc/replicated.conf ]; then
        REPLICATED_CONF_VALUE=$(cat /etc/replicated.conf | grep -o "\"$1\":\s*\"[^\"]*" | sed "s/\"$1\":\s*\"//") || true
    fi
}

#######################################
# Prompts for daemon endpoint if not already set.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   DAEMON_ENDPOINT
#######################################
DAEMON_ENDPOINT=
promptForDaemonEndpoint() {
    if [ -n "$DAEMON_ENDPOINT" ]; then
        return
    fi

    printf "Please enter the 'Daemon Address' displayed on the 'Cluster' page of your On-Prem Console.\n"
    while true; do
        printf "Daemon Address: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            DAEMON_ENDPOINT="$PROMPT_RESULT"
            return
        fi
    done
}

#######################################
# Prompts for daemon token if not already set.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   DAEMON_TOKEN
#######################################
DAEMON_TOKEN=
promptForDaemonToken() {
    if [ -n "$DAEMON_TOKEN" ]; then
        return
    fi

    printf "Please enter the 'Secret Token' displayed on the 'Cluster' page of your On-Prem Console.\n"
    while true; do
        printf "Secret Token: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            DAEMON_TOKEN="$PROMPT_RESULT"
            return
        fi
    done
}

#######################################
# Prompts for daemon token if not already set.
# Globals:
#   REPLICATED_USERNAME
# Arguments:
#   None
# Returns:
#   REPLICATED_USER_ID
#######################################
REPLICATED_USER_ID=0
maybeCreateReplicatedUser() {
    # require REPLICATED_USERNAME
    if [ -z "$REPLICATED_USERNAME" ]; then
        return
    fi

    # Create the users
    REPLICATED_USER_ID=$(id -u "$REPLICATED_USERNAME" 2>/dev/null || true)
    if [ -z "$REPLICATED_USER_ID" ]; then
        useradd -g "${DOCKER_GROUP_ID:-0}" "$REPLICATED_USERNAME"
        REPLICATED_USER_ID=$(id -u "$REPLICATED_USERNAME")
    fi

    # Add the users to the docker group if needed
    # Versions older than 2.5.0 run as root
    if [ "$REPLICATED_USER_ID" != "0" ]; then
        usermod -a -G "${DOCKER_GROUP_ID:-0}" "$REPLICATED_USERNAME"
    fi
}
