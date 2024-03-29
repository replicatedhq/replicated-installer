#!/bin/bash

#
# This script is meant for quick & easy install via:
#   'curl -sSL {{ replicated_install_url }}/docker | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/docker | sudo bash'
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
SKIP_OPERATOR_INSTALL=0
IS_MIGRATION=0
NO_PROXY=0
AIRGAP=0
ONLY_INSTALL_DOCKER=0
OPERATOR_TAGS="{{ operator_tags }}"
REPLICATED_USERNAME="{{ replicated_username }}"
UI_BIND_PORT="8800"
CONFIGURE_IPV6=0
{% if use_fast_timeouts %}
READ_TIMEOUT="-t 1"
FAST_TIMEOUTS=1
{%- endif %}
NO_CE_ON_EE="{{ no_ce_on_ee }}"
HARD_FAIL_ON_LOOPBACK="{{ hard_fail_on_loopback }}"
HARD_FAIL_ON_FIREWALLD="{{ hard_fail_on_firewalld }}"
ADDITIONAL_NO_PROXY=
FORCE_REPLICATED_DOWNGRADE=0
SKIP_PREFLIGHTS="{{ '1' if skip_preflights else '' }}"
IGNORE_PREFLIGHTS="{{ '1' if ignore_preflights else '' }}"
REGISTRY_ADDRESS_OVERRIDE=
REGISTRY_PATH_PREFIX=
DISABLE_REPLICATED_UI="{{ '1' if disable_replicated_ui else '' }}"
DISABLE_REPLICATED_HOST_NETWORKING="{{ '1' if disable_replicated_host_networking else '' }}"
RELEASE_SEQUENCE="{{ release_sequence }}"
RELEASE_PATCH_SEQUENCE="{{ release_patch_sequence }}"

CHANNEL_CSS={% if channel_css %}
set +e
read -r -d '' CHANNEL_CSS << CHANNEL_CSS_EOM
{{ channel_css }}
CHANNEL_CSS_EOM
set -e
{%- endif %}

TERMS={% if terms %}
set +e
read -r -d '' TERMS << TERMS_EOM
{{ terms }}
TERMS_EOM
set -e
{%- endif %}

{% include 'common/common.sh' %}
{% include 'common/log.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/system.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/docker-install.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/cli-script.sh' %}
{% include 'common/alias.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/proxy.sh' %}
{% include 'common/airgap.sh' %}
{% include 'common/selinux.sh' %}
{% include 'common/firewall.sh' %}
{% include 'common/registryproxy.sh' %}
{% include 'preflights/index.sh' %}

ask_for_registry_name_ipv6() {
  line=
  while [[ "$line" == "" ]]; do
    printf "Enter a hostname that resolves to $PRIVATE_ADDRESS: "
    prompt
    line=$PROMPT_RESULT
  done

  # check if it's resolvable.  it might not be ping-able.
  if ping6 -c 1 $line 2>&1 | grep -q "unknown host"; then
      echo -e >&2 "${RED}${line} cannot be resolved${NC}"
      exit 1
  fi
  REGISTRY_ADVERTISE_ADDRESS="$line"
  printf "Replicated will use \"%s\" to communicate with this server.\n" "${REGISTRY_ADVERTISE_ADDRESS}"
}

discoverPrivateIp() {
    if [ -n "$PRIVATE_ADDRESS" ]; then
        if [ "$NO_PRIVATE_ADDRESS_PROMPT" != "1" ]; then
            printf "Validating local address supplied in parameter: '%s'\n" $PRIVATE_ADDRESS
            if ! isValidPrivateIp "$PRIVATE_ADDRESS" ; then
                promptForPrivateIp
                return
            fi
        fi
        printf "The installer will use local address '%s' (from parameter)\n" $PRIVATE_ADDRESS
        return
    fi

    readReplicatedConf "LocalAddress"
    if [ -n "$REPLICATED_CONF_VALUE" ]; then
        PRIVATE_ADDRESS="$REPLICATED_CONF_VALUE"
        if [ "$NO_PRIVATE_ADDRESS_PROMPT" != "1" ]; then
            printf "Validating local address found in /etc/replicated.conf: '%s'\n" $PRIVATE_ADDRESS
            if ! isValidPrivateIp "$PRIVATE_ADDRESS" ; then
                promptForPrivateIp
                return
            fi
        fi
        printf "The installer will use local address '%s' (imported from /etc/replicated.conf 'LocalAddress')\n" $PRIVATE_ADDRESS
        return
    fi

    promptForPrivateIp
}

configure_docker_ipv6() {
  case "$INIT_SYSTEM" in
      systemd)
        if ! grep -q "^ExecStart.*--ipv6" /lib/systemd/system/docker.service; then
            sed -i 's/ExecStart=\/usr\/bin\/dockerd/ExecStart=\/usr\/bin\/dockerd --ipv6/' /lib/systemd/system/docker.service
            RESTART_DOCKER=1
        fi
        ;;
      upstart|sysvinit)
        if [ -e /etc/sysconfig/docker ]; then # CentOS 6
          if ! grep -q "^other_args=.*--ipv6" /etc/sysconfig/docker; then
              sed -i 's/other_args=\"/other_args=\"--ipv6/' /etc/sysconfig/docker
              RESTART_DOCKER=1
          fi
        fi

        if [ -e /etc/default/docker ]; then # Everything NOT CentOS 6
          if ! grep -q "^DOCKER_OPTS=" /etc/default/docker; then
              echo 'DOCKER_OPTS="--ipv6"' >> /etc/default/docker
              RESTART_DOCKER=1
          fi
        fi
        ;;
      *)
        return 0
        ;;
  esac
}

DAEMON_TOKEN=
get_daemon_token() {
    if [ -n "$DAEMON_TOKEN" ]; then
        return
    fi

    readReplicatedOpts "DAEMON_TOKEN"
    if [ -n "$REPLICATED_OPTS_VALUE" ]; then
        DAEMON_TOKEN="$REPLICATED_OPTS_VALUE"
        return
    fi

    readReplicatedConf "DaemonToken"
    if [ -n "$REPLICATED_CONF_VALUE" ]; then
        DAEMON_TOKEN="$REPLICATED_CONF_VALUE"
        return
    fi

    getGuid
    DAEMON_TOKEN="$GUID_RESULT"
}

SELINUX_REPLICATED_DOMAIN=
CUSTOM_SELINUX_REPLICATED_DOMAIN=0
get_selinux_replicated_domain() {
    # may have been set by command line argument
    if [ -n "$SELINUX_REPLICATED_DOMAIN" ]; then
        CUSTOM_SELINUX_REPLICATED_DOMAIN=1
        return
    fi

    # if previously set to a custom domain it will be in REPLICATED_OPTS
    readReplicatedOpts "SELINUX_REPLICATED_DOMAIN"
    if [ -n "$REPLICATED_OPTS_VALUE" ]; then
        SELINUX_REPLICATED_DOMAIN="$REPLICATED_OPTS_VALUE"
        CUSTOM_SELINUX_REPLICATED_DOMAIN=1
        return
    fi

    # default if unset
    SELINUX_REPLICATED_DOMAIN=spc_t
}

remove_docker_containers() {
    # try twice because of aufs error "Unable to remove filesystem"
    if docker inspect replicated &>/dev/null; then
        set +e
        docker rm -f replicated
        _status=$?
        set -e
        if [ "$_status" -ne "0" ]; then
            if docker inspect replicated &>/dev/null; then
                printf "Failed to remove replicated container, retrying\n"
                sleep 1
                docker rm -f replicated
            fi
        fi
    fi
    if docker inspect replicated-ui &>/dev/null; then
        set +e
        docker rm -f replicated-ui
        _status=$?
        set -e
        if [ "$_status" -ne "0" ]; then
            if docker inspect replicated-ui &>/dev/null; then
                printf "Failed to remove replicated-ui container, retrying\n"
                sleep 1
                docker rm -f replicated-ui
            fi
        fi
    fi
}

tag_docker_images() {
    printf "Tagging replicated and replicated-ui images\n"
    # older docker versions require -f flag to move a tag from one image to another
    docker tag "$REPLICATED_REGISTRY_PREFIX/replicated:{{ replicated_tag }}{{ environment_tag_suffix }}" "$REPLICATED_REGISTRY_PREFIX/replicated:current" \
        || docker tag -f "$REPLICATED_REGISTRY_PREFIX/replicated:{{ replicated_tag }}{{ environment_tag_suffix }}" "$REPLICATED_REGISTRY_PREFIX/replicated:current"
    docker tag "$REPLICATED_REGISTRY_PREFIX/replicated-ui:{{ replicated_ui_tag }}{{ environment_tag_suffix }}" "$REPLICATED_REGISTRY_PREFIX/replicated-ui:current" \
        || docker tag -f "$REPLICATED_REGISTRY_PREFIX/replicated-ui:{{ replicated_ui_tag }}{{ environment_tag_suffix }}" "$REPLICATED_REGISTRY_PREFIX/replicated-ui:current"
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

REPLICATED_OPTS=
build_replicated_opts() {
    # See https://github.com/golang/go/blob/23173fc025f769aaa9e19f10aa0f69c851ca2f3b/src/crypto/x509/root_linux.go
    # CentOS 6/7, RHEL 7
    # Fedora/RHEL 6 (this is a link on Centos 6/7)
    # OpenSUSE
    # OpenELEC
    # Debian/Ubuntu/Gentoo etc. This is where OpenSSL will look. It's moved to the bottom because this exists as a link on some other platforms
    set \
        "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem" \
        "/etc/pki/tls/certs/ca-bundle.crt" \
        "/etc/ssl/ca-bundle.pem" \
        "/etc/pki/tls/cacert.pem" \
        "/etc/ssl/certs/ca-certificates.crt"

    for cert_file do
        if [ -f "$cert_file" ]; then
            REPLICATED_TRUSTED_CERT_MOUNT="-v ${cert_file}:/etc/ssl/certs/ca-certificates.crt"
            break
        fi
    done

    if [ -n "$REPLICATED_OPTS" ]; then
        REPLICATED_OPTS=$(echo "$REPLICATED_OPTS" | sed -e 's/-e[[:blank:]]*HTTP_PROXY=[^[:blank:]]*//g')
        REPLICATED_OPTS=$(echo "$REPLICATED_OPTS" | sed -e 's/-e[[:blank:]]*HTTPS_PROXY=[^[:blank:]]*//g')
        if [ -n "$PROXY_ADDRESS" ]; then
            REPLICATED_OPTS="$REPLICATED_OPTS -e HTTP_PROXY=$PROXY_ADDRESS -e HTTPS_PROXY=$PROXY_ADDRESS"
        fi
        REPLICATED_OPTS=$(echo "$REPLICATED_OPTS" | sed -e 's/-e[[:blank:]]*NO_PROXY=[^[:blank:]]*//g')
        if [ -n "$NO_PROXY_ADDRESSES" ]; then
           REPLICATED_OPTS="$REPLICATED_OPTS -e NO_PROXY=$NO_PROXY_ADDRESSES"
        fi
        REPLICATED_OPTS=$(echo "$REPLICATED_OPTS" | sed -e 's/-e[[:blank:]]*REGISTRY_ADVERTISE_ADDRESS=[^[:blank:]]*//g')
        if [ -n "$REGISTRY_ADVERTISE_ADDRESS" ]; then
            REPLICATED_OPTS="$REPLICATED_OPTS -e REGISTRY_ADVERTISE_ADDRESS=$REGISTRY_ADVERTISE_ADDRESS"
        fi
        REPLICATED_OPTS=$(echo "$REPLICATED_OPTS" | sed -e 's/-e[[:blank:]]*DISABLE_HOST_NETWORKING=[^[:blank:]]*//g')
        if [ "$DISABLE_REPLICATED_HOST_NETWORKING" = "1" ]; then
            REPLICATED_OPTS="$REPLICATED_OPTS -e DISABLE_HOST_NETWORKING=true"
        fi
        # if '--read-only' is not present, add it
        if ! echo "$REPLICATED_OPTS" | grep -q -- '--read-only'; then # -- in grep because otherwise the search string is interpreted as a flag
            if [ -n "$REPLICATED_DOCKER_READONLY_FLAG" ]; then
                REPLICATED_OPTS="$REPLICATED_OPTS $REPLICATED_DOCKER_READONLY_FLAG"
            fi
        fi

        if [ -n "$REPLICATED_UI_OPTS" ]; then
            # if '--read-only' is not present, add it
            if ! echo "$REPLICATED_UI_OPTS" | grep -q -- '--read-only'; then # -- in grep because otherwise the search string is interpreted as a flag
                if [ -n "$REPLICATED_DOCKER_READONLY_FLAG" ]; then
                    REPLICATED_UI_OPTS="$REPLICATED_UI_OPTS $REPLICATED_DOCKER_READONLY_FLAG"
                fi
            fi
        else
            REPLICATED_UI_OPTS=" $REPLICATED_DOCKER_READONLY_FLAG"
        fi
        return
    fi

    REPLICATED_OPTS=" $REPLICATED_DOCKER_READONLY_FLAG"

{% if customer_base_url_override %}
    REPLICATED_OPTS="$REPLICATED_OPTS -e MARKET_BASE_URL={{ customer_base_url_override }}"
{% elif replicated_env == "staging" %}
    REPLICATED_OPTS="$REPLICATED_OPTS -e MARKET_BASE_URL=https://api.staging.replicated.com/market"
{%- endif %}
{% if replicated_env == "staging" %}
    REPLICATED_OPTS="$REPLICATED_OPTS -e DATA_BASE_URL=https://data.staging.replicated.com/market -e VENDOR_REGISTRY=registry.staging.replicated.com -e REPLICATED_IMAGE_TAG_SUFFIX=.staging"
{%- endif %}
{% if replicated_install_url != "https://get.replicated.com" %}
    REPLICATED_OPTS="$REPLICATED_OPTS -e INSTALLER_URL={{ replicated_install_url }}"
{%- endif %}

    if [ -n "$PROXY_ADDRESS" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e HTTP_PROXY=$PROXY_ADDRESS -e HTTPS_PROXY=$PROXY_ADDRESS -e NO_PROXY=$NO_PROXY_ADDRESSES"
    fi
    if [ -n "$REGISTRY_ADVERTISE_ADDRESS" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e REGISTRY_ADVERTISE_ADDRESS=$REGISTRY_ADVERTISE_ADDRESS"
    fi
    if [ "$SKIP_OPERATOR_INSTALL" != "1" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e DAEMON_TOKEN=$DAEMON_TOKEN"
    fi
    if [ -n "$LOG_LEVEL" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e LOG_LEVEL=$LOG_LEVEL"
    else
        REPLICATED_OPTS="$REPLICATED_OPTS -e LOG_LEVEL=info"
    fi
    if [ "$AIRGAP" = "1" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e AIRGAP=true"
    fi
    if [ -n "$RELEASE_SEQUENCE" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e RELEASE_SEQUENCE=$RELEASE_SEQUENCE"
    fi
    if [ -n "$RELEASE_PATCH_SEQUENCE" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e RELEASE_PATCH_SEQUENCE=$RELEASE_PATCH_SEQUENCE"
    fi
    if [ "$CUSTOM_SELINUX_REPLICATED_DOMAIN" = "1" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e SELINUX_REPLICATED_DOMAIN=$SELINUX_REPLICATED_DOMAIN"
    fi

    find_hostname
    REPLICATED_OPTS="$REPLICATED_OPTS -e NODENAME=$SYS_HOSTNAME"

    REPLICATED_UI_OPTS=" $REPLICATED_DOCKER_READONLY_FLAG"
    if [ -n "$LOG_LEVEL" ]; then
        REPLICATED_UI_OPTS="$REPLICATED_UI_OPTS -e LOG_LEVEL=$LOG_LEVEL"
    fi

    dockerGetLoggingDriver
    if [ "$DOCKER_LOGGING_DRIVER" = "json-file" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS --log-opt max-size=50m --log-opt max-file=3"
        REPLICATED_UI_OPTS="$REPLICATED_UI_OPTS --log-opt max-size=50m --log-opt max-file=3"
    fi

    if [ "$DISABLE_REPLICATED_HOST_NETWORKING" = "1" ]; then
        REPLICATED_OPTS="$REPLICATED_OPTS -e DISABLE_HOST_NETWORKING=true"
    fi
}

write_replicated_configuration() {
    cat > $CONFDIR/replicated <<-EOF
RELEASE_CHANNEL={{ channel_name }}
PRIVATE_ADDRESS=$PRIVATE_ADDRESS
SKIP_OPERATOR_INSTALL=$SKIP_OPERATOR_INSTALL
REPLICATED_OPTS="$REPLICATED_OPTS"
REPLICATED_UI_OPTS="$REPLICATED_UI_OPTS"
EOF
}

write_systemd_services() {
    cat > /etc/systemd/system/replicated.service <<-EOF
{% include 'systemd/replicated.service' %}
EOF

    if [ "$DISABLE_REPLICATED_UI" != "1" ]; then
        cat > /etc/systemd/system/replicated-ui.service <<-EOF
{% include 'systemd/replicated-ui.service' %}
EOF
    fi

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

    cat > /etc/init/replicated.conf <<-EOF
{% include 'upstart/replicated.conf' %}
EOF
    cat > /etc/init/replicated-stop.conf <<-EOF
{% include 'upstart/replicated-stop.conf' %}
EOF

    if [ "$DISABLE_REPLICATED_UI" != "1" ]; then
        cat > /etc/init/replicated-ui.conf <<-EOF
{% include 'upstart/replicated-ui.conf' %}
EOF
        cat > /etc/init/replicated-ui-stop.conf <<-EOF
{% include 'upstart/replicated-ui-stop.conf' %}
EOF
    fi
}

write_sysvinit_services() {
    cat > /etc/init.d/replicated <<-EOF
{% include 'sysvinit/replicated' %}
EOF
    chmod +x /etc/init.d/replicated

    if [ "$DISABLE_REPLICATED_UI" != "1" ]; then
        cat > /etc/init.d/replicated-ui <<-EOF
{% include 'sysvinit/replicated-ui' %}
EOF
        chmod +x /etc/init.d/replicated-ui
    fi
}

stop_systemd_services() {
    if systemctl status replicated &>/dev/null; then
        systemctl stop replicated
    fi
    if systemctl status replicated-ui &>/dev/null; then
        systemctl stop replicated-ui
    fi
}

start_systemd_services() {
    systemctl enable replicated
    systemctl start replicated

    if [ "$DISABLE_REPLICATED_UI" != "1" ]; then
        systemctl enable replicated-ui
        systemctl start replicated-ui
    fi
}

stop_upstart_services() {
    if status replicated &>/dev/null && ! status replicated 2>/dev/null | grep -q "stop"; then
        stop replicated
    fi
    if status replicated-ui &>/dev/null && ! status replicated-ui 2>/dev/null | grep -q "stop"; then
        stop replicated-ui
    fi
}

start_upstart_services() {
    start replicated
    start replicated-ui
}

stop_sysvinit_services() {
    if service replicated status &>/dev/null; then
        service replicated stop
    fi
    if service replicated-ui status &>/dev/null; then
        service replicated-ui stop
    fi
}

start_sysvinit_services() {
    # TODO: what about chkconfig
    update-rc.d replicated stop 20 0 1 6 . start 20 2 3 4 5 .
    update-rc.d replicated enable
    service replicated start

    if [ "$DISABLE_REPLICATED_UI" != "1" ]; then
        update-rc.d replicated-ui stop 20 0 1 6 . start 20 2 3 4 5 .
        update-rc.d replicated-ui enable
        service replicated-ui start
    fi
}

install_operator() {
    prefix="{{ '/' + channel_name if channel_name != 'stable' else '' }}"
    if [ "$AIRGAP" != "1" ]; then
        getUrlCmd
        echo -e "${GREEN}Installing local operator with command:"
        echo -e "${URLGET_CMD} {{ replicated_install_url }}${prefix}/operator?replicated_operator_tag={{ replicated_operator_tag }}${NC}"
        ${URLGET_CMD} "{{ replicated_install_url }}${prefix}/operator?replicated_operator_tag={{ replicated_operator_tag }}" > "$REPLICATED_TEMP_DIR/operator_install.sh"
    fi
    _private_address_with_brackets="$PRIVATE_ADDRESS"
    if [ "$DISABLE_REPLICATED_HOST_NETWORKING" = "1" ]; then
        _private_address_with_brackets="$DOCKER0_GATEWAY_IP"
    fi
    if isValidIpv6 "$_private_address_with_brackets"; then
        _private_address_with_brackets="[$_private_address_with_brackets]"
    fi
    opts="no-docker skip-preflights daemon-endpoint=$_private_address_with_brackets:9879 daemon-token=$DAEMON_TOKEN private-address=$PRIVATE_ADDRESS tags=$OPERATOR_TAGS"
    if [ -n "$PUBLIC_ADDRESS" ]; then
        opts=$opts" public-address=$PUBLIC_ADDRESS"
    elif [ "$NO_PUBLIC_ADDRESS" = "1" ]; then
        opts=$opts" no-public-address"
    fi
    if [ -n "$PROXY_ADDRESS" ]; then
        opts=$opts" http-proxy=$PROXY_ADDRESS additional-no-proxy=$NO_PROXY_ADDRESSES"
    else
        opts=$opts" no-proxy"
    fi
    if [ -z "$READ_TIMEOUT" ]; then
        opts=$opts" no-auto"
    fi
    if [ "$AIRGAP" = "1" ]; then
        opts=$opts" airgap"
    fi
    if [ "$SKIP_DOCKER_PULL" = "1" ]; then
        opts=$opts" skip-pull"
    fi
    if [ -n "$LOG_LEVEL" ]; then
        opts=$opts" log-level=$LOG_LEVEL"
    fi
    if [ "$CUSTOM_SELINUX_REPLICATED_DOMAIN" = "1" ]; then
        opts=$opts" selinux-replicated-domain=$SELINUX_REPLICATED_DOMAIN"
    fi
    if [ -n "$FAST_TIMEOUTS" ]; then
        opts=$opts" fast-timeouts"
    fi
    if [ -n "$NO_CE_ON_EE" ]; then
        opts=$opts" no-ce-on-ee"
    fi
    if [ "$BYPASS_FIREWALLD_WARNING" = "1" ]; then
        opts=$opts" bypass-firewalld-warning"
    fi
    if [ -n "$REGISTRY_ADDRESS_OVERRIDE" ]; then
        opts=$opts" registry-address-override=$REGISTRY_ADDRESS_OVERRIDE"
    fi
    if [ -n "$REGISTRY_PATH_PREFIX" ]; then
        opts=$opts" registry-path-prefix=$REGISTRY_PATH_PREFIX"
    fi
    if [ "$DISABLE_REPLICATED_HOST_NETWORKING" = "1" ]; then
        # we still bind the registry to the host network
        opts=$opts" daemon-registry-address=$DOCKER0_GATEWAY_IP:9874"
    fi

    # When this script is piped into bash as stdin, apt-get will eat the remaining parts of this script,
    # preventing it from being executed.  So using /dev/null here to change stdin for the docker script.
    if [ "$AIRGAP" = "1" ]; then
        bash ./operator_install.sh $opts < /dev/null
    else
        bash "$REPLICATED_TEMP_DIR/operator_install.sh" $opts < /dev/null
    fi
}

outro() {
    warn_if_selinux
    if [ "$DISABLE_REPLICATED_UI" != "1" ]; then
        if [ -z "$PUBLIC_ADDRESS" ]; then
            PUBLIC_ADDRESS="<this_server_address>"
        fi
        printf "To continue the installation, visit the following URL in your browser:\n\n  http://%s:$UI_BIND_PORT\n" "$PUBLIC_ADDRESS"
    fi
    if ! commandExists "replicated"; then
        printf "\nTo create an alias for the replicated cli command run the following in your current shell or log out and log back in:\n\n  source /etc/replicated.alias\n"
    fi
    printf "\n"
}


################################################################################
# Execution starts here
################################################################################

export DEBIAN_FRONTEND=noninteractive

if replicated12Installed; then
    echo -e >&2 "${RED}Existing 1.2 install detected; please back up and run migration script before installing.${NC}"
    echo -e >&2 "${RED}Instructions at https://help.replicated.com/docs/native/customer-installations/upgrading/${NC}"
    exit 1
fi

maybeCreateTempDir
require64Bit
requireRootUser
detectLsbDist
detectInitSystem
detectInitSystemConfDir
getReplicatedRegistryPrefix "$REPLICATED_VERSION"
getReplicatedReadonlyDockerFlag "$REPLICATED_VERSION"

mkdir -p /var/lib/replicated/branding
chmod a+x /var/lib/replicated/branding
if [ -n "$CHANNEL_CSS" ]; then
    echo "$CHANNEL_CSS" | base64 --decode > /var/lib/replicated/branding/channel.css
fi
if [ -n "$TERMS" ]; then
    echo "$TERMS" | base64 --decode > /var/lib/replicated/branding/terms.json
fi

# read existing replicated opts values
if [ -f $CONFDIR/replicated ]; then
    # shellcheck source=replicated-default
    . $CONFDIR/replicated
fi
if [ -f $CONFDIR/replicated-operator ]; then
    # support for the old installation script that used REPLICATED_OPTS for
    # operator
    tmp_replicated_opts="$REPLICATED_OPTS"
    # shellcheck source=replicated-operator-default
    . $CONFDIR/replicated-operator
    REPLICATED_OPTS="$tmp_replicated_opts"
fi

# override these values with command line flags
while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
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
        no-operator|no_operator)
            SKIP_OPERATOR_INSTALL=1
            ;;
        is-migration|is_migration)
            IS_MIGRATION=1
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
            # airgap implies "skip docker"
            AIRGAP=1
            SKIP_DOCKER_INSTALL=1
            ;;
        no-auto|no_auto)
            READ_TIMEOUT=
            ;;
        daemon-token|daemon_token)
            DAEMON_TOKEN="$_value"
            ;;
        tags)
            OPERATOR_TAGS="$_value"
            ;;
        docker-version|docker_version)
            PINNED_DOCKER_VERSION="$_value"
            ;;
        ui-bind-port|ui_bind_port)
            UI_BIND_PORT="$_value"
            ;;
        registry-advertise-address|registry_advertise_address)
            REGISTRY_ADVERTISE_ADDRESS="$_value"
            ;;
        release-sequence|release_sequence)
            RELEASE_SEQUENCE="$_value"
            ;;
        release-patch-sequence|release_patch_sequence)
            RELEASE_PATCH_SEQUENCE="$_value"
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
        force-replicated-downgrade|force_replicated_downgrade)
            FORCE_REPLICATED_DOWNGRADE=1
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
        disable-replicated-ui|disable_replicated_ui)
            DISABLE_REPLICATED_UI=1
            ;;
        disable-replicated-host-networking|disable_replicated_host_networking)
            # DISABLE_REPLICATED_HOST_NETWORKING supported in replicated 2.49.0+
            DISABLE_REPLICATED_HOST_NETWORKING=1
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

if [ "$FORCE_REPLICATED_DOWNGRADE" != "1" ] && isReplicatedDowngrade "$REPLICATED_VERSION"; then
    replicated2Version
    echo -e >&2 "${RED}Current Replicated version $INSTALLED_REPLICATED_VERSION is greater than the proposed version $REPLICATED_VERSION.${NC}"
    echo -e >&2 "${RED}To downgrade Replicated re-run the script with the force-replicated-downgrade flag.${NC}"
    exit 1
fi

checkFirewalld

if [ "$ONLY_INSTALL_DOCKER" = "1" ]; then
    # no min if only installing docker
    installDocker "$PINNED_DOCKER_VERSION" "0.0.0"

    checkDockerDriver
    checkDockerStorageDriver "$HARD_FAIL_ON_LOOPBACK"
    exit 0
fi

printf "Determining local address\n"
discoverPrivateIp

if [ -z "$PUBLIC_ADDRESS" ] && [ "$AIRGAP" != "1" ] && [ "$NO_PUBLIC_ADDRESS" != "1" ]; then
    printf "Determining service address\n"
    discoverPublicIp

    # check that we will eventually run the operator install script
    if [ "$SKIP_OPERATOR_INSTALL" != "1" ] && [ "$IS_MIGRATION" != "1" ]; then
        # Even though this script does not use PUBLIC_ADDRESS, we must prompt prior to replicated
        # operator installation to minimize the delay between starting replicated and the operator for
        # automated installs. If the operator takes too long to start then the app start will fail.
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
fi

maybePromptForArtifactoryAuth
configureRegistryProxyAddressOverride
maybeWriteRegistryProxyConfig

if [ "$NO_PROXY" != "1" ]; then
    if [ -z "$PROXY_ADDRESS" ]; then
        discoverProxy
    fi

    if [ -z "$PROXY_ADDRESS" ] && [ "$AIRGAP" != "1" ]; then
        promptForProxy
    fi

    if [ -n "$PROXY_ADDRESS" ]; then
        getNoProxyAddresses "$PRIVATE_ADDRESS"
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

get_docker0_gateway_ip

if [ -n "$PROXY_ADDRESS" ]; then
    requireDockerProxy
fi

if [ "$CONFIGURE_IPV6" = "1" ] && [ "$DID_INSTALL_DOCKER" = "1" ]; then
    configure_docker_ipv6
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

if [ -n "$PROXY_ADDRESS" ]; then
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

ensureReplicatedConfReadable

get_daemon_token

if [ "$SKIP_DOCKER_PULL" = "1" ]; then
    printf "Skip docker pull flag detected, will not pull replicated and replicated-ui images\n"
elif [ "$AIRGAP" != "1" ]; then
    printf "Pulling replicated and replicated-ui images\n"
    pullReplicatedImages
else
    printf "Loading replicated and replicated-ui images from package\n"
    airgapLoadReplicatedImages
    printf "Loading replicated debian, command, statsd-graphite, and premkit images from package\n"
    airgapLoadSupportImages

    airgapMaybeLoadSupportBundle
    airgapMaybeLoadRetraced
fi

tag_docker_images

printf "Stopping replicated and replicated-ui service\n"
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

printf "Installing replicated and replicated-ui service\n"

REPLICATED_PORT_RANGE="-p {{ replicated_port_range }}"
if [ "$DISABLE_REPLICATED_HOST_NETWORKING" = "1" ]; then
    if [ -z "$REGISTRY_ADVERTISE_ADDRESS" ]; then
        REGISTRY_ADVERTISE_ADDRESS="$DOCKER0_GATEWAY_IP:9874"
    fi
    REPLICATED_PORT_RANGE="-p $DOCKER0_GATEWAY_IP:9874-9879:9874-9879/tcp"
fi

get_selinux_replicated_domain
get_selinux_replicated_domain_label
build_replicated_opts
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

printf "Starting replicated and replicated-ui service\n"
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

printf "Installing replicated command alias\n"
installCliFile "sudo docker exec" "replicated"
installAliasFile

if [ "$SKIP_OPERATOR_INSTALL" != "1" ] && [ "$IS_MIGRATION" != "1" ]; then
    # we write this value to the opts file so if you didn't install it the first
    # time it will not install when updating
    printf "Installing local operator\n"
    install_operator
fi

outro
exit 0
