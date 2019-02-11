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
AIRGAP_LICENSE_PATH=
AIRGAP_PACKAGE_PATH=
INIT_FLAGS="no-clear no-proxy" # TOOD proxy

{% include 'common/cli-script.sh' %}
{% include 'common/common.sh' %}
{% include 'common/kubernetes.sh' %}
{% include 'common/log.sh' %}
{% include 'common/system.sh' %}

startNativeScheduler() {
    logStep "Ensuring native scheduler is running"

    # online installs can co-exist but airgap installs bind the same host ports
    if [ "$AIRGAP" = "1" ] && commandExists "kubectl" ; then
        logSubstep "stop replicated pod"
        kubectl delete services replicated replicated-ui &>/dev/null || true
    fi

    logSubstep "start systemd services"
    systemctl start replicated
    systemctl start replicated-operator
    systemctl start replicated-ui

    # ensure replicatedctl wrapper is for native
    logSubstep "configure replicatedctl for native scheduler"
    if ! grep -q "sudo docker exec" "/usr/local/bin/replicatedctl" 2>/dev/null ; then
        installCliFile "sudo docker exec" "replicated"
    fi

    logSubstep "wait for native daemon to report ready"
    waitReplicatedctlReady
    checkVersion

    logSubstep "wait for audit log database"
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

checkVersion() {
    local version=$(replicatedctl version | awk '{ print $3 }')
    semverParse "$version"
    if [ "$minor" -lt 33 ]; then
        bail "Migrations require Replicated >= 2.33.0"
    fi
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

    logSubstep "stop systemd services"
    systemctl stop replicated
    systemctl stop replicated-operator
    systemctl stop replicated-ui

    logSubstep "remove replicatedctl native configuration"
    rm -f /usr/local/bin/replicatedctl /usr/local/bin/replicated

    logSuccess "Native scheduler stopped"
}

purgeNativeScheduler() {
    logStep "Removing native scheduler"
    # TODO
    logSuccess "Removed native scheduler"
}

startK8sScheduler() {
    logStep "Installing Kubernetes scheduler"
    # prepend flags inferred from native install so they can be overridden
    local logLevel=$(getNativeEnv LOG_LEVEL)
    if [ -n "$logLevel" ]; then
        INIT_FLAGS="log-level=$logLevel $INIT_FLAGS"
    fi
    local localAddress=$(getNativeEnv LOCAL_ADDRESS)
    if [ -n "$localAddress" ]; then
        INIT_FLAGS="private-address=$localAddress $INIT_FLAGS"
    fi
    getK8sInitScript
    bash /tmp/kubernetes-init.sh $INIT_FLAGS
    logSuccess "Kubernetes scheduler installed"
}

exportNativeState() {
    logStep "Saving native app state to $TMP_DIR"

    logSubstep "export native environment"
    docker exec replicated printenv | grep -E '^(LOCAL_ADDRESS|LOG_LEVEL)=' > "${TMP_DIR}/native.env"

    logSubstep "export app config"
    replicatedctl app-config export --hidden > "${TMP_DIR}/app-config.json"

    logSubstep "export console settings"
    replicatedctl migration export > "${TMP_DIR}/migration.json"

    logSubstep "export audit log"
    docker exec retraced-postgres /bin/bash -c 'PG_DATABASE=$POSTGRES_DATABASE PGHOST=$POSTGRES_HOST PGUSER=$POSTGRES_USER PGPASSWORD=$POSTGRES_PASSWORD pg_dump -c' > "${TMP_DIR}/retraced.sql"

    logSubstep "export certificates"
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
    for i in {1..30}; do
        if docker exec retraced-postgres pg_isready -q ; then
            set -e
            return
        fi
        sleep 2
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
        sleep 2
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

    logSubstep "wait for daemon pod to report ready"
    waitReplicatedctlReady

    logSubstep "restore audit log"
    restoreRetraced

    logSubstep "restore certificates"
    restoreSecrets

    logSubstep "restore console settings"
    replicatedctl migration import < "${TMP_DIR}/migration.json"
    waitReplicatedctlReady # the migration import may cause the daemon to restart

    if [ "$AIRGAP" = "1" ]; then
        logSubstep "load airgap license"
        replicatedctl license-load --airgap-package="$AIRGAP_PACKAGE_PATH" < "$AIRGAP_LICENSE_PATH"
    fi

    logSubstep "restore app config"
    replicatedctl app-config import < "${TMP_DIR}/app-config.json"
}

validate() {
    if [ "$AIRGAP" = "1" ]; then
        if [ -z "$AIRGAP_LICENSE_PATH" ]; then
            bail "airgap-license-path is required for airgap installs"
            exit 1
        fi
        if [ -z "$AIRGAP_PACKAGE_PATH" ]; then
            bail "airgap-package-path is required for airgap installs"
        fi

        # ensure package path exists
        AIRGAP_PACKAGE_PATH=$(realpath $AIRGAP_PACKAGE_PATH)
        if [ ! -f "$AIRGAP_PACKAGE_PATH" ]; then
            bail "airgap-package-path file not found: $AIRGAP_PACKAGE_PATH"
        fi
        if [ ! -f "$AIRGAP_LICENSE_PATH" ]; then
            bail "airgap-license-path file not found: $AIRGAP_LICENSE_PATH"
        fi
    else
        if [ -n "$AIRGAP_LICENSE_PATH" ]; then
            bail "airgap flag is required with airgap-license-path"
        fi
        if [ -n "$AIRGAP_PACKAGE_PATH" ]; then
            bail "airgap package path is required with airgap-package-path"
        fi
    fi
}

################################################################################
# Execution starts here
################################################################################

requireRootUser

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            AIRGAP=1
            INIT_FLAGS="$INIT_FLAGS airgap"
            ;;
        airgap-license-path|airgap_license_path)
            AIRGAP_LICENSE_PATH="$_value"
            ;;
        airgap-package-path|airgap_package_path)
            AIRGAP_PACKAGE_PATH="$_value"
            ;;
        *)
            INIT_FLAGS="$INIT_FLAGS $_param=$_value"
            ;;
    esac
    shift
done

validate

export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p "$TMP_DIR"

checkKubernetes
checkNativeState
if [ "$HAS_NATIVE_STATE" != "1" ]; then
    startNativeScheduler
    exportNativeState
fi

if [ "$HAS_KUBERNETES" != "1" ]; then
    stopNativeScheduler
    startK8sScheduler
fi
checkVersion

checkApp
if [ "$HAS_APP" != "1" ]; then
    startAppOnK8s
fi
logSuccess "App is installed on Kubernetes"

purgeNativeScheduler
