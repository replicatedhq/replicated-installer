
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
# Reads a value from REPLICATED_OPTS variable in the /etc/default/replicated file
# Globals:
#   REPLICATED_OPTS
# Arguments:
#   Variable to read
# Returns:
#   REPLICATED_OPTS_VALUE
#######################################
readReplicatedOpts() {
    unset REPLICATED_OPTS_VALUE
    REPLICATED_OPTS_VALUE="$(echo "$REPLICATED_OPTS" | grep -o "$1=[^ ]*" | cut -d'=' -f2)"
}

#######################################
# Reads a value from REPLICATED_OPERATOR_OPTS variable in the /etc/default/replicated-operator file
# Globals:
#   REPLICATED_OPTS
# Arguments:
#   Variable to read
# Returns:
#   REPLICATED_OPTS_VALUE
#######################################
readReplicatedOperatorOpts() {
    unset REPLICATED_OPTS_VALUE
    REPLICATED_OPTS_VALUE="$(echo "$REPLICATED_OPERATOR_OPTS" | grep -o "$1=[^ ]*" | cut -d'=' -f2)"
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
# Creates user and adds to Docker group
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

#######################################
# Pull replicated and replicated-ui container images.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
pullReplicatedImages() {
    docker pull "{{ replicated_docker_host }}/replicated/replicated:{{ replicated_tag|default('stable', true) }}{{ environment_tag_suffix }}"
    docker pull "{{ replicated_docker_host }}/replicated/replicated-ui:{{ replicated_ui_tag|default('stable', true) }}{{ environment_tag_suffix }}"
}

#######################################
# Pull replicated-operator container image.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
pullOperatorImage() {
    docker pull "{{ replicated_docker_host }}/replicated/replicated-operator:{{ replicated_operator_tag|default('stable', true) }}{{ environment_tag_suffix }}"
}

#######################################
# Tag and push replicated-operator container image to the on-prem registry.
# Globals:
#   None
# Arguments:
#   On-prem registry address
# Returns:
#   None
#######################################
tagAndPushOperatorImage()  {
    docker tag \
        "{{ replicated_docker_host }}/replicated/replicated-operator:{{ replicated_operator_tag|default('stable', true) }}{{ environment_tag_suffix }}" \
        "${1}/replicated/replicated-operator:{{ replicated_operator_tag|default('stable', true) }}{{ environment_tag_suffix }}"
    docker push "${1}/replicated/replicated-operator:{{ replicated_operator_tag|default('stable', true) }}{{ environment_tag_suffix }}"
}
