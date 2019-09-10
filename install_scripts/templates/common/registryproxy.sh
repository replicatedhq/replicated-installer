
#######################################
#
# registryproxy.sh
#
# require common.sh
#
#######################################

ARTIFACTORY_ADDRESS=
ARTIFACTORY_ACCESS_METHOD=
ARTIFACTORY_QUAY_REPO_KEY=
ARTIFACTORY_AUTH=

#######################################
# Configures the registry address override
# and path prefix when a registry proxy is set.
# Globals:
#   ARTIFACTORY_ADDRESS
#   ARTIFACTORY_ACCESS_METHOD
#   ARTIFACTORY_QUAY_REPO_KEY
# Arguments:
#   None
# Returns:
#   REGISTRY_ADDRESS_OVERRIDE
#   REGISTRY_PATH_PREFIX
#######################################
configureRegistryProxyAddressOverride()
{
    if [ -z "$ARTIFACTORY_ADDRESS" ]; then
        return
    fi

    if [ "$AIRGAP" = "1" ]; then
        printf "${RED}Artifactory regsitry proxy cannot be used with airgap.${NC}\n" 1>&2
        exit 1
    fi

    case "$ARTIFACTORY_ACCESS_METHOD" in
        url-prefix)
            _configureRegistryProxyAddressOverride_UrlPrefix
            ;;
        subdomain)
            _configureRegistryProxyAddressOverride_Subdomain
            ;;
        port)
            _configureRegistryProxyAddressOverride_Port
            ;;
        *)
            # default url-prefix
            _configureRegistryProxyAddressOverride_UrlPrefix
            ;;
    esac
}

_configureRegistryProxyAddressOverride_UrlPrefix()
{
    if [ -z "$ARTIFACTORY_ADDRESS" ]; then
        return
    fi

    local quayRepoKey="$ARTIFACTORY_QUAY_REPO_KEY"
    if [ -z "$quayRepoKey" ]; then
        printf "${YELLOW}Flag \"artifactory-quay-repo-key\" not set, defaulting to \"quay-remote\".${NC}\n"
        quayRepoKey="quay-remote"
    fi
    REGISTRY_ADDRESS_OVERRIDE="$ARTIFACTORY_ADDRESS"
    REGISTRY_PATH_PREFIX="${quayRepoKey}/"
}

_configureRegistryProxyAddressOverride_Subdomain()
{
    if [ -z "$ARTIFACTORY_ADDRESS" ]; then
        return
    fi

    local quayRepoKey="$ARTIFACTORY_QUAY_REPO_KEY"
    if [ -z "$quayRepoKey" ]; then
        printf "${YELLOW}Flag \"artifactory-quay-repo-key\" not set, defaulting to \"quay-remote\".${NC}\n"
        quayRepoKey="quay-remote"
    fi
    REGISTRY_ADDRESS_OVERRIDE="${quayRepoKey}.${ARTIFACTORY_ADDRESS}"
}

_configureRegistryProxyAddressOverride_Port()
{
    if [ -z "$ARTIFACTORY_ADDRESS" ]; then
        return
    fi

    if [ -z "$ARTIFACTORY_QUAY_REPO_KEY" ]; then
        printf "${RED}Flag \"artifactory-quay-repo-key\" required for Artifactory access method \"port\".${NC}\n" 1>&2
        exit 1
    fi
    splitHostPort "$ARTIFACTORY_ADDRESS"
    REGISTRY_ADDRESS_OVERRIDE="${HOST}:${ARTIFACTORY_QUAY_REPO_KEY}"
}

#######################################
# Writes registry proxy config if it does not exist.
# Globals:
#   ARTIFACTORY_ADDRESS
#   ARTIFACTORY_ACCESS_METHOD
#   ARTIFACTORY_QUAY_REPO_KEY
#   ARTIFACTORY_AUTH
# Arguments:
#   None
# Returns:
#   None
#######################################
maybeWriteRegistryProxyConfig()
{
    if [ -z "$ARTIFACTORY_ADDRESS" ]; then
        return
    fi

    if [ -f /etc/replicated/registry_proxy.json ]; then
        return
    fi

    printf "\n${YELLOW}Registry proxy configuration file /etc/replicated/registry_proxy.json not found.${NC}\n\n"
    printf "${YELLOW}Please follow the documentation at: ${NC}\n"
    printf "${YELLOW}  https://help.replicated.com/docs/native/customer-installations/registry-proxies/ .${NC}\n\n"
    printf "${YELLOW}Do you want to proceed anyway? ${NC}"
    if ! confirmN; then
        exit 0
    fi

    mkdir -p /etc/replicated
    cat > /etc/replicated/registry_proxy.json <<-EOF
{
  "artifactory": {
    "address": "$ARTIFACTORY_ADDRESS",
    "auth": "$ARTIFACTORY_AUTH",
    "access_method": "$ARTIFACTORY_ACCESS_METHOD",
    "repository_key_map": {
      "quay.io": "$ARTIFACTORY_QUAY_REPO_KEY"
    }
  }
}
EOF
}

#######################################
# Parses a basic auth string (base64 user:pass)
# Globals:
#   None
# Arguments:
#   $1 - Auth string
# Returns:
#   BASICAUTH_USERNAME
#   BASICAUTH_PASSWORD
#######################################
parseBasicAuth()
{
    BASICAUTH_USERNAME=
    BASICAUTH_PASSWORD=
    local auth="$(echo "$1" | base64 --decode)"
    oIFS="$IFS"; IFS=":" read -r BASICAUTH_USERNAME BASICAUTH_PASSWORD <<< "$auth"; IFS="$oIFS"
}
