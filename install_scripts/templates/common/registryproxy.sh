
#######################################
#
# registryproxy.sh
#
# require common.sh
# require log.sh
# require prompt.sh
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
        bail "Artifactory registry proxy cannot be used with airgap."
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
        logWarn "Flag \"artifactory-quay-repo-key\" not set, defaulting to \"quay-remote\"."
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
        logWarn "Flag \"artifactory-quay-repo-key\" not set, defaulting to \"quay-remote\"."
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
        bail "Flag \"artifactory-quay-repo-key\" required for Artifactory access method \"port\"."
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
    printf "${YELLOW}Do you want to proceed anyway? ${NC}"
    if ! confirmN; then
        exit 0
    fi

    _writeRegistryProxyConfig "/etc/replicated/registry_proxy.json"
}

_writeRegistryProxyConfig()
{
    mkdir -p /etc/replicated
    cat > "$1" <<-EOF
{
  "artifactory": {
    "address": "$ARTIFACTORY_ADDRESS",
    "auth": "$ARTIFACTORY_AUTH",
EOF
    if [ -n "$ARTIFACTORY_QUAY_REPO_KEY" ]; then
        cat >> "$1" <<-EOF
    "access_method": "$ARTIFACTORY_ACCESS_METHOD",
    "repository_key_map": {
      "quay.io": "$ARTIFACTORY_QUAY_REPO_KEY"
    }
  }
}
EOF
    else
        cat >> "$1" <<-EOF
    "access_method": "$ARTIFACTORY_ACCESS_METHOD"
  }
}
EOF
    fi
}

#######################################
# Prompts for Artifactory auth creds if ARTIFACTORY_AUTH
# is set to string literal "<ARTIFACTORY_SECRET>".
# Globals:
#   ARTIFACTORY_AUTH
# Arguments:
#   $1 - username (for testing)
#   $2 - password (for testing)
# Returns:
#   ARTIFACTORY_AUTH
#######################################
maybePromptForArtifactoryAuth()
{
    if [ "$ARTIFACTORY_AUTH" != "<ARTIFACTORY_SECRET>" ]; then
        return
    fi

    artifactoryUsername="$1"
    artifactoryPassword="$2"

    printf "\nPlease enter your artifactory registry credentials (leave blank to skip)\n"
    if [ -z "$artifactoryUsername" ]; then
        printf "Username: "
        prompt
        local artifactoryUsername="$PROMPT_RESULT"
    fi
    if [ -z "$artifactoryPassword" ]; then
        printf "Password: "
        prompt
        local artifactoryPassword="$PROMPT_RESULT"
    fi
    if [ -z "$artifactoryUsername" ] || [ -z "$artifactoryPassword" ]; then
        logWarn "Artifactory credentials are empty"
        unset ARTIFACTORY_AUTH
        return
    fi
    ARTIFACTORY_AUTH="$(echo -n $artifactoryUsername:$artifactoryPassword | base64)"
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
