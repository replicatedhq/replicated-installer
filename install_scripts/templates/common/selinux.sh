
#######################################
#
# selinux.sh
#
# require common.sh docker-version.sh
#
#######################################

#######################################
# Check if SELinux is enabled
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Non-zero exit status unless SELinux is enabled
#######################################
selinux_enabled() {
    if commandExists "selinuxenabled"; then
        selinuxenabled
        return
    elif commandExists "sestatus"; then
        ENABLED=$(sestatus | grep 'SELinux status' | awk '{ print $3 }')
        echo "$ENABLED" | grep --quiet --ignore-case enabled
        return
    fi

    return 1
}

#######################################
# Check if SELinux is enforced
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Non-zero exit status unelss SELinux is enforced
#######################################
selinux_enforced() {
    if commandExists "getenforce"; then
        ENFORCED=$(getenforce)
        echo $(getenforce) | grep --quiet --ignore-case enforcing
        return
    elif commandExists "sestatus"; then
        ENFORCED=$(sestatus | grep 'SELinux mode' | awk '{ print $3 }')
        echo "$ENFORCED" | grep --quiet --ignore-case enforcing
        return
    fi

    return 1
}

SELINUX_REPLICATED_DOMAIN_LABEL=
get_selinux_replicated_domain_label() {
    getDockerVersion

    compareDockerVersions "$DOCKER_VERSION" "1.11.0"
    if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
        SELINUX_REPLICATED_DOMAIN_LABEL="label:type:$SELINUX_REPLICATED_DOMAIN"
    else
        SELINUX_REPLICATED_DOMAIN_LABEL="label=type:$SELINUX_REPLICATED_DOMAIN"
    fi
}

#######################################
# Prints a warning if selinux is enabled and enforcing
# Globals:
#   None
# Arguments:
#   Mode - either permissive or enforcing
# Returns:
#   None
#######################################
warn_if_selinux() {
    if selinux_enabled ; then
        if selinux_enforced ; then
            printf "${YELLOW}SELinux is enforcing. Running docker with the \"--selinux-enabled\" flag may cause some features to become unavailable.${NC}\n\n"
        else
            printf "${YELLOW}SELinux is enabled. Switching to enforcing mode and running docker with the \"--selinux-enabled\" flag may cause some features to become unavailable.${NC}\n\n"
        fi
    fi
}
