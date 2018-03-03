
#######################################
#
# docker-swarm.sh
#
# require prompt.sh
#
#######################################

#######################################
# Prompts for swarm master address if not already set.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   SWARM_MASTER_ADDRESS
#######################################
SWARM_MASTER_ADDRESS=
promptForSwarmMasterAddress() {
    if [ -n "$SWARM_MASTER_ADDRESS" ]; then
        return
    fi

    printf "Please enter the Swarm master address.\n"
    while true; do
        printf "Swarm master address: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            SWARM_MASTER_ADDRESS="$PROMPT_RESULT"
            return
        fi
    done
}

#######################################
# Prompts for swarm token if not already set.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   SWARM_TOKEN
#######################################
SWARM_TOKEN=
promptForSwarmToken() {
    if [ -n "$SWARM_TOKEN" ]; then
        return
    fi

    printf "Please enter the Swarm token.\n"
    while true; do
        printf "Swarm token: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            SWARM_TOKEN="$PROMPT_RESULT"
            return
        fi
    done
}
