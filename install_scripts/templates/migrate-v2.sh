#!/bin/bash

#
# This script is meant for quick & easy install via:
#   'curl -sSL {{ replicated_install_url }}/migrate-v2 | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/migrate-v2 | sudo bash'
#

set -e

READ_TIMEOUT=
READ_TIMEOUT_MSG="timeout... continuing"
SKIP_DOCKER_INSTALL=0
NO_PROXY=0
REPLICATED_INSTALL_URL="{{ replicated_install_url }}"
RELEASE_CHANNEL="stable"

command_exists() {
    command -v "$@" > /dev/null 2>&1
}

LSB_DIST=
detect_lsb_dist() {
  _dist=
  if [ -r /etc/os-release ]; then
      _dist="$(. /etc/os-release && echo "$ID")"
      _version="$(. /etc/os-release && echo "$VERSION_ID")"
  elif [ -r /etc/centos-release ]; then
      # this is a hack for CentOS 6
      _dist="$(cat /etc/centos-release | cut -d" " -f1)"
      _version="$(cat /etc/centos-release | cut -d" " -f3 | cut -d "." -f1)"
  fi
  if [ -n "$_dist" ]; then
      _dist="$(echo "$_dist" | tr '[:upper:]' '[:lower:]')"
      case "$_dist" in
          ubuntu)
              oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
              [ $1 -ge 12 ] && LSB_DIST=$_dist
              ;;
          debian)
              oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
              [ $1 -ge 7 ] && LSB_DIST=$_dist
              ;;
          fedora)
              oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
              [ $1 -ge 21 ] && LSB_DIST=$_dist
              ;;
          rhel)
              oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
              [ $1 -ge 7 ] && LSB_DIST=$_dist
              ;;
          centos)
              oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
              [ $1 -ge 6 ] && LSB_DIST=$_dist
              ;;
          amzn)
              [ "$_version" = "2017.03" ] || [ "$_version" = "2017.09" ] || \
              [ "$_version" = "2016.03" ] || [ "$_version" = "2016.09" ] || \
              [ "$_version" = "2015.03" ] || [ "$_version" = "2015.09" ] || \
              [ "$_version" = "2014.03" ] || [ "$_version" = "2014.09" ] && \
              LSB_DIST=$_dist
              # TODO: docker install fails on amzn 2014.03
              # as of now its possible to install docker manually and run this
              # script with "| sudo bash -s no-docker"
              ;;
          sles)
              oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
              [ $1 -ge 12 ] && LSB_DIST=$_dist
              ;;
      esac
  fi
  return 0
}

detect_init_system() {
    if [[ "`/sbin/init --version 2>/dev/null`" =~ upstart ]]; then
        INIT_SYSTEM=upstart
    elif [[ "`systemctl 2>/dev/null`" =~ -\.mount ]]; then
        INIT_SYSTEM=systemd
    elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
        INIT_SYSTEM=sysvinit
    else
        echo >&2 "Error: failed to detect init system or unsupported."
        exit 1
    fi
}

read_replicated_conf() {
    unset REPLICATED_CONF_VALUE
    if [ -f /etc/replicated.conf ]; then
        REPLICATED_CONF_VALUE=$(cat /etc/replicated.conf | grep -o "\"$1\":\s*\"[^\"]*" | sed "s/\"$1\":\s*\"//") || true
    fi
}

ask_for_proxy() {
    while true
    do
        set +e
        read $READ_TIMEOUT -p "Does this machine require a proxy to access the Internet? (y/N): " wants_proxy < /dev/tty
        _err=$?
        set -e
        if [ "$_err" -ge "128" ]; then
            echo $READ_TIMEOUT_MSG
            wants_proxy=""
        fi
        case $wants_proxy in
            "")
                break;;
            [nN]*)
                break;;
            [yY]*)
                set +e
                read $READ_TIMEOUT -p "Enter desired HTTP proxy address: " chosen < /dev/tty
                set -e
                if [ -n "$chosen" ]; then
                    PROXY_ADDRESS="$chosen"
                    printf "The installer will use the proxy at '%s'\n" "$PROXY_ADDRESS"
                fi
                break;;
            *)
                echo "Please choose y or n.";;
        esac
    done
}

discover_proxy() {
    read_replicated_conf "HttpProxy"
    if [ -n "$REPLICATED_CONF_VALUE" ]; then
        PROXY_ADDRESS="$REPLICATED_CONF_VALUE"
        printf "The installer will use the proxy at '%s' (imported from /etc/replicated.conf 'HttpProxy')\n" $PROXY_ADDRESS
        return
    fi

    if [ -n "$HTTP_PROXY" ]; then
        PROXY_ADDRESS="$HTTP_PROXY"
        printf "The installer will use the proxy at '%s' (imported from env var 'HTTP_PROXY')\n" $PROXY_ADDRESS
        return
    elif [ -n "$http_proxy" ]; then
        PROXY_ADDRESS="$http_proxy"
        printf "The installer will use the proxy at '%s' (imported from env var 'http_proxy')\n" $PROXY_ADDRESS
        return
    elif [ -n "$HTTPS_PROXY" ]; then
        PROXY_ADDRESS="$HTTPS_PROXY"
        printf "The installer will use the proxy at '%s' (imported from env var 'HTTPS_PROXY')\n" $PROXY_ADDRESS
        return
    elif [ -n "$https_proxy" ]; then
        PROXY_ADDRESS="$https_proxy"
        printf "The installer will use the proxy at '%s' (imported from env var 'https_proxy')\n" $PROXY_ADDRESS
        return
    fi
}

require_docker_proxy() {
    if [[ "$(docker info 2>/dev/null)" = *"Http Proxy:"* ]]; then
        return
    fi

    printf "It does not look like Docker is set up with http proxy enabled.\n"
    while true
    do
        set +e
        read $READ_TIMEOUT -p "Do you want to proceed anyway? (y/N) " allow < /dev/tty
        _err=$?
        set -e
        if [ "$_err" -ge "128" ]; then
            echo $READ_TIMEOUT_MSG
            allow=""
        fi
        case $allow in
            "" )
                exit_on_require_docker;;
            [nN]* )
                exit_on_require_docker;;
            [yY]* )
                break;;
            *)
                echo "Please choose y or n.";;
        esac
    done
}

exit_on_require_docker() {
    echo >&2 "Please manually configure your Docker with environment HTTP_PROXY."
    exit 1
}

needs_login() {
    if [[ $($CMD_PREFIX apps) = "Error: You are not logged in."* ]]; then
        echo >&2 "Error: please log into Replicated CLI using the following command before executing this script:"
        echo >&2 ""
        echo >&2 "  sudo replicated login"
        echo >&2 ""
        exit 1
    fi
}

get_app() {
    app=$($CMD_PREFIX apps | awk '{ if (NR == 2) { print } }')
    if [ -z "$app" ]; then
        echo >&2 "Error: no app"
        exit 1
    fi

    APP_ID=$(echo "$app" | awk 'BEGIN { FS = "     *" } { print $1 }')
    APP_NAME=$(echo "$app" | awk 'BEGIN { FS = "     *" } { print $2 }')
}

is_app_stopped() {
    _app=$($CMD_PREFIX app $1)
    _run_status=$(echo "$_app" | grep -o '"RunStatus":\s*"[^"]*' | sed 's/"RunStatus":\s*"//') || true
    _run_status_next=$(echo "$_app" | grep -o '"RunStatusNext":\s*"[^"]*' | sed 's/"RunStatusNext":\s*"//') || true
    if [ "$_run_status" = "Stopped" ] && [ "$_run_status_next" = "Stopped" ]; then
        return 0
    else
        return 1
    fi
}

stop_app() {
    if is_app_stopped $APP_ID; then
        return
    fi

    $CMD_PREFIX app $APP_ID stop
    for i in {1..10}; do
        if is_app_stopped $APP_ID; then
            return
        fi
        sleep 5
    done

    echo "Unable to stop the app. Attempting a force stop..."
    $CMD_PREFIX app $APP_ID stop -f
    for i in {1..10}; do
        if is_app_stopped $APP_ID; then
            return
        fi
        sleep 5
    done

    echo >&2 "Error: unable to stop the app, manually stop the app and try again"
    exit 1
}

get_replicated_v1_install_script_cmd() {
    REPLICATED_V1_INSTALL_SCRIPT_CMD=
    if command_exists "curl"; then
        REPLICATED_V1_INSTALL_SCRIPT_CMD="curl -sSL"
        if [ -n "$PROXY_ADDRESS" ]; then
            REPLICATED_V1_INSTALL_SCRIPT_CMD=$REPLICATED_V1_INSTALL_SCRIPT_CMD" -x $PROXY_ADDRESS"
        fi
    else
        REPLICATED_V1_INSTALL_SCRIPT_CMD="wget -qO-"
    fi
    if [ "$RELEASE_CHANNEL" = "stable" ]; then
        REPLICATED_V1_INSTALL_SCRIPT_CMD=$REPLICATED_V1_INSTALL_SCRIPT_CMD" $REPLICATED_INSTALL_URL"
    else
        REPLICATED_V1_INSTALL_SCRIPT_CMD=$REPLICATED_V1_INSTALL_SCRIPT_CMD" $REPLICATED_INSTALL_URL/$RELEASE_CHANNEL"
    fi
    REPLICATED_V1_INSTALL_SCRIPT_CMD=$REPLICATED_V1_INSTALL_SCRIPT_CMD" | bash -s"
    if [ "$SKIP_DOCKER_INSTALL" -eq "1" ]; then
        REPLICATED_V1_INSTALL_SCRIPT_CMD=$REPLICATED_V1_INSTALL_SCRIPT_CMD" no-docker"
    fi
    if [ -n "$PROXY_ADDRESS" ]; then
        REPLICATED_V1_INSTALL_SCRIPT_CMD=$REPLICATED_V1_INSTALL_SCRIPT_CMD" http-proxy=$PROXY_ADDRESS"
    fi
    read_replicated_conf "LocalAddress"
    if [ -n "$REPLICATED_CONF_VALUE" ]; then
        REPLICATED_V1_INSTALL_SCRIPT_CMD=$REPLICATED_V1_INSTALL_SCRIPT_CMD" local-address=$REPLICATED_CONF_VALUE"
    fi
}

RESTORE_SCRIPT=
backup_replicated() {
    printf "Enter directory in which to backup Replicated data (/var/lib/replicated_backups): "
    set +e
    read $READ_TIMEOUT backup_dir < /dev/tty
    set -e
    backup_dir=${backup_dir:-/var/lib/replicated_backups}
    backup_file=${backup_dir%/}/backup_$(date +%s).tgz
    mkdir -p $backup_dir
    tar -zcf $backup_file /var/lib/replicated > /dev/null 2>&1

    RESTORE_SCRIPT=${backup_dir%/}/restore.sh
    echo '#!/bin/bash' > $RESTORE_SCRIPT
    echo 'printf "You are about to restore Replicated V1. Do you want to proceed? (y/N) "' >> $RESTORE_SCRIPT
    echo 'read allow < /dev/tty' >> $RESTORE_SCRIPT
    echo 'if [ "$allow" != "y" ] && [ "$allow" != "Y" ]; then' >> $RESTORE_SCRIPT
    echo '    exit 0' >> $RESTORE_SCRIPT
    echo 'fi' >> $RESTORE_SCRIPT
    case "$INIT_SYSTEM" in
        systemd)
            echo 'systemctl disable replicated replicated-ui replicated-updater replicated-agent replicated-operator' >> $RESTORE_SCRIPT
            echo 'systemctl stop replicated replicated-ui replicated-updater replicated-agent replicated-operator' >> $RESTORE_SCRIPT
            ;;
        upstart)
            echo 'stop replicated' >> $RESTORE_SCRIPT
            echo 'stop replicated-ui' >> $RESTORE_SCRIPT
            echo 'stop replicated-updater' >> $RESTORE_SCRIPT
            echo 'stop replicated-agent' >> $RESTORE_SCRIPT
            echo 'stop replicated-operator' >> $RESTORE_SCRIPT
            ;;
        sysvinit)
            echo 'service replicated stop' >> $RESTORE_SCRIPT
            echo 'service replicated-ui stop' >> $RESTORE_SCRIPT
            echo 'service replicated-updater stop' >> $RESTORE_SCRIPT
            echo 'service replicated-agent stop' >> $RESTORE_SCRIPT
            echo 'service replicated-operator stop' >> $RESTORE_SCRIPT
            ;;
    esac
    case "$LSB_DIST" in
        fedora|rhel|centos|amzn)
            echo 'yum remove -y replicated replicated-ui replicated-updater replicated-agent replicated-operator' >> $RESTORE_SCRIPT
            ;;
        ubuntu|debian)
            echo 'apt-get purge -y replicated replicated-ui replicated-updater replicated-agent replicated-operator < /dev/null' >> $RESTORE_SCRIPT
            ;;
    esac
    echo 'docker rm -f replicated replicated-ui replicated-operator' >> $RESTORE_SCRIPT
    echo 'rm -rf /var/lib/replicated /var/lib/replicated-operator /etc/systemd/system/replicated* /etc/init/replicated* /etc/init.d/replicated* /etc/default/replicated*' >> $RESTORE_SCRIPT
    echo 'mkdir -p /var/lib/replicated' >> $RESTORE_SCRIPT
    echo "tar -zxopf $backup_file -C /" >> $RESTORE_SCRIPT
    get_replicated_v1_install_script_cmd
    echo "$REPLICATED_V1_INSTALL_SCRIPT_CMD" >> $RESTORE_SCRIPT
    case "$LSB_DIST" in
        fedora|rhel|centos|amzn)
            echo 'yum install -y replicated-agent' >> $RESTORE_SCRIPT
            ;;
        ubuntu|debian)
            echo 'apt-get install -y replicated-agent' >> $RESTORE_SCRIPT
            ;;
    esac

    echo "Data has been backed up to $backup_file."
    echo "Replicated v1 data can be restored by issuing the following command:"
    echo ""
    echo "  cat $RESTORE_SCRIPT | sudo bash"
    echo ""
}

LOCAL_HOST=
REMOTE_HOSTS=0
get_hosts() {
    _hosts_result="$($CMD_PREFIX hosts)"
    _hosts_header="$(echo "$_hosts_result" | awk '{ if (NR==1) { print $0 } }')"
    _id_index="0"
    _private_addr_index="$(echo "$_hosts_header" | grep -b -o 'PRIVATE ADDRESS' | awk 'BEGIN { FS = ":" }{ print $1 }')"
    _public_addr_index="$(echo "$_hosts_header" | grep -b -o 'PUBLIC ADDRESS' | awk 'BEGIN { FS = ":" }{ print $1 }')"
    _name_index="$(echo "$_hosts_header" | grep -b -o 'NAME' | awk 'BEGIN { FS = ":" }{ print $1 }')"
    _tags_index="$(echo "$_hosts_header" | grep -b -o 'TAGS' | awk 'BEGIN { FS = ":" }{ print $1 }')"
    while read -r _hosts_row; do
        _id="$(echo "${_hosts_row:$_id_index}" | awk 'BEGIN { FS = "     *" }{ print $1 }')"
        _private_addr="$(echo "${_hosts_row:$_private_addr_index}" | awk 'BEGIN { FS = "     *" }{ print $1 }')"
        _public_addr="$(echo "${_hosts_row:$_public_addr_index}" | awk 'BEGIN { FS = "     *" }{ print $1 }')"
        _name="$(echo "${_hosts_row:$_name_index}" | awk 'BEGIN { FS = "     *" }{ print $1 }')"
        _tags="$(echo "${_hosts_row:$_tags_index}" | awk 'BEGIN { FS = "     *" }{ print $1 }' | tr -d ' ')"
        _host="$_id|$_name|$_private_addr|$_public_addr|$_tags"
        if [ "$_name" = "local" ]; then
            LOCAL_HOST=$_host
        else
            read "REMOTE_HOST_$REMOTE_HOSTS" <<< "$_host"
            REMOTE_HOSTS=$((REMOTE_HOSTS+1))
        fi
    done <<< "$(echo "$_hosts_result" | awk '{ if (NR>1) { print $0 } }')"
}

stop_replicated_v1() {
    case "$INIT_SYSTEM" in
        systemd)
            systemctl stop replicated || true
            ;;
        upstart)
            stop replicated || true
            ;;
        sysvinit)
            service replicated stop || true
            ;;
    esac
}

remove_replicated_v1() {
    case "$INIT_SYSTEM" in
        systemd)
            systemctl disable replicated replicated-ui replicated-updater replicated-agent || true
            systemctl stop replicated replicated-ui replicated-updater replicated-agent || true
            ;;
        upstart)
            stop replicated || true
            stop replicated-ui || true
            stop replicated-updater || true
            stop replicated-agent || true
            ;;
        sysvinit)
            service replicated stop || true
            service replicated-ui stop || true
            service replicated-updater stop || true
            service replicated-agent stop || true
            ;;
    esac

    case "$LSB_DIST" in
        fedora|rhel|centos|amzn)
            yum remove -y replicated replicated-ui replicated-updater replicated-agent || true
            return
            ;;
        ubuntu|debian)
            apt-get purge -y replicated replicated-ui replicated-updater replicated-agent < /dev/null || true
            return
            ;;
    esac

    cat >&2 <<'EOF'
Error: either your platform is not easily detectable, is not supported by
this installer script, or does not yet have a package for Replicated.
EOF
    exit 1
}

remove_replicated_agent_v1_command() {
    case "$INIT_SYSTEM" in
        systemd)
            echo "  sudo systemctl stop replicated-agent \\"
            echo "    && sudo systemctl disable replicated-agent \\"
            ;;
        upstart)
            echo "  sudo stop replicated-agent \\"
            ;;
        sysvinit)
            echo "  sudo service replicated-agent stop \\"
            ;;
    esac
    case "$LSB_DIST" in
        fedora|rhel|centos|amzn)
            echo "    && sudo yum remove -y replicated-agent"
            return
            ;;
        ubuntu|debian)
            echo "    && sudo apt-get purge -y replicated-agent"
            return
            ;;
    esac
}

start_replicated_v2() {
    cmd=
    if command_exists "curl"; then
        cmd="curl -sSL"
        if [ -n "$PROXY_ADDRESS" ]; then
            cmd=$cmd" -x $PROXY_ADDRESS"
        fi
    elif command_exists "wget"; then
        cmd="wget -qO-"
    else
        echo >&2 "Error: curl or wget required"
        exit 1
    fi

    if [ "$RELEASE_CHANNEL" = "stable" ]; then
        cmd=$cmd" $REPLICATED_INSTALL_URL/docker"
    else
        cmd=$cmd" $REPLICATED_INSTALL_URL/$RELEASE_CHANNEL/docker"
    fi

    $cmd > "$REPLICATED_TEMP_DIR/replicated_install.sh"

    opts="is-migration daemon-token=$DAEMON_TOKEN"
    if [ "$SKIP_DOCKER_INSTALL" -eq "1" ]; then
        opts=$opts" no-docker"
    fi
    read_replicated_conf "LocalAddress"
    if [ -n "$REPLICATED_CONF_VALUE" ]; then
        opts=$opts" local-address=$REPLICATED_CONF_VALUE"
    fi
    if [ -n "$PROXY_ADDRESS" ]; then
        opts=$opts" http-proxy=$PROXY_ADDRESS"
    else
        opts=$opts" no-proxy"
    fi
    if [ -z "$READ_TIMEOUT" ]; then
        opts=$opts" no-auto"
    fi

    bash "$REPLICATED_TEMP_DIR/replicated_install.sh" $opts < /dev/null

    for i in {1..10}; do
        if is_replicated_v2_started; then
          return
        fi
        sleep 5
    done

    echo >&2 "Error: Replicated failed to start"
    exit 1
}

is_replicated_v2_installed() {
    if docker inspect replicated > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

is_replicated_v2_started() {
    if $V2_CMD_PREFIX status 2>/dev/null | grep -q "started" ; then
        return 0
    else
        return 1
    fi
}

get_replicated_daemon_endpoint() {
    DAEMON_ENDPOINT=$($V2_CMD_PREFIX console operator_bind_address)
}

get_replicated_daemon_token() {
    DAEMON_TOKEN=$($V2_CMD_PREFIX console operator_access_token)
}

get_operator_install_script_cmd() {
    OPERATOR_INSTALL_SCRIPT_CMD=
    if command_exists "curl"; then
        if [ -n "$PROXY_ADDRESS" ]; then
            OPERATOR_INSTALL_SCRIPT_CMD="curl -sSL -x $PROXY_ADDRESS $REPLICATED_INSTALL_URL"
        else
            OPERATOR_INSTALL_SCRIPT_CMD="curl -sSL $REPLICATED_INSTALL_URL"
        fi
    else
        OPERATOR_INSTALL_SCRIPT_CMD="wget -qO- $REPLICATED_INSTALL_URL"
    fi
    if [ "$RELEASE_CHANNEL" = "stable" ]; then
        OPERATOR_INSTALL_SCRIPT_CMD=$OPERATOR_INSTALL_SCRIPT_CMD"/operator"
    else
        OPERATOR_INSTALL_SCRIPT_CMD=$OPERATOR_INSTALL_SCRIPT_CMD"/$RELEASE_CHANNEL/operator"
    fi
}

get_operator_install_script() {
    $OPERATOR_INSTALL_SCRIPT_CMD > "$REPLICATED_TEMP_DIR/operator_install.sh"
}

install_operator_opts() {
    _id=$(echo "$1" | awk 'BEGIN { FS = "|" } { print $1 }')
    _private_addr=$(echo "$1" | awk 'BEGIN { FS = "|" } { print $3 }')
    _public_addr=$(echo "$1" | awk 'BEGIN { FS = "|" } { print $4 }')
    _tags=$(echo "$1" | awk 'BEGIN { FS = "|" } { print $5 }')

    INSTALL_OPERATOR_OPTS="no-docker operator-id=$_id daemon-endpoint=$DAEMON_ENDPOINT daemon-token=$DAEMON_TOKEN"
    if [ -n "$_private_addr" ]; then
        INSTALL_OPERATOR_OPTS=$INSTALL_OPERATOR_OPTS" private-address=$_private_addr"
    fi
    if [ -n "$_public_addr" ]; then
        INSTALL_OPERATOR_OPTS=$INSTALL_OPERATOR_OPTS" public-address=$_public_addr"
    fi
    if [ -n "$_tags" ]; then
        INSTALL_OPERATOR_OPTS=$INSTALL_OPERATOR_OPTS" tags=$_tags"
    fi
    if [ -n "$PROXY_ADDRESS" ]; then
        INSTALL_OPERATOR_OPTS=$INSTALL_OPERATOR_OPTS" http-proxy=$PROXY_ADDRESS"
    else
        INSTALL_OPERATOR_OPTS=$INSTALL_OPERATOR_OPTS" no-proxy"
    fi
}

start_replicated_v2_local_operator() {
    install_operator_opts $1
    if [ -z "$READ_TIMEOUT" ]; then
        INSTALL_OPERATOR_OPTS=$INSTALL_OPERATOR_OPTS" no-auto"
    fi
    bash "$REPLICATED_TEMP_DIR/operator_install.sh" $INSTALL_OPERATOR_OPTS < /dev/null

    for i in {1..10}; do
        if is_operator_v2_initialized $_id; then
            return
        fi
        sleep 5
    done

    echo >&2 "Error: unable to start the operator"
    exit 1
}

start_replicated_v2_remote_operator() {
    install_operator_opts $1
    echo "  $OPERATOR_INSTALL_SCRIPT_CMD \\"
    echo "    | sudo bash -s $INSTALL_OPERATOR_OPTS"
    echo ""

    printf "Press any key when complete: "
    set +e
    # NOTE: no read timeout
    read < /dev/tty
    set -e

    for i in {1..10}; do
        if is_operator_v2_initialized $1; then
            return
        fi
        sleep 5
    done

    echo >&2 "Error: operator not started"
    exit 1
}

is_operator_v2_initialized() {
    _node=$($V2_CMD_PREFIX nodes | grep $1)
    _connected=$(echo "$_node" | awk 'BEGIN { FS = "     *" } { print $4 }')
    _initialized=$(echo "$_node" | awk 'BEGIN { FS = "     *" } { print $5 }')
    if [ "$_connected" = "true" ] && [ "$_initialized" = "true" ]; then
        return 0
    else
        return 1
    fi
}

run_replicated_v2_migration() {
    while true; do
        set +e
        _out=$($V2_CMD_PREFIX migrate-v2 $APP_ID)
        _err=$?
        set -e
        if [ "$_err" -eq "0" ]; then
            return
        fi
        echo "Migration command failed with error:"
        echo "  $_out"
        for i in {1..10}; do
            printf "Try again (Y/n) "
            set +e
            read $READ_TIMEOUT _again < /dev/tty
            set -e
            _again=${_again:-y}
            if [ "$_again" = "n" ] || [ "$_again" = "N" ]; then
                echo >&2 "Migration failed:"
                replicated_v2_migration_command $APP_ID
                exit 1
            elif [ "$_again" = "y" ] || [ "$_again" = "Y" ]; then
                break
            fi
        done
    done
}

replicated_v2_migration_command() {
    echo "The database migration script can be run manually by issuing the following command:"
    echo ""
    echo "  sudo docker exec -it replicated replicated migrate-v2 $APP_ID"
    echo ""
}

start_app_v2() {
    $V2_CMD_PREFIX app $APP_ID start
    # shellcheck disable=SC2034

    MAX_WAIT=120
    for i in $(seq 1 $MAX_WAIT); do
        if [ $i -ne "$MAX_WAIT" ] && [ $(( $i % 12 )) -eq "0" ]; then
            RUNNING=$(( $i / 12 ))
            MINUTES="minute"
            if [ $RUNNING -gt "1" ]; then
                MINUTES="minutes"
            fi
            echo "Service is not running after $RUNNING $MINUTES.  Waiting for service to finish starting..."
        fi
        if is_app_started_v2 $APP_ID; then
            return
        fi
        sleep 5
    done

    echo >&2 "Service not started after 10 minutes.  Please check the console for the current status."
    exit 1
}

is_app_started_v2() {
    _app=$($V2_CMD_PREFIX app $APP_ID)
    _run_status=$(echo "$_app" | grep -o '"RunStatus":\s*"[^"]*' | sed 's/"RunStatus":\s*"//') || true
    _run_status_next=$(echo "$_app" | grep -o '"RunStatusNext":\s*"[^"]*' | sed 's/"RunStatusNext":\s*"//') || true
    _transitioning=$(echo "$_app" | grep -o '"IsStartInProgress":\s*[tf][ra][ul]s*e' | sed 's/"IsStartInProgress":\s*//') || true

    if [ "$_run_status" = "Started" ] && [ "$_run_status_next" = "Started" ] && [ "$_transitioning" = "false" ]; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Execution starts here
################################################################################

if [ -z "$REPLICATED_TEMP_DIR" ]; then
    REPLICATED_TEMP_DIR="$(mktemp -d --suffix=replicated)"
fi

case "$(uname -m)" in
    *64)
        ;;
    *)
        echo >&2 'Error: you are not using a 64bit platform.'
        echo >&2 'This installer currently only supports 64bit platforms.'
        exit 1
        ;;
esac

user="$(id -un 2>/dev/null || true)"

detect_lsb_dist

detect_init_system

if [ "$user" != "root" ]; then
    echo >&2 "Error: This script requires admin privileges. Please re-run it as root."
    exit 1
fi

while [ "$1" != "" ]; do
    _param=`echo "$1" | awk -F= '{print $1}'`
    _value=`echo "$1" | awk -F= '{print $2}'`
    case $_param in
        channel)
            case $_value in
                beta)
                    RELEASE_CHANNEL="beta"
                    ;;
                unstable)
                    RELEASE_CHANNEL="unstable"
                    ;;
            esac
            ;;
        no-docker|no_docker)
            SKIP_DOCKER_INSTALL=1
            ;;
        no-proxy|no_proxy)
            NO_PROXY=1
            ;;
        no-auto|no_auto)
            READ_TIMEOUT=
            ;;
        read-timeout|read_timeout)
            READ_TIMEOUT="-t $_value"
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

while true
do
    set +e
    read $READ_TIMEOUT -p "Please backup your server before running this script. Do you want to proceed? (y/N) " allow < /dev/tty
    _err=$?
    set -e
    if [ "$_err" -ge "128" ]; then
        echo $READ_TIMEOUT_MSG
        allow=""
    fi
    case $allow in
        "")
            exit 0;;
        [nN]*)
            exit 0;;
        [yY]*)
            break;;
        *)
            echo "Please choose y or n.";;
    esac
done

CMD_PREFIX="replicated"
V2_CMD_PREFIX="docker exec replicated replicated"

if is_replicated_v2_installed; then
    printf "It looks as though Replicated v2 is already installed\n"
    replicated_v2_migration_command "<app id>"
    exit 0
fi

if [ "$NO_PROXY" -ne "1" ]; then
    if [ -z "$PROXY_ADDRESS" ]; then
        discover_proxy
    fi

    if [ -z "$PROXY_ADDRESS" ]; then
        ask_for_proxy
    fi
fi

if [ -n "$PROXY_ADDRESS" ]; then
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
fi

if [ -n "$PROXY_ADDRESS" ]; then
    require_docker_proxy
fi

needs_login

get_app

echo "Migration may take a few minutes, great time to grab a hot cup of coffee..."
echo ""

echo "Migrating $APP_NAME..."
echo ""

get_hosts

echo "1) Stopping app..."
stop_app
echo "App stopped"
echo ""

echo "2) Stoppping Replicated daemon..."
stop_replicated_v1
echo "Replicated daemons stopped"
echo ""

echo "3) Backing up Replicated..."
backup_replicated
echo "Backup success"
echo ""

echo "4) Removing Replicated daemons..."
remove_replicated_v1
if [ "$REMOTE_HOSTS" -gt "0" ]; then
    echo "Local Replicated daemons removed"
    echo "Please remove all $REMOTE_HOSTS remote agent(s) manually by issuing the following commands on the respective hosts:"
    echo ""
    remove_replicated_agent_v1_command
    echo ""
    printf "Press any key when complete: "
    set +e
    # NOTE: no read timeout
    read < /dev/tty
    set -e
fi
echo "All Replicated daemons removed"
echo ""

echo "5) Starting Replicated docker containers..."
get_operator_install_script_cmd
get_operator_install_script
start_replicated_v2
get_replicated_daemon_endpoint
get_replicated_daemon_token
if [ -n "$LOCAL_HOST" ]; then
    start_replicated_v2_local_operator $LOCAL_HOST
fi
if [ "$REMOTE_HOSTS" -gt "0" ]; then
    echo "Local Replicated docker containers started"
    if [ "$REMOTE_HOSTS" = "1" ]; then
        echo "Please start the remote operators manually by issuing the following command on the remote host:"
    else
        echo "Please start each of the $REMOTE_HOSTS remote operators manually by issuing the following commands on the respective hosts:"
    fi
    echo ""
    for (( i=0; i<$REMOTE_HOSTS; i++ )); do
        _remote_host="REMOTE_HOST_$i"
        start_replicated_v2_remote_operator ${!_remote_host}
    done
fi
echo "All Replicated docker containers started"
echo ""

echo "6) Running database migration script..."
run_replicated_v2_migration
echo "Migration success"
echo ""

echo "7) Starting service..."
start_app_v2
echo "Service started"
echo ""

echo "Migration complete"
exit 0
