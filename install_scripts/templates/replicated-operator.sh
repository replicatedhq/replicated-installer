#!/bin/bash

#
# This script is meant for quick & easy install via:
#   'curl -sSL {{ replicated_install_url }}/operator | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/operator | sudo bash'
#
# This script can also be used for upgrades by re-running on same host.
#

set -e

REPLICATED_VERSION="{{ replicated_version }}"
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
MIN_DOCKER_VERSION="{{ min_docker_version }}"
SKIP_DOCKER_INSTALL=0
SKIP_DOCKER_PULL=0
NO_PUBLIC_ADDRESS=0
NO_PROXY=0
AIRGAP=0
ONLY_INSTALL_DOCKER=0
OPERATOR_TAGS="{{ operator_tags }}"
REPLICATED_USERNAME="{{ replicated_username }}"
{% if use_fast_timeouts %}
READ_TIMEOUT="-t 1"
FAST_TIMEOUTS=1
{%- endif %}
NO_CE_ON_EE="{{ no_ce_on_ee }}"
HARD_FAIL_ON_LOOPBACK="{{ hard_fail_on_loopback }}"
HARD_FAIL_ON_FIREWALLD="{{ hard_fail_on_firewalld }}"
ADDITIONAL_NO_PROXY=
SKIP_PREFLIGHTS="{{ '1' if skip_preflights else '' }}"
IGNORE_PREFLIGHTS="{{ '1' if ignore_preflights else '' }}"
REGISTRY_ADDRESS_OVERRIDE=
REGISTRY_PATH_PREFIX=
DAEMON_REGISTRY_ADDRESS=

{% include 'common/common.sh' %}
{% include 'common/log.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/system.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/docker-install.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/proxy.sh' %}
{% include 'common/airgap.sh' %}
{% include 'common/selinux.sh' %}
{% include 'common/firewall.sh' %}
{% include 'common/registryproxy.sh' %}
{% include 'preflights/index.sh' %}

discoverPrivateIp() {
    if [ -n "$PRIVATE_ADDRESS" ]; then
        printf "The installer will use local address '%s' (from parameter)\n" "$PRIVATE_ADDRESS"
        return
    fi

    readReplicatedConf "LocalAddress"
    if [ -n "$REPLICATED_CONF_VALUE" ]; then
        PRIVATE_ADDRESS="$REPLICATED_CONF_VALUE"
        printf "The installer will use local address '%s' (imported from /etc/replicated.conf 'LocalAddress')\n" "$PRIVATE_ADDRESS"
        return
    fi

    promptForPrivateIp
}

remove_docker_containers() {
    # try twice because of aufs error "Unable to remove filesystem"
    if docker inspect replicated-operator &>/dev/null; then
        set +e
        docker rm -f replicated-operator
        _status=$?
        set -e
        if [ "$_status" -ne "0" ]; then
            if docker inspect replicated-operator &>/dev/null; then
                printf "Failed to remove replicated-operator container, retrying\n"
                sleep 1
                docker rm -f replicated-operator
            fi
        fi
    fi
}

tag_docker_images() {
    printf "Tagging replicated-operator image\n"
    # older docker versions require -f flag to move a tag from one image to another
    docker tag "${REPLICATED_REGISTRY_PREFIX}/replicated-operator:{{ replicated_operator_tag }}{{ environment_tag_suffix }}" "${REPLICATED_REGISTRY_PREFIX}/replicated-operator:current" \
        || docker tag -f "${REPLICATED_REGISTRY_PREFIX}/replicated-operator:{{ replicated_operator_tag }}{{ environment_tag_suffix }}" "${REPLICATED_REGISTRY_PREFIX}/replicated-operator:current"
}

find_hostname() {
    set +e
    SYS_HOSTNAME=`hostname -f`
    if [ "$?" -ne "0" ]; then
        SYS_HOSTNAME=`hostname`
        if [ "$?" -ne "0" ]; then
            SYS_HOSTNAME=""
        fi
    fi
    set -e
}

SELINUX_REPLICATED_DOMAIN=
CUSTOM_SELINUX_REPLICATED_DOMAIN=0
get_selinux_replicated_domain() {
    # may have been set by command line argument
    if [ -n "$SELINUX_REPLICATED_DOMAIN" ]; then
        CUSTOM_SELINUX_REPLICATED_DOMAIN=1
        return
    fi

    # if previously set to a custom domain it will be in REPLICATED_OPERATOR_OPTS
    readReplicatedOperatorOpts "SELINUX_REPLICATED_DOMAIN"
    if [ -n "$REPLICATED_OPTS_VALUE" ]; then
        SELINUX_REPLICATED_DOMAIN="$REPLICATED_OPTS_VALUE"
        CUSTOM_SELINUX_REPLICATED_DOMAIN=1
        return
    fi

    # default if unset
    SELINUX_REPLICATED_DOMAIN=spc_t
}

REPLICATED_OPERATOR_OPTS=
build_replicated_operator_opts() {
    if [ -n "$REPLICATED_OPERATOR_OPTS" ]; then
        if [ -n "$PUBLIC_ADDRESS" ]; then
            REPLICATED_OPERATOR_OPTS=$(echo "$REPLICATED_OPERATOR_OPTS" | sed -e 's/-e[[:blank:]]*PUBLIC_ADDRESS=[^[:blank:]]*//g')
            REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS -e PUBLIC_ADDRESS=$PUBLIC_ADDRESS"
        fi
        REPLICATED_OPERATOR_OPTS=$(echo "$REPLICATED_OPERATOR_OPTS" | sed -e 's/-e[[:blank:]]*NO_PROXY=[^[:blank:]]*//g')
        if [ -n "$NO_PROXY_ADDRESSES" ]; then
           REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS -e NO_PROXY=$NO_PROXY_ADDRESSES"
        fi
        REPLICATED_OPERATOR_OPTS=$(echo "$REPLICATED_OPERATOR_OPTS" | sed -e 's/-e[[:blank:]]*DAEMON_REGISTRY_ENDPOINT=[^[:blank:]]*//g')
        if [ -n "$DAEMON_REGISTRY_ADDRESS" ]; then
           REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS -e DAEMON_REGISTRY_ENDPOINT=$DAEMON_REGISTRY_ADDRESS"
        fi
        # if '--read-only' is not present, add it
        if ! echo "$REPLICATED_OPERATOR_OPTS" | grep -q -- '--read-only'; then # -- in grep because otherwise the search string is interpreted as a flag
            if [ -n "$REPLICATED_DOCKER_READONLY_FLAG" ]; then
                REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS $REPLICATED_DOCKER_READONLY_FLAG"
            fi
        fi
        return
    fi

    REPLICATED_OPERATOR_OPTS=" $REPLICATED_DOCKER_READONLY_FLAG"
    if [ -n "$OPERATOR_ID" ]; then
        REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e OPERATOR_ID=$OPERATOR_ID"
    fi
    if [ -n "$PUBLIC_ADDRESS" ]; then
        REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e PUBLIC_ADDRESS=$PUBLIC_ADDRESS"
    fi
    if [ -n "$OPERATOR_TAGS" ]; then
        REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e TAGS=$OPERATOR_TAGS"
    fi
    if [ -n "$LOG_LEVEL" ]; then
        REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e LOG_LEVEL=$LOG_LEVEL"
    else
        REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e LOG_LEVEL=info"
    fi
    if [ "$AIRGAP" = "1" ]; then
        REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e AIRGAP=true"
    fi
    if [ "$CUSTOM_SELINUX_REPLICATED_DOMAIN" = "1" ]; then
        REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e SELINUX_REPLICATED_DOMAIN=$SELINUX_REPLICATED_DOMAIN"
    fi
    if [ -n "$NO_PROXY_ADDRESSES" ]; then
        REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS -e NO_PROXY=$NO_PROXY_ADDRESSES"
    fi

    find_hostname
    REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e NODENAME=$SYS_HOSTNAME"

    dockerGetLoggingDriver
    if [ "$DOCKER_LOGGING_DRIVER" = "json-file" ]; then
        REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS --log-opt max-size=50m --log-opt max-file=3"
    fi

    if [ -n "$DAEMON_REGISTRY_ADDRESS" ]; then
        REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS -e DAEMON_REGISTRY_ENDPOINT=$DAEMON_REGISTRY_ADDRESS"
    fi
}

write_replicated_configuration() {
    DAEMON_HOST=`echo $DAEMON_ENDPOINT | sed -e 's/:.*$//'`
    cat > $CONFDIR/replicated-operator <<-EOF
RELEASE_CHANNEL={{ channel_name }}
DAEMON_ENDPOINT=$DAEMON_ENDPOINT
DAEMON_TOKEN=$DAEMON_TOKEN
DAEMON_HOST=$DAEMON_HOST
PRIVATE_ADDRESS=$PRIVATE_ADDRESS
REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS"
EOF
}

write_systemd_services() {
    cat > /etc/systemd/system/replicated-operator.service <<-EOF
{% include 'systemd/replicated-operator.service' %}
EOF

    systemctl daemon-reload
}

write_upstart_services() {
    REPLICATED_RESTART_POLICY=
    # NOTE: SysVinit does not support dependencies therefore we must add a
    # restart policy to the replicated service. The tradeoff here is that
    # SysVinit will lose track of the replicated process when docker restarts
    # the replicated service.
    if ! ls /etc/init/docker* 1> /dev/null 2>&1; then
        REPLICATED_RESTART_POLICY="--restart always"
    fi

    cat > /etc/init/replicated-operator.conf <<-EOF
{% include 'upstart/replicated-operator.conf' %}
EOF
    cat > /etc/init/replicated-operator-stop.conf <<-EOF
{% include 'upstart/replicated-operator-stop.conf' %}
EOF
}

write_sysvinit_services() {
    cat > /etc/init.d/replicated-operator <<-EOF
{% include 'sysvinit/replicated-operator' %}
EOF
}

stop_systemd_services() {
    if systemctl status replicated-operator &>/dev/null; then
        systemctl stop replicated-operator
    fi
}

start_systemd_services() {
    systemctl enable replicated-operator
    systemctl start replicated-operator
}

stop_upstart_services() {
    if status replicated-operator &>/dev/null && ! status replicated-operator 2>/dev/null | grep -q "stop"; then
        stop replicated-operator
    fi
}

start_upstart_services() {
    start replicated-operator
}

stop_sysvinit_services() {
    if service replicated-operator status &>/dev/null; then
        service replicated-operator stop
    fi
}

start_sysvinit_services() {
    chmod +x /etc/init.d/replicated-operator
    # TODO: what about chkconfig
    update-rc.d replicated-operator stop 20 0 1 6 . start 20 2 3 4 5 .
    update-rc.d replicated-operator enable
    service replicated-operator start
}

migrate_autoconfig_file() {
    if [ -e /var/lib/replicated-operator/replicated-operator.conf ]; then
        # file already migrated
        return 0
    fi
    if [ -e /etc/replicated-operator.conf ]; then
        if [ ! -e /var/lib/replicated-operator ]; then
            mkdir -p /var/lib/replicated-operator
        fi
        mv /etc/replicated-operator.conf /var/lib/replicated-operator/replicated-operator.conf
    fi
}

outro() {
    printf "\nOperator installation successful\n"
    printf "\n"
}


################################################################################
# Execution starts here
################################################################################

export DEBIAN_FRONTEND=noninteractive

maybeCreateTempDir
require64Bit
requireRootUser
detectLsbDist
detectInitSystem
detectInitSystemConfDir
getReplicatedRegistryPrefix "$REPLICATED_VERSION"
getReplicatedReadonlyDockerFlag "$REPLICATED_VERSION"

# read existing replicated opts values
if [ -f $CONFDIR/replicated-operator ]; then
    # shellcheck source=replicated-operator-default
    . $CONFDIR/replicated-operator
    # support for the old installation script that used REPLICATED_OPTS for
    # operator
    if [ -z "$REPLICATED_OPERATOR_OPTS" ] && [ -n "$REPLICATED_OPTS" ]; then
        REPLICATED_OPERATOR_OPTS="$REPLICATED_OPTS"
    fi
fi

# override these values with command line flags
while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        daemon-endpoint|daemon_endpoint)
            DAEMON_ENDPOINT="$_value"
            ;;
        daemon-token|daemon_token)
            DAEMON_TOKEN="$_value"
            ;;
        daemon-registry-address|daemon_registry_address)
            DAEMON_REGISTRY_ADDRESS="$_value"
            ;;
        operator-id)
            OPERATOR_ID="$_value"
            ;;
        local-address|local_address|private-address|private_address)
            PRIVATE_ADDRESS="$_value"
            NO_PRIVATE_ADDRESS_PROMPT="1"
            ;;
        public-address|public_address)
            PUBLIC_ADDRESS="$_value"
            ;;
        no-public-address|no_public_address)
            NO_PUBLIC_ADDRESS=1
            ;;
        no-docker|no_docker)
            SKIP_DOCKER_INSTALL=1
            ;;
        install-docker-only|install_docker_only)
            ONLY_INSTALL_DOCKER=1
            ;;
        no-proxy|no_proxy)
            NO_PROXY=1
            ;;
        airgap)
            AIRGAP=1
            SKIP_DOCKER_INSTALL=1
            ;;
        tags)
            OPERATOR_TAGS="$_value"
            ;;
        no-auto|no_auto)
            READ_TIMEOUT=
            ;;
        skip-pull|skip_pull)
            SKIP_DOCKER_PULL=1
            ;;
        bypass-storagedriver-warnings|bypass_storagedriver_warnings)
            BYPASS_STORAGEDRIVER_WARNINGS=1
            ;;
        log-level|log_level)
            LOG_LEVEL="$_value"
            ;;
        selinux-replicated-domain|selinux_replicated_domain)
            SELINUX_REPLICATED_DOMAIN="$_value"
            ;;
        fast-timeouts|fast_timeouts)
            READ_TIMEOUT="-t 1"
            FAST_TIMEOUTS=1
            ;;
        no-ce-on-ee|no_ce_on_ee)
            NO_CE_ON_EE=1
            ;;
        hard-fail-on-loopback|hard_fail_on_loopback)
            HARD_FAIL_ON_LOOPBACK=1
            ;;
        bypass-firewalld-warning|bypass_firewalld_warning)
            BYPASS_FIREWALLD_WARNING=1
            ;;
        hard-fail-on-firewalld|hard_fail_on_firewalld)
            HARD_FAIL_ON_FIREWALLD=1
            ;;
        additional-no-proxy|additional_no_proxy)
            if [ -z "$ADDITIONAL_NO_PROXY" ]; then
                ADDITIONAL_NO_PROXY="$_value"
            else
                ADDITIONAL_NO_PROXY="$ADDITIONAL_NO_PROXY,$_value"
            fi
            ;;
        skip-preflights|skip_preflights)
            SKIP_PREFLIGHTS=1
            ;;
        prompt-on-preflight-warnings|prompt_on_preflight_warnings)
            IGNORE_PREFLIGHTS=0
            ;;
        ignore-preflights|ignore_preflights)
            # do nothing
            ;;
        artifactory-address|artifactory_address)
            ARTIFACTORY_ADDRESS="$_value"
            ;;
        artifactory-access-method|artifactory_access_method)
            ARTIFACTORY_ACCESS_METHOD="$_value"
            ;;
        artifactory-docker-repo-key|artifactory_docker_repo_key)
            ARTIFACTORY_DOCKER_REPO_KEY="$_value"
            ;;
        artifactory-quay-repo-key|artifactory_quay_repo_key)
            ARTIFACTORY_QUAY_REPO_KEY="$_value"
            ;;
        artifactory-auth)
            ARTIFACTORY_AUTH="$_value"
            ;;
        registry-address-override|registry_address_override)
            REGISTRY_ADDRESS_OVERRIDE="$_value"
            ;;
        registry-path-prefix|registry_path_prefix)
            REGISTRY_PATH_PREFIX="$_value"
            ;;
        *)
            echo "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

checkFirewalld

if [ "$ONLY_INSTALL_DOCKER" = "1" ]; then
    # no min if only installing docker
    installDocker "$PINNED_DOCKER_VERSION" "0.0.0"

    checkDockerDriver
    checkDockerStorageDriver "$HARD_FAIL_ON_LOOPBACK"
    exit 0
fi

if [ -z "$PRIVATE_ADDRESS" ]; then
    printf "Determining local address\n"
    discoverPrivateIp
fi

if [ -z "$PUBLIC_ADDRESS" ] && [ "$AIRGAP" != "1" ] && [ "$NO_PUBLIC_ADDRESS" != "1" ]; then
    printf "Determining service address\n"
    discoverPublicIp

    readReplicatedOperatorOpts "PUBLIC_ADDRESS"
    if [ -z "$PUBLIC_ADDRESS" ]; then
        PUBLIC_ADDRESS="$REPLICATED_OPTS_VALUE"
    fi
    # Check that the public address from discoverPublicIp matches the one from Replicated Operator opts
    if [ -n "$REPLICATED_OPTS_VALUE" ] && [ "$REPLICATED_OPTS_VALUE" = "$PUBLIC_ADDRESS" ]; then
        printf "The installer will use service address '%s' (imported from $CONFDIR/replicated-operator 'PUBLIC_ADDRESS')\n" $PUBLIC_ADDRESS
    else
        if [ -n "$PUBLIC_ADDRESS" ]; then
            # If public addresses do not match then prompt with confirmation
            shouldUsePublicIp
        else
            printf "The installer was unable to automatically detect the service IP address of this machine.\n"
            printf "Please enter the address or leave blank for unspecified.\n"
            promptForPublicIp
            if [ -z "$PUBLIC_ADDRESS" ]; then
                NO_PUBLIC_ADDRESS=1
            fi
        fi
    fi
fi

maybePromptForArtifactoryAuth
configureRegistryProxyAddressOverride

if [ "$NO_PROXY" != "1" ]; then
    if [ -z "$PROXY_ADDRESS" ]; then
        discoverProxy
    fi

    if [ -z "$PROXY_ADDRESS" ] && [ "$AIRGAP" != "1" ]; then
        promptForProxy
    fi

    if [ -n "$PROXY_ADDRESS" ]; then
        getNoProxyAddresses "$DAEMON_ENDPOINT"
    fi
fi

exportProxy

if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
    installDocker "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"

    checkDockerDriver
    checkDockerStorageDriver "$HARD_FAIL_ON_LOOPBACK"
else
    requireDocker
fi

if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
    requireDockerProxy
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
    checkDockerProxyConfig
fi

if [ "$SKIP_PREFLIGHTS" != "1" ]; then
    echo ""
    echo "Running preflight checks..."
    runPreflights || true
    if [ "$IGNORE_PREFLIGHTS" != "1" ]; then
        if [ "$HAS_PREFLIGHT_ERRORS" = "1" ]; then
            bail "\nPreflights have encountered some errors. Please correct them before proceeding."
        elif [ "$HAS_PREFLIGHT_WARNINGS" = "1" ]; then
            logWarn "\nPreflights have encountered some warnings. Please review them before proceeding."
            logWarn "Would you like to proceed anyway?"
            if ! confirmN " "; then
                exit 1
                return
            fi
        fi
    fi
fi

if [ -n "$ARTIFACTORY_ADDRESS" ] && [ -n "$ARTIFACTORY_AUTH" ]; then
    parseBasicAuth "$ARTIFACTORY_AUTH"
    echo "+ docker login $ARTIFACTORY_ADDRESS --username $BASICAUTH_USERNAME"
    echo "$BASICAUTH_PASSWORD" | docker login "$ARTIFACTORY_ADDRESS" --username "$BASICAUTH_USERNAME" --password-stdin
fi

detectDockerGroupId
maybeCreateReplicatedUser

promptForDaemonEndpoint
promptForDaemonToken

if [ "$SKIP_DOCKER_PULL" = "1" ]; then
    printf "Skip docker pull flag detected, will not pull replicated-operator container\n"
elif [ "$AIRGAP" != "1" ]; then
    printf "Pulling latest replicated-operator image\n"
    pullOperatorImage
else
    printf "Loading replicated-operator image from package\n"
    airgapLoadOperatorImage
fi

tag_docker_images

printf "Stopping replicated-operator service\n"
case "$INIT_SYSTEM" in
    systemd)
        stop_systemd_services
        ;;
    upstart)
        stop_upstart_services
        ;;
    sysvinit)
        stop_sysvinit_services
        ;;
esac
remove_docker_containers

printf "Installing replicated-operator service\n"
get_selinux_replicated_domain
get_selinux_replicated_domain_label
build_replicated_operator_opts
write_replicated_configuration
case "$INIT_SYSTEM" in
    systemd)
        write_systemd_services
        ;;
    upstart)
        write_upstart_services
        ;;
    sysvinit)
        write_sysvinit_services
        ;;
esac

printf "Starting replicated-operator service\n"
migrate_autoconfig_file
case "$INIT_SYSTEM" in
    systemd)
        start_systemd_services
        ;;
    upstart)
        start_upstart_services
        ;;
    sysvinit)
        start_sysvinit_services
        ;;
esac

outro
exit 0
