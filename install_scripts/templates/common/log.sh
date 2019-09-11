#######################################
# Prints the first arg in green with a checkmark
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
logSuccess() {
    printf "${GREEN}✔ $1${NC}\n" 1>&2
}

#######################################
# Prints the first arg in blue
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
logStep() {
    printf "${BLUE}⚙  $1${NC}\n" 1>&2
}

#######################################
# Prints the first arg indented in light blue
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
logSubstep() {
    printf "\t${LIGHT_BLUE}- $1${NC}\n" 1>&2
}

#######################################
# Prints the first arg in Yellow
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
logWarn() {
    printf "${YELLOW}$1${NC}\n" 1>&2
}


#######################################
# Prints the first arg in Red
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
logFail() {
    printf "${RED}$1${NC}\n" 1>&2
}

#######################################
# Prints the args in Red and exits 1
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
bail() {
    logFail "$@"
    exit 1
}

