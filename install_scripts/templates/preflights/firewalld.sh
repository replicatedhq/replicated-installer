###############################################################################
## firewalld.sh
###############################################################################

###############################################################################
# Determine if firewalld is active
###############################################################################
preflightFirewalld()
{
    if ! commandExists "systemctl"; then
        return 0
    fi
    if ! systemctl -q is-active firewalld; then
        info "Firewalld is not active"
        return 0
    fi

    warn "Firewalld is active"
    return 1
}
