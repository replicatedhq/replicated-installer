###############################################################################
## disk.sh
###############################################################################

###############################################################################
# Determine if root disk usage is over 83% threshold
###############################################################################
preflightDiskUsageRootDir()
{
    preflightDiskUsage / 83
}

###############################################################################
# Determine if /var/lib/docker disk usage is over 83% threshold
###############################################################################
preflightDiskUsageDockerDataDir()
{
    if ! commandExists "docker"; then
        return 0
    fi
    preflightDiskUsage /var/lib/docker 83
}

###############################################################################
# Determine if /var/lib/replicated disk usage is over 83% threshold
###############################################################################
preflightDiskUsageReplicatedDataDir()
{
    if ! commandExists "replicatedctl"; then
        return 0
    fi
    preflightDiskUsage /var/lib/replicated 83
}

preflightDiskUsage()
{
    local dir="$1"
    local threshold="$2"
    if [ ! -d "$dir" ]; then
        return 0
    fi

    getDiskUsagePcent "$dir"
    if [ "$DISK_USAGE_PCENT" -ge "$threshold" ]; then
        warn "$dir disk usage is at ${DISK_USAGE_PCENT}%%"
        return 1
    fi
    info "$dir disk usage is at ${DISK_USAGE_PCENT}%%"
    return 0
}

getDiskUsagePcent()
{
    DISK_USAGE_PCENT="$(df "$1" | awk 'NR==2 {print $5}' | sed 's/%//')"
}
