###############################################################################
## docker.sh
###############################################################################

###############################################################################
# Check if Docker device driver is Devicemapper in loopback mode
###############################################################################
preflightDockerDevicemapperLoopback()
{
    if ! commandExists "docker"; then
        return 0
    fi

    local driver="$(docker info 2>/dev/null | grep 'Storage Driver' | awk '{print $3}' | awk -F- '{print $1}')"
    if [ "$driver" != "devicemapper" ]; then
        return 0
    fi
    if docker info 2>/dev/null | grep -Fqs 'Data loop file:'; then
        warn "Docker device driver devicemapper is in loopback mode"
        return 1
    fi
    info "Docker device driver devicemapper not in loopback mode"
    return 0
}

###############################################################################
# Check if Docker is running with an http proxy
###############################################################################
preflightDockerHttpProxy()
{
    if ! commandExists "docker"; then
        return 0
    fi

    local proxy="$(docker info 2>/dev/null | grep -i 'Http Proxy:' | sed 's/ *Http Proxy: //I')"
    local no_proxy="$(docker info 2>/dev/null | grep -i 'No Proxy:' | sed 's/ *No Proxy: //I')"

    if [ -n "$proxy" ]; then
        info "Docker is set with http proxy \"$proxy\" and no proxy \"$no_proxy\""
    fi
    info "Docker http proxy not set"
    return 0
}

###############################################################################
# Check if Docker is running with a non-default seccomp profile
###############################################################################
preflightDockerSeccompNonDefault()
{
    if ! commandExists "docker"; then
        return 0
    fi

    if ! docker info 2>&1 | grep -q seccomp; then
        # no seccomp profile
        return 0
    fi

    if docker info 2>&1 | grep -qE "WARNING:.*seccomp profile"; then
        warn "Docker using a non-default seccomp profile"
        return 1
    fi
    info "Docker using default seccomp profile"
    return 0
}

###############################################################################
# Check if Docker is running with a non-standard root directory
###############################################################################
preflightDockerNonStandardRoot()
{
    if ! commandExists "docker"; then
        return 0
    fi

    local dir="$(docker info 2>/dev/null | grep -i 'Docker Root Dir:' | sed 's/ *Docker Root Dir: //I')"
    if [ -z "$dir" ]; then
        # failed to detect root dir
        return 0
    fi
    if [ "$dir" != "/var/lib/docker" ]; then
        error "Docker using a non-standard root directory of $dir"
        return 1
    fi
    info "Docker using standard root directory"
    return 0
}

###############################################################################
# Check if Docker icc is disabled
###############################################################################
preflightDockerIccDisabled()
{
    if ! commandExists "docker"; then
        return 0
    fi

    if ! docker network >/dev/null 2>&1; then
        # docker network command does not exist
        return 0
    fi

    if docker network inspect bridge | grep -q '"com.docker.network.bridge.enable_icc": "false"'; then
        warn "Docker icc (inter-container communication) disabled"
        return 1
    fi
    info "Docker icc (inter-container communication) enabled"
    return 0
}

###############################################################################
# Check if any Docker container registries are blocked
###############################################################################
preflightDockerContainerRegistriesBlocked()
{
    if ! commandExists "docker"; then
        return 0
    fi

    if [ ! -e /etc/containers/registries.conf ]; then
        return 0
    fi
    local registries="$(cat /etc/containers/registries.conf | awk '/\[registries\.block\]/,0' | grep "registries = " | head -1 | sed 's/registries *= \[ *\([^]]*\) *]/\1/')"
    if [ -n "$registries" ]; then
        warn "Docker /etc/containers/registries.conf blocking registries $registries"
        return 1
    fi
    info "Docker /etc/containers/registries.conf not blocking"
    return 0
}

###############################################################################
# Check if any Docker nofile ulimit is set
###############################################################################
preflightDockerUlimitNofileSet()
{
    if ! commandExists "docker"; then
        return 0
    fi

    maybeBuildPreflightImage
    maybeRemoveDockerContainer preflightDockerUlimitNofileSet
    docker run -d -p 38888:80 --name preflightDockerUlimitNofileSet "$PREFLIGHT_IMAGE" 10 >/dev/null 2&>1
    local nofile="$(docker inspect preflightDockerUlimitNofileSet | awk '/"nofile",/,0')"
    maybeRemoveDockerContainer preflightDockerUlimitNofileSet

    if [ -n "$nofile" ]; then
        local soft="$(echo "$nofile" | grep '"Soft":' | head -1 | sed 's/.*"Soft": *\([0-9]*\).*/\1/')"
        local hard="$(echo "$nofile" | grep '"Hard":' | head -1 | sed 's/.*"Hard": *\([0-9]*\).*/\1/')"
        if [ -n "$soft" ] || [ -n "$hard" ]; then
            warn "Docker open files (nofile) ulimit set to ${soft}:${hard}"
            return 1
        fi
    fi
    info "Docker open files (nofile) ulimit not set"
    return 0
}

###############################################################################
# Check if Docker userland-proxy is disabled
###############################################################################
preflightDockerUserlandProxyDisabled()
{
    if ! commandExists "docker"; then
        return 0
    fi

    maybeBuildPreflightImage
    maybeRemoveDockerContainer preflightDockerUserlandProxyDisabled
    docker run -d -p 38888:80 --name preflightDockerUserlandProxyDisabled "$PREFLIGHT_IMAGE" 10 >/dev/null 2&>1
    if ! ps auxw | grep -q "[d]ocker-proxy"; then
        maybeRemoveDockerContainer preflightDockerUserlandProxyDisabled
        warn "Docker userland proxy disabled"
        return 1
    fi
    maybeRemoveDockerContainer preflightDockerUserlandProxyDisabled
    info "Docker userland proxy enabled"
    return 0
}

PREFLIGHT_IMAGE="replicated/sleep:1.0"
maybeBuildPreflightImage()
{
    if docker inspect "$PREFLIGHT_IMAGE" >/dev/null 2&>1; then
        return
    fi

    local sleep="$(which sleep)"

    local linked="$(ldd -v "$sleep" | grep " => /" | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p' | sort | uniq)"

    local dir="$(mktemp -d)"

    cp "$sleep" "$dir"

    while read -r so; do
        cp "$so" "$dir"
    done <<< "$linked"

    cat >"$dir/Dockerfile" <<EOF
FROM scratch

ADD sleep /bin/sleep
EOF

    while read -r so; do
        echo "ADD $(basename $so) $so" >> "$dir/Dockerfile"
    done <<< "$linked"

    cat >>"$dir/Dockerfile" <<EOF

ENTRYPOINT ["/bin/sleep"]
EOF

    docker build -t "$PREFLIGHT_IMAGE" "$dir" >/dev/null
    rm -rf "$dir"
}

maybeRemoveDockerContainer()
{
    docker rm -f "$1" >/dev/null 2&>1 || true
}
