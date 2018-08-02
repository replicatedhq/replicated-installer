
#######################################
#
# swap.sh
#
# require common.sh docker-version.sh prompt.sh log.sh
#
#######################################

#######################################
# Check if swap is enabled
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Non-zero exit status unless swap is enabled
#######################################
swapEnabled() {
  swapon --summary | grep --quiet " " # todo this could be more specific, swapon -s returns nothing if its off
}

#######################################
# Check if swap is configured in /etc/fstab
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Non-zero exit status unless swap partitions are configured
#######################################
swapConfigured() {
    cat /etc/fstab | grep --quiet --ignore-case --extended-regexp '^[^#]+swap'
}


#######################################
# check if swap is enabled, if so prompt to disable it. Otherwise exit 1 via "bail"
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
mustSwapoff() {
    if swapEnabled || swapConfigured ; then
        printf "\n${YELLOW}This application is incompatible with memory swapping enabled. Disable swap to continue?${NC} "
        if confirmY ; then
            printf "=> Running swapoff --all\n"
            swapoff --all
            if swapConfigured ; then
              printf "=> Commenting swap entries in /etc/fstab \n"
              sed --in-place=.bak '/\bswap\b/ s/^/#/' /etc/fstab
              printf "=> A backup of /etc/fstab has been made at /etc/fstab.bak\n\n"
              printf "\n${YELLOW}Changes have been made to /etc/fstab. We recommend reviewing them after completing this installation to ensure mounts are correctly configured.${NC}\n\n"
              sleep 5 # for emphasis of the above ^
            fi
            logSuccess "Swap disabled.\n"
        else
            bail "\nDisable swap with swapoff --all and remove all swap entries from /etc/fstab before re-running this script"
        fi
    fi
}
