
#######################################
#
# docker-swarm.sh
#
# require prompt.sh
#
#######################################

#######################################
# Prompts for swarm manager address if not already set.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   SWARM_MANAGER_ADDRESS
#######################################
SWARM_MANAGER_ADDRESS=
promptForSwarmManagerAddress() {
    if [ -n "$SWARM_MANAGER_ADDRESS" ]; then
        return
    fi

    printf "Please enter the Swarm manager address.\n"
    while true; do
        printf "Swarm manager address: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            SWARM_MANAGER_ADDRESS="$PROMPT_RESULT"
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
