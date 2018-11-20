
#######################################
#
# firewall.sh
#
# require prompt.sh
#
#######################################

#######################################
# Warns or terminates if firewalld is active
# Globals:
#   HARD_FAIL_ON_FIREWALLD, INIT_SYSTEM
# Arguments:
#   None
# Returns:
#   None
#######################################
checkFirewalld() {
    # firewalld is only available on RHEL 7+ so other init systems can be ignored
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        return
    fi
    if ! systemctl -q is-active firewalld ; then
        return
    fi

    if [ "$HARD_FAIL_ON_FIREWALLD" = "1" ]; then
        printf "${RED}Firewalld is active${NC}\n"
        exit 1
    fi

    printf "${YELLOW}Continue with firewalld active? ${NC}"
    if confirmY ; then
        return
    fi
    exit 1
}
