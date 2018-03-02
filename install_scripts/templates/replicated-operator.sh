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

PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
MIN_DOCKER_VERSION="{{ min_docker_version }}"
SKIP_DOCKER_INSTALL=0
SKIP_DOCKER_PULL=0
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

{% include 'common/common.sh' %}
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

read_replicated_operator_opts() {
    REPLICATED_OPTS_VALUE="$(echo "$REPLICATED_OPERATOR_OPTS" | grep -o "$1=[^ ]*" | cut -d'=' -f2)"
}

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

pull_docker_images() {
    docker pull "{{ replicated_docker_host }}/replicated/replicated-operator:{{ replicated_operator_tag }}{{ environment_tag_suffix }}"
}

tag_docker_images() {
    printf "Tagging replicated-operator image\n"
    # older docker versions require -f flag to move a tag from one image to another
    docker tag "{{ replicated_docker_host }}/replicated/replicated-operator:{{ replicated_operator_tag }}{{ environment_tag_suffix }}" "{{ replicated_docker_host }}/replicated/replicated-operator:current" 2>/dev/null \
        || docker tag -f "{{ replicated_docker_host }}/replicated/replicated-operator:{{ replicated_operator_tag }}{{ environment_tag_suffix }}" "{{ replicated_docker_host }}/replicated/replicated-operator:current"
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
    read_replicated_operator_opts "SELINUX_REPLICATED_DOMAIN"
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
            REPLICATED_OPERATOR_OPTS=$(echo "$REPLICATED_OPERATOR_OPTS" | sed -e 's/-e[[:blank:]]*PUBLIC_ADDRESS=[^[:blank:]]*//')
            REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS -e PUBLIC_ADDRESS=$PUBLIC_ADDRESS"
        fi
        return
    fi

    REPLICATED_OPERATOR_OPTS=""
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

    find_hostname
    REPLICATED_OPERATOR_OPTS=$REPLICATED_OPERATOR_OPTS" -e NODENAME=$SYS_HOSTNAME"
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
    cat > /etc/init/replicated-operator.conf <<-EOF
{% include 'upstart/replicated-operator.conf' %}
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

require64Bit
requireRootUser
detectLsbDist
detectInitSystem
detectInitSystemConfDir

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
            NO_PROXY=1
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
        *)
            echo "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

if [ "$ONLY_INSTALL_DOCKER" = "1" ]; then
    # no min if only installing docker
    installDocker "$PINNED_DOCKER_VERSION" "0.0.0"

    checkDockerDriver
    checkDockerStorageDriver
    exit 0
fi

if [ -z "$PRIVATE_ADDRESS" ]; then
    printf "Determining local address\n"
    discoverPrivateIp
fi

if [ -z "$PUBLIC_ADDRESS" ] && [ "$AIRGAP" -ne "1" ]; then
    printf "Determining service address\n"
    discoverPublicIp

    if [ -z "$PUBLIC_ADDRESS" ]; then
        read_replicated_operator_opts "PUBLIC_ADDRESS"
        if [ -n "$REPLICATED_OPTS_VALUE" ]; then
            PUBLIC_ADDRESS="$REPLICATED_OPTS_VALUE"
            printf "The installer will use service address '%s' (imported from $CONFDIR/replicated-operator 'PUBLIC_ADDRESS')\n" $PUBLIC_ADDRESS
        fi
    fi

    if [ -n "$PUBLIC_ADDRESS" ]; then
        shouldUsePublicIp
    else
        printf "The installer was unable to automatically detect the service IP address of this machine.\n"
        printf "Please enter the address or leave blank for unspecified.\n"
        promptForPublicIp
    fi
fi

if [ "$NO_PROXY" != "1" ]; then
    if [ -z "$PROXY_ADDRESS" ]; then
        discoverProxy
    fi

    if [ -z "$PROXY_ADDRESS" ]; then
        promptForProxy
    fi
fi

exportProxy

if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
    installDocker "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"

    checkDockerDriver
    checkDockerStorageDriver
fi

if [ -n "$PROXY_ADDRESS" ]; then
    requireDockerProxy
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

if [ -n "$PROXY_ADDRESS" ]; then
    checkDockerProxyConfig
fi

detectDockerGroupId
maybeCreateReplicatedUser

promptForDaemonEndpoint
promptForDaemonToken

if [ "$SKIP_DOCKER_PULL" = "1" ]; then
    printf "Skip docker pull flag detected, will not pull replicated-operator container\n"
elif [ "$AIRGAP" != "1" ]; then
    printf "Pulling latest replicated-operator container\n"
    pull_docker_images
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
