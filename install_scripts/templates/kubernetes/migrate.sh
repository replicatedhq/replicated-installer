#!/bin/sh

set -e

TMP_DIR=/tmp/migrate-k8s
LOG_LEVEL=info
PRIVATE_ADDRESS=
AIRGAP=0
# If all state needed from the native app has been saved we can skip some steps
HAS_NATIVE_STATE=0
HAS_KUBERNETES=0
HAS_APP=0

{% include 'common/cli-script.sh' %}
{% include 'common/common.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/log.sh' %}
{% include 'common/system.sh' %}

startNativeScheduler() {
    logStep "Ensuring native scheduler is running"

    systemctl start replicated
    systemctl start replicated-operator
    systemctl start replicated-ui

    # ensure replicatedctl wrapper is for native
    if ! grep -q "sudo docker exec" "/usr/local/bin/replicatedctl" 2>/dev/null ; then
        installCliFile "sudo docker exec" "replicated"
    fi

    waitReplicatedctlReady
    waitNativeRetracedPostgresReady

    logSuccess "Native scheduler is running"
}

waitReplicatedctlReady() {
    for i in {1..30}; do
        if isReplicatedctlReady; then
            return 0
        fi
        sleep 2
    done
    return 1
}

isReplicatedctlReady() {
    replicatedctl system status 2>/dev/null | grep -q '"ready"'
}

getNativeEnv() {
    cat "$TMP_DIR/native.env" | grep "$1" | sed 's/=/ /g' | awk '{ print $2 }'
}

getK8sInitScript() {
    getUrlCmd
    if [ "$AIRGAP" != "1" ]; then
        $URLGET_CMD "{{ replicated_install_url }}/{{ kubernetes_init_path }}?{{ kubernetes_init_query }}" \
            > /tmp/kubernetes-init.sh
    else
        cp kubernetes-init.sh /tmp/kubernetes-init.sh
    fi
}

stopNativeScheduler() {
    logStep "Stopping native scheduler"
    systemctl stop replicated
    systemctl stop replicated-operator
    systemctl stop replicated-ui
    rm -f /usr/local/bin/replicatedctl /usr/local/bin/replicated
    logSuccess "Native scheduler stopped"
}

purgeNativeScheduler() {
    logStep "Removing native scheduler"
    # TODO
}

startK8sScheduler() {
    logStep "Installing Kubernetes scheduler"
    local logLevel=$(getNativeEnv LOG_LEVEL)
    if [ -n "$logLevel" ]; then
        LOG_LEVEL=$logLevel
    fi
    local localAddress=$(getNativeEnv LOCAL_ADDRESS)
    if [ -n "$localAddress" ]; then
        PRIVATE_ADDRESS=$localAddress
    fi
    getK8sInitScript
    bash /tmp/kubernetes-init.sh \
        no-clear \
        no-proxy \
        log-level="$LOG_LEVEL" \
        private-address="$PRIVATE_ADDRESS"
    logSuccess "Kubernetes scheduler installed"
}

exportNativeState() {
    logStep "Saving native app state to $TMP_DIR"
    docker exec replicated printenv | grep -E '^(LOCAL_ADDRESS|LOG_LEVEL)=' > "${TMP_DIR}/native.env"
    replicatedctl app-config export --hidden > "${TMP_DIR}/app-config.json"
    replicatedctl migration export > "${TMP_DIR}/migration.json"
    docker exec retraced-postgres /bin/bash -c 'PG_DATABASE=$POSTGRES_DATABASE PGHOST=$POSTGRES_HOST PGUSER=$POSTGRES_USER PGPASSWORD=$POSTGRES_PASSWORD pg_dump -c' > "${TMP_DIR}/retraced.sql"
    tar -cf "${TMP_DIR}/secrets.tar" -C /var/lib/replicated secrets
    logSuccess "Native app state saved"
}

# if all state needed from the native app has been saved, set the HAS_NATIVE_STATE flag to skip
# starting the native app. This could follow an interrupted migration.
checkNativeState() {
    if [ ! -f "${TMP_DIR}/native.env" ]; then
        return
    fi
    if [ ! -f "${TMP_DIR}/app-config.json" ]; then
        return
    fi
    if [ ! -f "${TMP_DIR}/migration.json" ]; then
        return
    fi
    if [ ! -f "${TMP_DIR}/retraced.sql" ]; then
        return
    fi
    if [ ! -f "${TMP_DIR}/secrets.tar" ]; then
        return
    fi

    HAS_NATIVE_STATE=1
}

# if Kubernetes is installed, set the HAS_KUBERNETES flag to avoid reinstalling
checkKubernetes() {
    if ! grep -q "kubectl exec" "/usr/local/bin/replicatedctl" 2>/dev/null ; then
        return
    fi
    if ! isReplicatedctlReady ; then
        return
    fi
    HAS_KUBERNETES=1
}

checkApp() {
    set +e
    if replicatedctl app status &>/dev/null ; then
        HAS_APP=1
    fi
    set -e
}

waitNativeRetracedPostgresReady() {
    set +e
    for i in {i..30}; do
        if docker exec retraced-postgres pg_isready -q ; then
            set -e
            return
        fi
    done
    echo "Timedout waiting for native Retraced Postgres to become ready"
    exit 1
}

restoreRetraced() {
    spinnerPodRunning "default" "retraced-postgres"
    # the server can take a bit to be ready for connections after the pod is running
    set +e
    for i in {1..30}; do
        cat "${TMP_DIR}/retraced.sql" | kubectl exec $(kubectl get pods | grep retraced-postgres | awk '{ print $1 }') -- \
            /bin/bash -c 'PG_DATABASE=$POSTGRES_DATABASE PGHOST=$POSTGRES_HOST PGUSER=$POSTGRES_USER PGPASSWORD=$POSTGRES_PASSWORD psql' &>/dev/null
        if [ "$?" -eq 0 ]; then
            set -e
            return
        fi
    done
    echo "Failed to restore audit log"
    exit 1
}

restoreSecrets() {
    local replPod=$(kubectl get pods --selector='app=replicated,tier=master' | tail -1 | awk '{ print $1 }')
    if [ -z "$replPod" ]; then
        echo "Cannot restore secrets: Replicated pod not found"
        return
    fi
    kubectl cp "${TMP_DIR}/secrets.tar" "$replPod":/tmp/secrets.tar -c replicated
    kubectl exec "$replPod" -c replicated -- tar -xf /tmp/secrets.tar -C /var/lib/replicated 
}

startAppOnK8s() {
    logStep "Restoring app state"
    waitReplicatedctlReady
    restoreRetraced
    restoreSecrets
    replicatedctl migration import < "${TMP_DIR}/migration.json"
    replicatedctl app-config import < "${TMP_DIR}/app-config.json"
}

################################################################################
# Execution starts here
################################################################################

requireRootUser

export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p "$TMP_DIR"

checkNativeState
if [ "$HAS_NATIVE_STATE" != "1" ]; then
    startNativeScheduler
    exportNativeState
fi

checkKubernetes
if [ "$HAS_KUBERNETES" != "1" ]; then
    stopNativeScheduler
    startK8sScheduler
fi

checkApp
if [ "$HAS_APP" != "1" ]; then
    startAppOnK8s
fi

logSuccess "App is running on Kubernetes"

purgeNativeScheduler
