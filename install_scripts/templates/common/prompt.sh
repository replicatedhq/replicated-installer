
#######################################
#
# prompt.sh
#
#######################################

PROMPT_RESULT=

if [ -z "$READ_TIMEOUT" ]; then
    READ_TIMEOUT="-t 20"
fi


#######################################
# Prompts the user for input.
# Globals:
#   READ_TIMEOUT, FAST_TIMEOUTS
# Arguments:
#   None
# Returns:
#   PROMPT_RESULT
#######################################
promptTimeout() {
    set +e
    if [ -z "$FAST_TIMEOUTS" ]; then
        read ${1:-$READ_TIMEOUT} PROMPT_RESULT < /dev/tty
    else
        read ${READ_TIMEOUT} PROMPT_RESULT < /dev/tty
    fi
    set -e
}

#######################################
# Confirmation prompt default yes.
# Globals:
#   READ_TIMEOUT, FAST_TIMEOUTS
# Arguments:
#   None
# Returns:
#   None
#######################################
confirmY() {
    printf "(Y/n) "
    promptTimeout
    if [ "$PROMPT_RESULT" = "n" ] || [ "$PROMPT_RESULT" = "N" ]; then
        return 1
    fi
    return 0
}

#######################################
# Confirmation prompt default no.
# Globals:
#   READ_TIMEOUT, FAST_TIMEOUTS
# Arguments:
#   None
# Returns:
#   None
#######################################
confirmN() {
    printf "(y/N) "
    promptTimeout
    if [ "$PROMPT_RESULT" = "y" ] || [ "$PROMPT_RESULT" = "Y" ]; then
        return 0
    fi
    return 1
}


#######################################
# Prompts the user for input.
# Globals:
#   READ_TIMEOUT
# Arguments:
#   None
# Returns:
#   PROMPT_RESULT
#######################################
prompt() {
    set +e
    read PROMPT_RESULT < /dev/tty
    set -e
}
