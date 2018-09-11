
#######################################
#
# docker-install.sh
#
# require common.sh, prompt.sh, system.sh, docker-version.sh
#
#######################################

#######################################
# Installs requested docker version.
# Requires at least min docker version to proceed.
# Globals:
#   LSB_DIST
#   INIT_SYSTEM
#   AIRGAP
# Arguments:
#   Requested Docker Version
#   Minimum Docker Version
# Returns:
#   DID_INSTALL_DOCKER
#######################################
DID_INSTALL_DOCKER=0
installDocker() {
    _dockerGetBestVersion "$1"

    if ! commandExists "docker"; then
        _dockerRequireMinInstallableVersion "$2"
        _installDocker "$BEST_DOCKER_VERSION_RESULT" 1
        return
    fi

    getDockerVersion

    compareDockerVersions "$DOCKER_VERSION" "$2"
    if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
        _dockerRequireMinInstallableVersion "$2"
        _dockerForceUpgrade "$BEST_DOCKER_VERSION_RESULT"
    else
        compareDockerVersions "$DOCKER_VERSION" "$BEST_DOCKER_VERSION_RESULT"
        if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
            _dockerUpgrade "$BEST_DOCKER_VERSION_RESULT"
            if [ "$DID_INSTALL_DOCKER" -ne "1" ]; then
                _dockerProceedAnyway
            fi
        elif [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "1" ]; then
            _dockerProceedAnyway "$BEST_DOCKER_VERSION_RESULT"
        fi
        # The system has the exact pinned version installed.
        # No need to run the Docker install script.
    fi
}


#######################################
# Installs requested docker version.
# Requires at least min docker version to proceed.
# Globals:
#   LSB_DIST
#   INIT_SYSTEM
# Returns:
#   DID_INSTALL_DOCKER
#######################################
DID_INSTALL_DOCKER=0
installDocker_1_12_Offline() {
    if commandExists "docker"; then
        return
    fi

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            mkdir -p image/
            layer_id=$(tar xvf packages-docker-ubuntu1604.tar -C image/ | grep layer.tar | cut -d'/' -f1)
            tar xvf image/${layer_id}/layer.tar
            pushd archives/
               dpkg -i *.deb
            popd
            DID_INSTALL_DOCKER=1
            return
            ;;
        rhel7.4|rhel7.5|centos7.4|centos7.5)
            mkdir -p image/
            layer_id=$(tar xvf packages-docker-rhel7.tar -C image/ | grep layer.tar | cut -d'/' -f1)
            tar xvf image/${layer_id}/layer.tar
            pushd archives/
                rpm --upgrade --force --nodeps *.rpm
            popd
            DID_INSTALL_DOCKER=1
            return
            ;;
        *)
   esac

   printf "Offline Docker install is not surpported on ${LSB_DIST} ${DIST_MAJOR}"
   exit 1
}

######################################
# For RHEL and derivatives install from yum docker repo
# Globals:
#   LSB_DIST
# Arguments:
#   Requested Docker Version
#   Minimum Docker Version
# Returns:
#   DID_INSTALL_DOCKER
######################################
installDockerK8s() {
    case "$LSB_DIST" in
        rhel|centos)
            yum install -y -q docker
            DID_INSTALL_DOCKER=1
            return
        ;;
    esac

    installDocker $1 $2
}

_installDocker() {
    if [ "$LSB_DIST" = "rhel" ] || [ "$LSB_DIST" = "ol" ] || [ "$LSB_DIST" = "sles" ]; then
        if [ -n "$NO_CE_ON_EE" ]; then
            printf "${RED}Enterprise Linux distributions require Docker Enterprise Edition. Please install Docker before running this installation script.${NC}\n" 1>&2
            exit 1
        fi
    fi

    if [ "$LSB_DIST" = "amzn" ]; then
        # Docker install script no longer supports Amazon Linux
        printf "${YELLOW}Pinning Docker version not supported on Amazon Linux${NC}\n"
        printf "${GREEN}Installing Docker from Yum repository${NC}\n"
        
        # 6/12/18
        # Amazon Linux 14.03, 17.03, and 18.03 have Docker 17.12.1ce and Docker
        # 18.03.1ce available. Amazon Linux 2 has Docker 17.06.2ce available.
        # Attempt to install 17.12.1 until we support 18.XX.
        yum -y -q install docker-17.12.1ce || yum -y -q install docker

        service docker start || true
        DID_INSTALL_DOCKER=1
        return
    elif [ "$LSB_DIST" = "sles" ]; then
        # Docker install script no longer supports SUSE
        # SUSE vesions as of now are 17.09.1, 17.04.0, 1.12.6 ...
        printf "${GREEN}Installing docker from Zypper repository${NC}\n"
        compareDockerVersions "17.0.0" "${1}"
        if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
            compareDockerVersions "17.09.0" "${1}"
            if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
                sudo zypper -n install "docker=${1}_ce"
            else
                sudo zypper -n install "docker=17.04.0_ce"
            fi
        else
            sudo zypper -n install "docker=1.12.6"
        fi
        service docker start || true
        DID_INSTALL_DOCKER=1
        return
    fi

    # TODO: does this affect 17.12?
    if { [ "$LSB_DIST" = "rhel" ] || [ "$LSB_DIST" = "ol" ] ; } && [ "$DIST_VERSION_MAJOR" = "7" ] && [[ "${1}" == *"17.06"* ]]; then
        if yum list installed "container-selinux" >/dev/null 2>&1; then
            # container-selinux installed
            printf "Skipping install of container-selinux as a version of it was already present\n"
        else
            # Install container-selinux from official source, ignoring errors
            yum install -y -q container-selinux 2> /dev/null || true
            # verify installation success
            if yum list installed "container-selinux" >/dev/null 2>&1; then
                printf "{$GREEN}Installed container-selinux from existing sources{$NC}\n"
            else
                # Install container-selinux from mirror.centos.org
                yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.42-1.gitad8f0f7.el7.noarch.rpm" || \
                    yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.33-1.git86f33cd.el7.noarch.rpm"
                if yum list installed "container-selinux" >/dev/null 2>&1; then
                    printf "${YELLOW}Installed package required by docker container-selinux from fallback source of mirror.centos.org${NC}\n"
                else
                    printf "${RED}Failed to install container-selinux package, required by Docker CE. Please install the container-selinux package or Docker before running this installation script.${NC}\n"
                    exit 1
                fi
            fi
        fi
    fi

    _docker_install_url="{{ replicated_install_url }}/docker-install.sh"
    printf "${GREEN}Installing docker from ${_docker_install_url}${NC}\n"
    getUrlCmd
    $URLGET_CMD "$_docker_install_url?docker_version=${1}&lsb_dist=${LSB_DIST}&dist_version=${DIST_VERSION_MAJOR}" > /tmp/docker_install.sh
    # When this script is piped into bash as stdin, apt-get will eat the remaining parts of this script,
    # preventing it from being executed.  So using /dev/null here to change stdin for the docker script.
    sh /tmp/docker_install.sh < /dev/null

    printf "${GREEN}External script is finished${NC}\n"

    # Need to manually start Docker in these cases
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl enable docker
        systemctl start docker
    elif [ "$LSB_DIST" = "centos" ]; then
        if [ "$(cat /etc/centos-release | cut -d" " -f3 | cut -d "." -f1)" = "6" ]; then
            service docker start
        fi
    fi

    # If the distribution is CentOS or RHEL and the filesystem is XFS, it is possible that docker has installed with overlay as the device driver
    # In that case we should change the storage driver to devicemapper, because while loopback-lvm is slow it is also more likely to work
    # set +e because df --output='fstype' doesn't exist on older versions of rhel and centos
    set +e
    if [ $2 -eq 1 ] && { [ "$LSB_DIST" = "centos" ] || [ "$LSB_DIST" = "rhel" ] ; } && { df --output='fstype' | grep -q -e '^xfs$' || grep -q -e ' xfs ' /etc/fstab ; } ; then
        # If distribution is centos or rhel and filesystem is XFS

        # Get kernel version (and extract major+minor version)
        kernelVersion="$(uname -r)"
        semverParse $kernelVersion

        if docker info | grep -q -e 'Storage Driver: overlay2\?' && { ! xfs_info / | grep -q -e 'ftype=1' || [ $major -lt 3 ] || { [ $major -eq 3 ] && [ $minor -lt 18 ]; }; }; then
            # If storage driver is overlay and (ftype!=1 OR kernel version less than 3.18)
            printf "${YELLOW}Changing docker storage driver to devicemapper as using overlay/overlay2 requires ftype=1 on xfs filesystems and requires kernel 3.18 or higher.\n"
            printf "It is recommended to configure devicemapper to use direct-lvm mode for production.${NC}\n"
            systemctl stop docker

            insertOrReplaceJsonParam /etc/docker/daemon.json storage-driver devicemapper

            systemctl start docker
        fi
    fi
    set -e

    DID_INSTALL_DOCKER=1
}

_dockerUpgrade() {
    if [ "$AIRGAP" != "1" ]; then
        printf "This installer will upgrade your current version of Docker (%s) to the recommended version: %s\n" "$DOCKER_VERSION" "$1"
        printf "Do you want to allow this? "
        if confirmY; then
            _installDocker "$1" 0
            return
        fi
    fi
}

_dockerForceUpgrade() {
    if [ "$AIRGAP" -eq "1" ]; then
        echo >&2 "Error: The installed version of Docker ($DOCKER_VERSION) may not be compatible with this installer."
        echo >&2 "Please manually upgrade your current version of Docker to the recommended version: $1"
        exit 1
    fi

    _dockerUpgrade "$1"
    if [ "$DID_INSTALL_DOCKER" -ne "1" ]; then
        printf "Please manually upgrade your current version of Docker to the recommended version: %s\n" "$1"
        exit 0
    fi
}

_dockerProceedAnyway() {
    printf "The installed version of Docker (%s) may not be compatible with this installer.\nThe recommended version is %s\n" "$DOCKER_VERSION" "$1"
    printf "Do you want to proceed anyway? "
    if ! confirmN; then
        exit 0
    fi
}

_dockerGetBestVersion() {
    BEST_DOCKER_VERSION_RESULT="$1"
    getMaxDockerVersion
    if [ -n "$MAX_DOCKER_VERSION_RESULT" ]; then
        compareDockerVersions "$BEST_DOCKER_VERSION_RESULT" "$MAX_DOCKER_VERSION_RESULT"
        if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "1" ]; then
            BEST_DOCKER_VERSION_RESULT="$MAX_DOCKER_VERSION_RESULT"
        fi
    fi
}

_dockerRequireMinInstallableVersion() {
    getMaxDockerVersion
    if [ -z "$MAX_DOCKER_VERSION_RESULT" ]; then
        return
    fi

    compareDockerVersions "$1" "$MAX_DOCKER_VERSION_RESULT"
    if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "1" ]; then
        echo >&2 "Error: This install script may not be compatible with this linux distribution."
        echo >&2 "We have detected a maximum docker version of $MAX_DOCKER_VERSION_RESULT while the required minimum version for this script is $1."
        exit 1
    fi
}
