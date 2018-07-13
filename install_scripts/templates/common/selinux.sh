
#######################################
#
# selinux.sh
#
# require common.sh docker-version.sh prompt.sh
#
#######################################

#######################################
# Check if SELinux is enabled
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Non-zero exit status unless SELinux is enabled
#######################################
selinux_enabled() {
    if commandExists "selinuxenabled"; then
        selinuxenabled
        return
    elif commandExists "sestatus"; then
        ENABLED=$(sestatus | grep 'SELinux status' | awk '{ print $3 }')
        echo "$ENABLED" | grep --quiet --ignore-case enabled
        return
    fi

    return 1
}

#######################################
# Check if SELinux is enforced
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Non-zero exit status unelss SELinux is enforced
#######################################
selinux_enforced() {
    if commandExists "getenforce"; then
        ENFORCED=$(getenforce)
        echo $(getenforce) | grep --quiet --ignore-case enforcing
        return
    elif commandExists "sestatus"; then
        ENFORCED=$(sestatus | grep 'SELinux mode' | awk '{ print $3 }')
        echo "$ENFORCED" | grep --quiet --ignore-case enforcing
        return
    fi

    return 1
}

SELINUX_REPLICATED_DOMAIN_LABEL=
get_selinux_replicated_domain_label() {
    getDockerVersion

    compareDockerVersions "$DOCKER_VERSION" "1.11.0"
    if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
        SELINUX_REPLICATED_DOMAIN_LABEL="label:type:$SELINUX_REPLICATED_DOMAIN"
    else
        SELINUX_REPLICATED_DOMAIN_LABEL="label=type:$SELINUX_REPLICATED_DOMAIN"
    fi
}

#######################################
# Prints a warning if selinux is enabled and enforcing
# Globals:
#   None
# Arguments:
#   Mode - either permissive or enforcing
# Returns:
#   None
#######################################
warn_if_selinux() {
    if selinux_enabled ; then
        if selinux_enforced ; then
            printf "${YELLOW}SELinux is enforcing. Running docker with the \"--selinux-enabled\" flag may cause some features to become unavailable.${NC}\n\n"
        else
            printf "${YELLOW}SELinux is enabled. Switching to enforcing mode and running docker with the \"--selinux-enabled\" flag may cause some features to become unavailable.${NC}\n\n"
        fi
    fi
}

#######################################
# Prompts to confirm disabling of SELinux for K8s installs, bails on decline.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
must_disable_selinux() {
    # From kubernets kubeadm docs for RHEL:
    #
    #    Disabling SELinux by running setenforce 0 is required to allow containers to
    #    access the host filesystem, which is required by pod networks for example.
    #    You have to do this until SELinux support is improved in the kubelet.
    if selinux_enabled && selinux_enforced ; then
        printf "\n${YELLOW}Kubernetes is incompatible with SELinux. Disable SELinux to continue?${NC} "
        if confirmY ; then
            setenforce 0
            sed -i s/^SELINUX=.*$/SELINUX=permissive/ /etc/selinux/config
        else
            bail "\nDisable SELinux with 'setenforce 0' before re-running install script"
        fi
    fi

    # https://github.com/containers/container-selinux/issues/51
    # required for CoreDNS because it sets allowPrivilegeEscalation: false
    if selinux_enabled ; then
        mkdir policy
        cd policy
        # tabs required
        cat <<-EOF > dockersvirt.te
		module dockersvirt 1.0;

		require {
			type container_runtime_t;
			type svirt_lxc_net_t;
			role system_r;
		};

		typebounds container_runtime_t svirt_lxc_net_t;
		EOF

        checkmodule -M -m -o dockersvirt.mod dockersvirt.te
        semodule_package -o dockersvirt.pp -m dockersvirt.mod
        semodule -i dockersvirt.pp

        cd ..
        # TODO
        # rm -r policy
    fi
}
