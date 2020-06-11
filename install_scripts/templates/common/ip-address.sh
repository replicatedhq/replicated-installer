
#######################################
#
# ip-address.sh
#
# require common.sh, prompt.sh
#
#######################################

PRIVATE_ADDRESS=
PUBLIC_ADDRESS=

#######################################
# Prompts the user for a private address.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   PRIVATE_ADDRESS
#######################################
promptForPrivateIp() {
    _count=0
    _regex="^[[:digit:]]+: ([^[:space:]]+)[[:space:]]+[[:alnum:]]+ ([[:digit:].]+)"
    while read -r _line; do
        [[ $_line =~ $_regex ]]
        if [ "${BASH_REMATCH[1]}" != "lo" ]; then
            _iface_names[$((_count))]=${BASH_REMATCH[1]}
            _iface_addrs[$((_count))]=${BASH_REMATCH[2]}
            let "_count += 1"
        fi
    done <<< "$(ip -4 -o addr)"
    if [ "$_count" -eq "0" ]; then
        echo >&2 "Error: The installer couldn't discover any valid network interfaces on this machine."
        echo >&2 "Check your network configuration and re-run this script again."
        echo >&2 "If you want to skip this discovery process, pass the 'local-address' arg to this script, e.g. 'sudo ./install.sh local-address=1.2.3.4'"
        exit 1
    elif [ "$_count" -eq "1" ]; then
        PRIVATE_ADDRESS=${_iface_addrs[0]}
        printf "The installer will use network interface '%s' (with IP address '%s')\n" "${_iface_names[0]}" "${_iface_addrs[0]}"
        return
    fi
    printf "The installer was unable to automatically detect the private IP address of this machine.\n"
    printf "Please choose one of the following network interfaces:\n"
    for i in $(seq 0 $((_count-1))); do
        printf "[%d] %-5s\t%s\n" "$i" "${_iface_names[$i]}" "${_iface_addrs[$i]}"
    done
    while true; do
        printf "Enter desired number (0-%d): " "$((_count-1))"
        prompt
        if [ -z "$PROMPT_RESULT" ]; then
            continue
        fi
        if [ "$PROMPT_RESULT" -ge "0" ] && [ "$PROMPT_RESULT" -lt "$_count" ]; then
            PRIVATE_ADDRESS=${_iface_addrs[$PROMPT_RESULT]}
            printf "The installer will use network interface '%s' (with IP address '%s').\n" "${_iface_names[$PROMPT_RESULT]}" "$PRIVATE_ADDRESS"
            return
        fi
    done
}

#######################################
# Discovers public IP address from cloud provider metadata services.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   PUBLIC_ADDRESS
#######################################
discoverPublicIp() {
    if [ -n "$PUBLIC_ADDRESS" ]; then
        printf "The installer will use service address '%s' (from parameter)\n" "$PUBLIC_ADDRESS"
        return
    fi

    # gce
    if commandExists "curl"; then
        set +e
        _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null)
        _status=$?
        set -e
    else
        set +e
        _out=$(wget --no-proxy -t 1 --timeout=5 --connect-timeout=2 -qO- --header='Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null)
        _status=$?
        set -e
    fi
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        PUBLIC_ADDRESS=$_out
        printf "The installer will use service address '%s' (discovered from GCE metadata service)\n" "$PUBLIC_ADDRESS"
        return
    fi

    # ec2
    if commandExists "curl"; then
        set +e
        _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
        _status=$?
        set -e
    else
        set +e
        _out=$(wget --no-proxy -t 1 --timeout=5 --connect-timeout=2 -qO- http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
        _status=$?
        set -e
    fi
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        PUBLIC_ADDRESS=$_out
        printf "The installer will use service address '%s' (discovered from EC2 metadata service)\n" "$PUBLIC_ADDRESS"
        return
    fi

    # azure
    if commandExists "curl"; then
        set +e
        _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text" 2>/dev/null)
        _status=$?
        set -e
    else
        set +e
        _out=$(wget --no-proxy -t 1 --timeout=5 --connect-timeout=2 -qO- --header='Metadata:true' "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text" 2>/dev/null)
        _status=$?
        set -e
    fi
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        PUBLIC_ADDRESS=$_out
        printf "The installer will use service address '%s' (discovered from Azure metadata service)\n" "$PUBLIC_ADDRESS"
        return
    fi
}

#######################################
# Prompts the user for a public address.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   PUBLIC_ADDRESS
#######################################
shouldUsePublicIp() {
    if [ -z "$PUBLIC_ADDRESS" ]; then
        return
    fi

    printf "The installer has automatically detected the service IP address of this machine as %s.\n" "$PUBLIC_ADDRESS"
    printf "Do you want to:\n"
    printf "[0] default: use %s\n" "$PUBLIC_ADDRESS"
    printf "[1] enter new address\n"
    printf "Enter desired number (0-1): "
    promptTimeout
    if [ "$PROMPT_RESULT" = "1" ]; then
        promptForPublicIp
    fi
}

#######################################
# Prompts the user for a public address.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   PUBLIC_ADDRESS
#######################################
promptForPublicIp() {
    while true; do
        printf "Service IP address: "
        promptTimeout "-t 120"
        if [ -n "$PROMPT_RESULT" ]; then
            if isValidIpv4 "$PROMPT_RESULT"; then
                PUBLIC_ADDRESS=$PROMPT_RESULT
                break
            else
                printf "%s is not a valid ip address.\n" "$PROMPT_RESULT"
            fi
        else
            break
        fi
    done
}

#######################################
# Determines if the ip is a valid ipv4 address.
# Globals:
#   None
# Arguments:
#   IP
# Returns:
#   None
#######################################
isValidIpv4() {
    if echo "$1" | grep -qs '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$'; then
        return 0
    else
        return 1
    fi
}

#######################################
# Determines if the ip is a valid ipv6 address. This will match long and short IPv6 addresses as
# well as the loopback address.
# Globals:
#   None
# Arguments:
#   IP
# Returns:
#   None
#######################################
isValidIpv6() {
    if echo "$1" | grep -qs "^\([0-9a-fA-F]\{0,4\}:\)\{1,7\}[0-9a-fA-F]\{0,4\}$"; then
        return 0
    else
        return 1
    fi
}

#######################################
# Returns the ip portion of an address.
# Globals:
#   None
# Arguments:
#   ADDRESS
# Returns:
#   PARSED_IPV4
#######################################
PARSED_IPV4=
parseIpv4FromAddress() {
    PARSED_IPV4=$(echo "$1" | grep --only-matching '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*')
}

#######################################
# Validates a private address against the ip routes.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if valid
#######################################
isValidPrivateIp() {
    local privateIp="$1"
    local _regex="^[[:digit:]]+: ([^[:space:]]+)[[:space:]]+[[:alnum:]]+ ([[:digit:].]+)"
    while read -r _line; do
        [[ $_line =~ $_regex ]]
        if [ "${BASH_REMATCH[1]}" != "lo" ] && [ "${BASH_REMATCH[2]}" = "$privateIp" ]; then
            return 0
        fi
    done <<< "$(ip -4 -o addr)"
    return 1
}
