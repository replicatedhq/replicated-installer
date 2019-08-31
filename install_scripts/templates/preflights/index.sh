###############################################################################
## index.sh
###############################################################################

{% include 'preflights/print.sh' %}

{% include 'preflights/disk.sh' %}
{% include 'preflights/docker.sh' %}
{% include 'preflights/firewalld.sh' %}
{% include 'preflights/iptables.sh' %}
{% include 'preflights/selinux.sh' %}

HAS_PREFLIGHT_WARNINGS=
HAS_PREFLIGHT_ERRORS=

###############################################################################
# Runs preflight checks
# Sets HAS_PREFLIGHT_WARNINGS=1 if there are any warnings
# Sets HAS_PREFLIGHT_ERRORS=1 if there are any errors
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   1 if there are errors
###############################################################################
runPreflights()
{
    HAS_PREFLIGHT_WARNINGS=0
    HAS_PREFLIGHT_ERRORS=0

    set +e
    if ! preflightDiskUsageRootDir; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDiskUsageDockerDataDir; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDiskUsageReplicatedDataDir; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDockerDevicemapperLoopback; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDockerHttpProxy; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDockerSeccompNonDefault; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDockerNonStandardRoot; then
        HAS_PREFLIGHT_ERRORS=1
    fi

    if ! preflightDockerIccDisabled; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDockerContainerRegistriesBlocked; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDockerUlimitNofileSet; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightDockerUserlandProxyDisabled; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightFirewalld; then
        HAS_PREFLIGHT_WARNINGS=1
    fi

    if ! preflightIptablesInputDrop; then
        HAS_PREFLIGHT_ERRORS=1
    fi

    if ! preflightSelinuxEnforcing; then
        HAS_PREFLIGHT_WARNINGS=1
    fi
    set -e

    if [ "$HAS_PREFLIGHT_ERRORS" = "1" ]; then
        return 1
    fi
    return 0
}
