###############################################################################
## iptables.sh
###############################################################################

###############################################################################
# Check if iptables default policy for the input chain is drop
###############################################################################
preflightIptablesInputDrop()
{
    if iptables -L | grep 'Chain INPUT (policy DROP)'; then
        warn "Iptables chain INPUT default policy DROP"
        return 1
    fi

    info "Iptables chain INPUT default policy ACCEPT"
    return 0
}
