###############################################################################
## selinux.sh
###############################################################################

###############################################################################
# Check if SELinux is in enforcing mode
###############################################################################
preflightSelinuxEnforcing()
{
    local enforcing=
    if commandExists "getenforce"; then
        enforcing="$(getenforce)"
    elif commandExists "sestatus"; then
        enforcing="$(sestatus | grep 'SELinux mode' | awk '{ print $3 }')"
    else
        return 0
    fi

    if echo "$enforcing" | grep -qi enforcing; then
        warn "SELinux is in enforcing mode"
        return 1
    fi
    info "SELinux is not in enforcing mode"
    return 0
}
