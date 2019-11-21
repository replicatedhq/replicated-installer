#!/bin/bash

set -e

AIRGAP=0
DAEMON_TOKEN=
GROUP_ID=
LOG_LEVEL=
MIN_DOCKER_VERSION="1.13.1" # secrets compatibility
NO_PROXY=0
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
PUBLIC_ADDRESS=
REGISTRY_BIND_PORT=
SKIP_DOCKER_INSTALL=0
SKIP_DOCKER_PULL=0
EXCLUDE_SUBNETS=
SWARM_ADVERTISE_ADDR=
SWARM_LISTEN_ADDR=
SWARM_NODE_ADDRESS=
SWARM_STACK_NAMESPACE=replicated
TLS_CERT_PATH=
UI_BIND_PORT=8800
USER_ID=
NO_CE_ON_EE="{{ no_ce_on_ee }}"
HARD_FAIL_ON_LOOPBACK="{{ hard_fail_on_loopback }}"
HARD_FAIL_ON_FIREWALLD="{{ hard_fail_on_firewalld }}"
ADDITIONAL_NO_PROXY=
SKIP_PREFLIGHTS="{{ '1' if skip_preflights else '' }}"
IGNORE_PREFLIGHTS="{{ '1' if ignore_preflights else '' }}"
REPLICATED_VERSION="{{ replicated_version }}"
REPLICATED_USERNAME="{{ replicated_username }}"
FORCE_REPLICATED_DOWNGRADE=0

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
{% include 'common/prompt.sh' %}
{% include 'common/log.sh' %}
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
{% include 'common/firewall.sh' %}
{% include 'preflights/index.sh' %}

initSwarm() {
    # init swarm (need for service command); if not created
    if ! docker node ls 2>/dev/null | grep -q "Leader"; then
        echo "Initializing the swarm"
        set +e
        docker swarm init --advertise-addr="$SWARM_ADVERTISE_ADDR" --listen-addr="$SWARM_LISTEN_ADDR"
        _status=$?
        set -e
        if [ "$_status" -ne "0" ]; then
            printf "${RED}Failed to initialize the swarm cluster.${NC}\n" 1>&2
            if [ -z "$SWARM_ADVERTISE_ADDR" ] || [ -z "$SWARM_LISTEN_ADDR" ]; then
                printf "${RED}It may be possible to re-run this installer with the flags -swarm-advertise-addr and -swarm-listen-addr to resolve the problem.${NC}\n" 1>&2
            fi
            exit $_status
        fi
    fi
}

maybeCreateDaemonToken() {
    # if the daemon_token secret does not already exist, create it
    if ! docker secret inspect daemon_token > /dev/null 2>&1; then
        if [ -z "$DAEMON_TOKEN" ]; then
            getGuid
            DAEMON_TOKEN="$GUID_RESULT"
        fi
        echo "$DAEMON_TOKEN" | docker secret create daemon_token -
        echo "Replicated secret token: ${DAEMON_TOKEN}"
    fi
}

excludeSubnets() {
    if [ -n "$EXCLUDE_SUBNETS" ]; then
        docker network create --driver=overlay $EXCLUDE_SUBNETS exclude_net
    fi
}

# Since 2.22.0 the replicated_default network is used for snapshots so it must
# be pre-created as attachable. When upgrading from an older version it must be
# destroyed and re-created as attachable.
ensureReplicatedNetworkAttachable() {
    if docker network ls | grep --quiet "replicated_default"; then
        attachable=$(docker network inspect replicated_default --format="{{ '{{ .Attachable }}' }}")
        if [ "$attachable" == "true" ]; then
            echo "Found attachable replicated_default network"
            return 0;
        fi

        echo "Destroying replicated_default network"
        set +e
        docker service rm replicated_replicated
        docker service rm replicated_replicated-operator
        docker service rm replicated_replicated-ui
        docker service rm premkit_replicated
        docker service rm statsd_replicated
        set -e

        docker network rm replicated_default
        while $(docker network ls | grep --quiet "replicated_default"); do
            sleep 1
        done
    fi

    echo "Create attachable replicated_default network"
    docker network create --driver=overlay --attachable --label=com.docker.stack.namespace=replicated replicated_default
}

stackDeploy() {
    opts=
    if [ "$AIRGAP" = "1" ]; then
        opts=$opts" airgap"
    fi
    if [ -n "$GROUP_ID" ]; then
        opts=$opts" group-id=$GROUP_ID"
    fi
    if [ -n "$LOG_LEVEL" ]; then
        opts=$opts" log-level=$LOG_LEVEL"
    fi
    if [ -n "$PUBLIC_ADDRESS" ]; then
        opts=$opts" public-address=$PUBLIC_ADDRESS"
    fi
    if [ -n "$REGISTRY_BIND_PORT" ]; then
        opts=$opts" registry-bind-port=$REGISTRY_BIND_PORT"
    fi
    if [ -n "$RELEASE_SEQUENCE" ]; then
        opts=$opts" release-sequence=$RELEASE_SEQUENCE"
    fi
    if [ -n "$SWARM_NODE_ADDRESS" ]; then
        opts=$opts" swarm-node-address=$SWARM_NODE_ADDRESS"
    fi
    if [ -n "$SWARM_STACK_NAMESPACE" ]; then
        opts=$opts" swarm-stack-namespace=$SWARM_STACK_NAMESPACE"
    fi
    if [ -n "$TLS_CERT_PATH" ]; then
        opts=$opts" tls-cert-path=$TLS_CERT_PATH"
    fi
    if [ -n "$UI_BIND_PORT" ]; then
        opts=$opts" ui-bind-port=$UI_BIND_PORT"
    fi
    if [ -n "$USER_ID" ]; then
        opts=$opts" user-id=$USER_ID"
    fi
    if [ -n "$PROXY_ADDRESS" ]; then
        opts=$opts" http-proxy=$PROXY_ADDRESS"
    fi
    if [ -n "$NO_PROXY_ADDRESSES" ]; then
        opts=$opts" no-proxy-addresses=$NO_PROXY_ADDRESSES"
    fi

    echo "Deploying Replicated stack"

    if [ "$AIRGAP" = "1" ]; then
        bash ./docker-compose-generate.sh $opts < /dev/null \
            > /tmp/replicated-docker-compose.yml
    else
        getUrlCmd
        $URLGET_CMD "{{ replicated_install_url }}/{{ docker_compose_path }}?{{ docker_compose_query }}" \
            > /tmp/docker-compose-generate.sh
        bash /tmp/docker-compose-generate.sh $opts < /dev/null \
            > /tmp/replicated-docker-compose.yml
    fi

    semverCompare "$REPLICATED_VERSION" "2.29.0"
    if [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
        # The restart policy used to be on-failure which caused replicated to stop running on upgrades due to an exit code 0.
        # This will force the service to start after upgrading to ensure that the service did not complete.
        if docker stack services -q "$SWARM_STACK_NAMESPACE" | xargs docker service inspect --format "{{ '{{.Spec.TaskTemplate.RestartPolicy.Condition}}' }}" 2>/dev/null | grep -qs "on-failure"; then
            docker stack services -q "$SWARM_STACK_NAMESPACE" | xargs -L1 docker service update -d --restart-condition=any >/dev/null || :
            waitStackServices
        fi
    fi

    # Update replicated to the new version.
    docker stack deploy -c /tmp/replicated-docker-compose.yml "$SWARM_STACK_NAMESPACE"
    waitStackServices
}

waitStackServices() {
    _counter=0
    while docker stack services -q "$SWARM_STACK_NAMESPACE" | xargs docker service inspect --format "{{ '{{.UpdateStatus.State}}' }}" 2>/dev/null | grep -qs "updating" && [ "$_counter" -lt "10" ]; do
        sleep 5
        _counter="$(($_counter+1))"
    done
}

includeBranding() {
    if [ -n "$CHANNEL_CSS" ]; then
        echo "$CHANNEL_CSS" | base64 --decode > /tmp/channel.css
    fi
    if [ -n "$TERMS" ]; then
        echo "$TERMS" | base64 --decode > /tmp/terms.json
    fi

    # wait until replicated container is running
    REPLICATED_CONTAINER_ID="$(docker ps -a -q --filter='name=replicated_replicated\.' --filter='status=running')"
    LOOP_COUNTER=0
    while [ "$REPLICATED_CONTAINER_ID" = "" ] && [ "$LOOP_COUNTER" -le 30 ]; do
        sleep 1s
        let LOOP_COUNTER=LOOP_COUNTER+1
        REPLICATED_CONTAINER_ID="$(docker ps -a -q --filter='name=replicated_replicated\.' --filter='status=running')"
    done

    # then copy in the branding file
    if [ -n "$REPLICATED_CONTAINER_ID" ]; then
        docker exec "${REPLICATED_CONTAINER_ID}" mkdir -p /var/lib/replicated/branding/
        if [ -f /tmp/channel.css ]; then
            docker cp /tmp/channel.css "${REPLICATED_CONTAINER_ID}:/var/lib/replicated/branding/channel.css"
        fi
        if [ -f /tmp/terms.json ]; then
            docker cp /tmp/terms.json "${REPLICATED_CONTAINER_ID}:/var/lib/replicated/branding/terms.json"
        fi
    else
        printf "${YELLOW}Unable to find replicated container to copy branding css to.${NC}\n"
    fi
}

outro() {
    if [ -z "$PUBLIC_ADDRESS" ]; then
        PUBLIC_ADDRESS="<this_server_address>"
    fi
    printf "\n${GREEN}To continue the installation, visit the following URL in your browser:\n\n"
    printf "    http://%s:%s\n" "$PUBLIC_ADDRESS" "$UI_BIND_PORT"
    if ! commandExists "replicated"; then
        printf "\nTo create an alias for the replicated cli command run the following in your current shell or log out and log back in:\n\n  source /etc/replicated.alias\n"
    fi
    printf "${NC}\n"
}


################################################################################
# Execution starts here
################################################################################

export DEBIAN_FRONTEND=noninteractive

require64Bit
requireRootUser
detectLsbDist
detectInitSystem

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            # airgap implies "skip docker"
            AIRGAP=1
            SKIP_DOCKER_INSTALL=1
            ;;
        bypass-storagedriver-warnings|bypass_storagedriver_warnings)
            BYPASS_STORAGEDRIVER_WARNINGS=1
            ;;
        daemon-token|daemon_token)
            DAEMON_TOKEN="$_value"
            ;;
        docker-version|docker_version)
            PINNED_DOCKER_VERSION="$_value"
            ;;
        force-replicated-downgrade|force_replicated_downgrade)
            FORCE_REPLICATED_DOWNGRADE=1
            ;;
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        log-level|log_level)
            LOG_LEVEL="$_value"
            ;;
        no-docker|no_docker)
            SKIP_DOCKER_INSTALL=1
            ;;
        no-proxy|no_proxy)
            NO_PROXY=1
            ;;
        public-address|public_address)
            PUBLIC_ADDRESS="$_value"
            ;;
        release-sequence|release_sequence)
            RELEASE_SEQUENCE="$_value"
            ;;
        skip-pull|skip_pull)
            SKIP_DOCKER_PULL=1
            ;;
        exclude-subnet|exclude_subnet)
            if [ -z "$EXCLUDE_SUBNETS" ]; then
                EXCLUDE_SUBNETS="--subnet=$_value"
            else
                EXCLUDE_SUBNETS="$EXCLUDE_SUBNETS --subnet=$_value"
            fi
            ;;
        swarm-advertise-addr|swarm_advertise_addr)
            SWARM_ADVERTISE_ADDR="$_value"
            ;;
        swarm-listen-addr|swarm_listen_addr)
            SWARM_LISTEN_ADDR="$_value"
            ;;
        swarm-stack-namespace|swarm_stack_namespace)
            SWARM_STACK_NAMESPACE="$_value"
            ;;
        ui-bind-port|ui_bind_port)
            UI_BIND_PORT="$_value"
            ;;
        tls-cert-path|tls_cert_path)
            TLS_CERT_PATH="$_value"
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

if [ -z "$PUBLIC_ADDRESS" ] && [ "$AIRGAP" -ne "1" ]; then
    printf "Determining service address\n"
    discoverPublicIp

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

    if [ -z "$PROXY_ADDRESS" ] && [ "$AIRGAP" != "1" ]; then
        promptForProxy
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

detectDockerGroupId
maybeCreateReplicatedUser
USER_ID="$REPLICATED_USER_ID"
GROUP_ID="$DOCKER_GROUP_ID"

initSwarm

SWARM_TOKEN="$(docker swarm join-token -q worker)"
SWARM_NODE_ID="$(docker info --format "{{ '{{.Swarm.NodeID}}' }}")"
SWARM_NODE_ADDRESS="$(docker info --format "{{ '{{.Swarm.NodeAddr}}' }}")"
SWARM_MASTER_ADDRESS="$(docker info --format "{{ '{{with index .Swarm.RemoteManagers 0}}{{.Addr}}{{end}}' }}")"

if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
    getNoProxyAddresses "$SWARM_NODE_ADDRESS"
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

# TODO: consider running replicated as registry mirror

echo "Swarm nodes:"
docker node ls

maybeCreateDaemonToken

# this label is needed for replicated and replicated-ui node placement
docker node update --label-add replicated-role=master "$SWARM_NODE_ID"

if [ "$SKIP_DOCKER_PULL" = "1" ]; then
    printf "Skip docker pull flag detected, will not pull replicated, replicated-ui and replicated-operator images\n"
else
    if [ "$AIRGAP" != "1" ]; then
        printf "Pulling replicated, replicated-ui and replicated-operator images\n"
        pullReplicatedImages
        pullOperatorImage
    else
        printf "Loading replicated, replicated-ui and replicated-operator images from package\n"
        airgapLoadReplicatedImages
        airgapLoadOperatorImage
        printf "Loading replicated debian, command, statsd-graphite, and premkit images from package\n"
        airgapLoadSupportImages
        airgapMaybeLoadSupportBundle
        airgapMaybeLoadRetraced
    fi

    # is this an update?
    if /usr/local/bin/replicatedctl app status inspect >/dev/null 2>&1; then
        printf "Pushing replicated-operator container image to on-prem registry\n"
        tagAndPushOperatorImage "${SWARM_NODE_ADDRESS}:${REGISTRY_BIND_PORT:-9874}" || :
    fi
fi

excludeSubnets
ensureReplicatedNetworkAttachable
stackDeploy

includeBranding

printf "Installing replicated command alias\n"
installCliFile \
    "sudo docker exec" \
    '"$(sudo docker inspect --format "{{ '{{.Status.ContainerStatus.ContainerID}}' }}" "$(sudo docker service ps "$(sudo docker service inspect --format "{{ '{{.ID}}' }}" '"${SWARM_STACK_NAMESPACE}"'_replicated)" -q | awk "NR==1")")"'
installAliasFile

# printf "${GREEN}To add a worker to this swarm, run the following command:\n"
# printf "    curl -sSL {{ replicated_install_url }}/{{ swarm_worker_join_path }} | sudo bash -s \\ \n"
# printf "        swarm-master-address=%s \\ \n" "$SWARM_MASTER_ADDRESS"
# printf "        swarm-token=%s${NC}\n" "$SWARM_TOKEN"

# TODO: wait for replicated services to come up

outro
exit 0
