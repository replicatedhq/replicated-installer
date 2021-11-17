
#######################################
#
# proxy.sh
#
# require prompt.sh, system.sh, docker.sh, replicated.sh
#
#######################################

PROXY_ADDRESS=
DID_CONFIGURE_DOCKER_PROXY=0

#######################################
# Prompts for proxy address.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   PROXY_ADDRESS
#######################################
promptForProxy() {
    printf "Does this machine require a proxy to access the Internet? "
    if ! confirmN; then
        return
    fi

    printf "Enter desired HTTP proxy address: "
    prompt
    if [ -n "$PROMPT_RESULT" ]; then
        if [ "${PROMPT_RESULT:0:7}" != "http://" ] && [ "${PROMPT_RESULT:0:8}" != "https://" ]; then
            echo >&2 "Proxy address must have prefix \"http(s)://\""
            exit 1
        fi
        PROXY_ADDRESS="$PROMPT_RESULT"
        printf "The installer will use the proxy at '%s'\n" "$PROXY_ADDRESS"
    fi
}

#######################################
# Discovers proxy address from environment.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   PROXY_ADDRESS
#######################################
discoverProxy() {
    readReplicatedConf "HttpProxy"
    if [ -n "$REPLICATED_CONF_VALUE" ]; then
        PROXY_ADDRESS="$REPLICATED_CONF_VALUE"
        printf "The installer will use the proxy at '%s' (imported from /etc/replicated.conf 'HttpProxy')\n" "$PROXY_ADDRESS"
        return
    fi

    if [ -n "$HTTP_PROXY" ]; then
        PROXY_ADDRESS="$HTTP_PROXY"
        printf "The installer will use the proxy at '%s' (imported from env var 'HTTP_PROXY')\n" "$PROXY_ADDRESS"
        return
    elif [ -n "$http_proxy" ]; then
        PROXY_ADDRESS="$http_proxy"
        printf "The installer will use the proxy at '%s' (imported from env var 'http_proxy')\n" "$PROXY_ADDRESS"
        return
    elif [ -n "$HTTPS_PROXY" ]; then
        PROXY_ADDRESS="$HTTPS_PROXY"
        printf "The installer will use the proxy at '%s' (imported from env var 'HTTPS_PROXY')\n" "$PROXY_ADDRESS"
        return
    elif [ -n "$https_proxy" ]; then
        PROXY_ADDRESS="$https_proxy"
        printf "The installer will use the proxy at '%s' (imported from env var 'https_proxy')\n" "$PROXY_ADDRESS"
        return
    fi
}

#######################################
# Requires that docker is set up with an http proxy.
# Globals:
#   PROXY_ADDRESS
#   NO_PROXY_ADDRESSES
#   DID_INSTALL_DOCKER
# Arguments:
#   None
# Returns:
#   None
#######################################
requireDockerProxy() {
    _previous_proxy="$(docker info 2>/dev/null | grep -i 'Http Proxy:' | sed 's/ *Http Proxy: //I')"
    _previous_no_proxy="$(docker info 2>/dev/null | grep -i 'No Proxy:' | sed 's/ *No Proxy: //I')"
    if [ "$PROXY_ADDRESS" = "$_previous_proxy" ] && [ "$NO_PROXY_ADDRESSES" = "$_previous_no_proxy" ]; then
        return
    fi

    _allow=n
    if [ "$DID_INSTALL_DOCKER" = "1" ]; then
        _allow=y
    else
        if [ -n "$_previous_proxy" ]; then
            printf "${YELLOW}It looks like Docker is set up with http proxy address $_previous_proxy.${NC}\n"
            if [ -n "$_previous_no_proxy" ]; then
                printf "${YELLOW}and no proxy addresses $_previous_no_proxy.${NC}\n"
            fi
            printf "${YELLOW}This script will automatically reconfigure it now.${NC}\n"
        else
            printf "${YELLOW}It does not look like Docker is set up with http proxy enabled.${NC}\n"
            printf "${YELLOW}This script will automatically configure it now.${NC}\n"
        fi
        printf "${YELLOW}Do you want to allow this?${NC} "
        if confirmY; then
            _allow=y
        fi
    fi
    if [ "$_allow" = "y" ]; then
        configureDockerProxy
    else
        printf "${YELLOW}Do you want to proceed anyway?${NC} "
        if ! confirmN; then
            printf "${RED}Please manually configure your Docker daemon with environment HTTP_PROXY.${NC}\n" 1>&2
            exit 1
        fi
    fi
}

#######################################
# Configures docker to run with an http proxy.
# Globals:
#   INIT_SYSTEM
#   PROXY_ADDRESS
#   NO_PROXY_ADDRESSES
# Arguments:
#   None
# Returns:
#   RESTART_DOCKER
#######################################
configureDockerProxy() {
    case "$INIT_SYSTEM" in
        systemd)
            _docker_conf_file=/etc/systemd/system/docker.service.d/http-proxy.conf
            mkdir -p /etc/systemd/system/docker.service.d

            _configureDockerProxySystemd "$_docker_conf_file" "$PROXY_ADDRESS" "$NO_PROXY_ADDRESSES"
            RESTART_DOCKER=1
            ;;
        upstart|sysvinit)
            _docker_conf_file=
            if [ -e /etc/sysconfig/docker ]; then
                _docker_conf_file=/etc/sysconfig/docker
            else
                _docker_conf_file=/etc/default/docker
                mkdir -p /etc/default
            fi

            _configureDockerProxyUpstart "$_docker_conf_file" "$PROXY_ADDRESS" "$NO_PROXY_ADDRESSES"
            RESTART_DOCKER=1
            ;;
        *)
            return 0
            ;;
    esac
    DID_CONFIGURE_DOCKER_PROXY=1
}

#######################################
# Configures systemd docker to run with an http proxy.
# Globals:
#   None
# Arguments:
#   $1 - config file
#   $2 - proxy address
#   $3 - no proxy address
# Returns:
#   None
#######################################
_configureDockerProxySystemd() {
    if [ ! -e "$1" ]; then
        touch "$1" # create the file if it doesn't exist
    fi

    if [ ! -s "$1" ]; then # if empty
        echo "# Generated by replicated install script" >> "$1"
        echo "[Service]" >> "$1"
    fi
    if ! grep -q "^\[Service\] *$" "$1"; then
        # don't mess with this file in this case
        return
    fi
    if ! grep -q "^Environment=" "$1"; then
        echo "Environment=" >> "$1"
    fi

    sed -i'' -e "s/\"*HTTP_PROXY=[^[:blank:]]*//" "$1" # remove old http proxy address
    sed -i'' -e "s/\"*HTTPS_PROXY=[^[:blank:]]*//" "$1" # remove old https proxy address
    sed -i'' -e "s/\"*NO_PROXY=[^[:blank:]]*//" "$1" # remove old no proxy address
    sed -i'' -e "s/^\(Environment=\) */\1/" "$1" # remove space after equals sign
    sed -i'' -e "s/ $//" "$1" # remove trailing space

    sed -i'' -e "s#^\(Environment=.*$\)#\1 \"HTTP_PROXY=${2}\"#" "$1"
    sed -i'' -e "s#^\(Environment=.*$\)#\1 \"HTTPS_PROXY=${2}\"#" "$1"
    sed -i'' -e "s#^\(Environment=.*$\)#\1 \"NO_PROXY=${3}\"#" "$1"
}

#######################################
# Configures upstart docker to run with an http proxy.
# Globals:
#   None
# Arguments:
#   $1 - config file
#   $2 - proxy address
#   $3 - no proxy address
# Returns:
#   None
#######################################
_configureDockerProxyUpstart() {
    if [ ! -e "$1" ]; then
        touch "$1" # create the file if it doesn't exist
    fi

    _export_proxy="export http_proxy=\"$2\""
    _export_noproxy="export NO_PROXY=\"$3\""
    if grep -q "^export http_proxy" "$1"; then
        sed -i'' -e "s#^export *http_proxy=.*#$_export_proxy#" "$1"
        _export_proxy=
    fi
    if grep -q "^export NO_PROXY" "$1"; then
        sed -i'' -e "s#^export *NO_PROXY=.*#$_export_noproxy#" "$1"
        _export_noproxy=
    fi

    if [ -n "$_export_proxy" ] || [ -n "$_export_noproxy" ]; then
        echo "" >> "$1"
        echo "# Generated by replicated install script" >> "$1"
    fi
    if [ -n "$_export_proxy" ]; then
        echo "$_export_proxy" >> "$1"
    fi
    if [ -n "$_export_noproxy" ]; then
        echo "$_export_noproxy" >> "$1"
    fi
}

#######################################
# Check that the docker proxy configuration was successful.
# Globals:
#   DID_CONFIGURE_DOCKER_PROXY
# Arguments:
#   None
# Returns:
#   None
#######################################
checkDockerProxyConfig() {
    if [ "$DID_CONFIGURE_DOCKER_PROXY" != "1" ]; then
        return
    fi
    if docker info 2>/dev/null | grep -q -i "Http Proxy:"; then
        return
    fi

    echo -e "${RED}Docker proxy configuration failed.${NC}"
    printf "Do you want to proceed anyway? "
    if ! confirmN; then
        echo >&2 "Please manually configure your Docker daemon with environment HTTP_PROXY."
        exit 1
    fi
}

#######################################
# Exports proxy configuration.
# Globals:
#   PROXY_ADDRESS
# Arguments:
#   None
# Returns:
#   None
#######################################
exportProxy() {
    if [ -z "$PROXY_ADDRESS" ]; then
        return
    fi
    if [ -z "$http_proxy" ]; then
       export http_proxy=$PROXY_ADDRESS
    fi
    if [ -z "$https_proxy" ]; then
       export https_proxy=$PROXY_ADDRESS
    fi
    if [ -z "$HTTP_PROXY" ]; then
       export HTTP_PROXY=$PROXY_ADDRESS
    fi
    if [ -z "$HTTPS_PROXY" ]; then
       export HTTPS_PROXY=$PROXY_ADDRESS
    fi
}

#######################################
# Assembles a sane list of no_proxy addresses
# Globals:
#   ADDITIONAL_NO_PROXY (optional)
# Arguments:
#   None
# Returns:
#   NO_PROXY_ADDRESSES
#######################################
NO_PROXY_ADDRESSES=
getNoProxyAddresses() {
    get_docker0_gateway_ip

    NO_PROXY_ADDRESSES="localhost,127.0.0.1,$DOCKER0_GATEWAY_IP"

    if [ -n "$ADDITIONAL_NO_PROXY" ]; then
        NO_PROXY_ADDRESSES="$NO_PROXY_ADDRESSES,$ADDITIONAL_NO_PROXY"
    fi

    while [ "$#" -gt 0 ]
    do
        # [10.138.0.2]:9878 -> 10.138.0.2
        hostname=`echo $1 | sed -e 's/:[0-9]*$//' | sed -e 's/[][]//g'`
        if [ -n "$hostname" ]; then
            NO_PROXY_ADDRESSES="$NO_PROXY_ADDRESSES,$hostname"
        fi
        shift
    done

    # filter duplicates
    NO_PROXY_ADDRESSES=`echo "$NO_PROXY_ADDRESSES" | sed 's/,/\n/g' | sort | uniq | paste -s --delimiters=","`
}
