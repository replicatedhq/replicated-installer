
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
                _dockerProceedAnyway "$BEST_DOCKER_VERSION_RESULT"
            fi
        elif [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "1" ]; then
            # allow patch versions greater than the current version
            compareDockerVersionsIgnorePatch "$DOCKER_VERSION" "$BEST_DOCKER_VERSION_RESULT"
            if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "1" ]; then
                _dockerProceedAnyway "$BEST_DOCKER_VERSION_RESULT"
            fi
        fi
        # The system has the exact pinned version installed.
        # No need to run the Docker install script.
    fi
}

#######################################
# Install docker from a prepared image
# Globals:
#   LSB_DIST
#   INIT_SYSTEM
# Returns:
#   DID_INSTALL_DOCKER
#######################################
DID_INSTALL_DOCKER=0
installDockerOffline() {
    if commandExists "docker"; then
        return
    fi

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            mkdir -p image/
            layer_id=$(tar xvf packages-docker-ubuntu1604.tar -C image/ | grep layer.tar | cut -d'/' -f1)
            tar xvf image/${layer_id}/layer.tar
            pushd archives/
               dpkg -i --force-depends-version *.deb
            popd
            DID_INSTALL_DOCKER=1
            return
            ;;
        ubuntu18.04)
            mkdir -p image/
            layer_id=$(tar xvf packages-docker-ubuntu1804.tar -C image/ | grep layer.tar | cut -d'/' -f1)
            tar xvf image/${layer_id}/layer.tar
            pushd archives/
               dpkg -i --force-depends-version *.deb
            popd
            DID_INSTALL_DOCKER=1
            return
            ;;
        centos7.4|centos7.5|centos7.6|centos7.7|rhel7.4|rhel7.5|rhel7.6|rhel7.7)
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

   printf "Offline Docker install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
   exit 1
}

_installDocker() {
    _should_skip_docker_ee_install
    if [ "$SHOULD_SKIP_DOCKER_EE_INSTALL" -eq "1" ]; then
        printf "${RED}Enterprise Linux distributions require Docker Enterprise Edition. Please install Docker before running this installation script.${NC}\n" 1>&2
        exit 1
    fi

    if [ "$LSB_DIST" = "amzn" ]; then
        # Docker install script no longer supports Amazon Linux
        printf "${YELLOW}Pinning Docker version not supported on Amazon Linux${NC}\n"
        printf "${GREEN}Installing Docker from Yum repository${NC}\n"

        # 2020-05-11
        # Amazon Linux has Docker 17.12.1ce and Docker 18.09.9ce available.
        compareDockerVersions "18.0.0" "${1}"
        if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
            if commandExists "amazon-linux-extras"; then
                # NOTE: need to patch here with 18.09.2 or 18.06.2 when available.
                ( set -x; amazon-linux-extras install -y -q docker=18.09.9 || amazon-linux-extras install docker=18.09.9 || \
                    amazon-linux-extras install -y -q docker || amazon-linux-extras install docker )
            else
                ( set -x; yum install -y -q docker-18.09.9ce || yum install -y -q docker )
            fi
        else
            if commandExists "amazon-linux-extras"; then
                ( set -x; amazon-linux-extras install -y -q docker=17.12.1 || amazon-linux-extras install docker=17.12.1 \
                    || amazon-linux-extras install -y -q docker || amazon-linux-extras install docker )
            else
                ( set -x; yum install -y -q docker-17.12.1ce || yum install -y -q docker )
            fi
        fi

        service docker start || true
        DID_INSTALL_DOCKER=1
        return
    elif [ "$LSB_DIST" = "sles" ]; then
        printf "${YELLOW}Pinning Docker version not supported on SUSE Linux${NC}\n"
        printf "${GREEN}Installing Docker from Zypper repository${NC}\n"

        # 2020-05-11
        # SUSE has Docker 17.09.1_ce, 18.09.7_ce and 19.03.5 available.
        compareDockerVersions "19.0.0" "${1}"
        if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
            ( set -x; zypper -n install "docker=19.03.5_ce" || zypper -n install docker )
        else
            compareDockerVersions "18.0.0" "${1}"
            if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
                ( set -x; zypper -n install "docker=18.09.7_ce" || zypper -n install docker )
            else
                ( set -x; zypper -n install "docker=17.09.1_ce" || zypper -n install docker )
            fi
        fi

        service docker start || true
        DID_INSTALL_DOCKER=1
        return
    fi

    compareDockerVersions "17.06.0" "${1}"
    if { [ "$LSB_DIST" = "rhel" ] || [ "$LSB_DIST" = "ol" ] ; } && [ "$COMPARE_DOCKER_VERSIONS_RESULT" -le "0" ]; then
        if yum list installed "container-selinux" >/dev/null 2>&1; then
            # container-selinux installed
            printf "Skipping install of container-selinux as a version of it was already present\n"
        else
            # Install container-selinux from official source, ignoring errors
            yum install -y -q container-selinux 2> /dev/null || true
            # verify installation success
            if yum list installed "container-selinux" >/dev/null 2>&1; then
                printf "${GREEN}Installed container-selinux from existing sources${NC}\n"
            else
                if [ "$DIST_VERSION" = "7.6" ]; then
                    # Install container-selinux from mirror.centos.org
                    yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.107-1.el7_6.noarch.rpm"
                    if yum list installed "container-selinux" >/dev/null 2>&1; then
                        printf "${YELLOW}Installed package required by docker container-selinux from fallback source of mirror.centos.org${NC}\n"
                    else
                        printf "${RED}Failed to install container-selinux package, required by Docker CE. Please install the container-selinux package or Docker before running this installation script.${NC}\n"
                        exit 1
                    fi
                else
                    # Install container-selinux from mirror.centos.org
                    yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.107-3.el7.noarch.rpm"
                    if yum list installed "container-selinux" >/dev/null 2>&1; then
                        printf "${YELLOW}Installed package required by docker container-selinux from fallback source of mirror.centos.org${NC}\n"
                    else
                        printf "${RED}Failed to install container-selinux package, required by Docker CE. Please install the container-selinux package or Docker before running this installation script.${NC}\n"
                        exit 1
                    fi
                fi
            fi
        fi
    fi

    _docker_install_url="{{ replicated_install_url }}/docker-install.sh"
    printf "${GREEN}Installing docker version ${1} from ${_docker_install_url}${NC}\n"
    getUrlCmd
    $URLGET_CMD "$_docker_install_url?docker_version=${1}&lsb_dist=${LSB_DIST}&dist_version=${DIST_VERSION_MAJOR}" > /tmp/docker_install.sh
    # When this script is piped into bash as stdin, apt-get will eat the remaining parts of this script,
    # preventing it from being executed.  So using /dev/null here to change stdin for the docker script.
    VERSION="${1}" sh /tmp/docker_install.sh < /dev/null

    printf "${GREEN}External script is finished${NC}\n"

    # Need to manually start Docker in these cases
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl enable docker
        systemctl start docker
    elif [ "$LSB_DIST" = "centos" ] && [ "$DIST_VERSION_MAJOR" = "6" ]; then
        service docker start
    elif [ "$LSB_DIST" = "rhel" ] && [ "$DIST_VERSION_MAJOR" = "6" ]; then
        service docker start
    fi

    # i guess the second arg means to skip this?
    if [ "$2" -eq "1" ]; then
        # set +e because df --output='fstype' doesn't exist on older versions of rhel and centos
        set +e
        _maybeRequireRhelDevicemapper
        set -e
    fi

    DID_INSTALL_DOCKER=1
}

_maybeRequireRhelDevicemapper() {
    # If the distribution is CentOS or RHEL and the filesystem is XFS, it is possible that docker has installed with overlay as the device driver
    # In that case we should change the storage driver to devicemapper, because while loopback-lvm is slow it is also more likely to work
    if { [ "$LSB_DIST" = "centos" ] || [ "$LSB_DIST" = "rhel" ] ; } && { df --output='fstype' 2>/dev/null | grep -q -e '^xfs$' || grep -q -e ' xfs ' /etc/fstab ; } ; then
        # If distribution is centos or rhel and filesystem is XFS

        # xfs (RHEL 7.2 and higher), but only with d_type=true enabled. Use xfs_info to verify that the ftype option is set to 1.
        # https://docs.docker.com/storage/storagedriver/overlayfs-driver/#prerequisites
        oIFS="$IFS"; IFS=.; set -- $DIST_VERSION; IFS="$oIFS";
        _dist_version_minor=$2
        if [ "$DIST_VERSION_MAJOR" -eq "7" ] && [ "$_dist_version_minor" -ge "2" ] && xfs_info / | grep -q -e 'ftype=1'; then
            return
        fi

        # Get kernel version (and extract major+minor version)
        kernelVersion="$(uname -r)"
        semverParse $kernelVersion

        if docker info | grep -q -e 'Storage Driver: overlay2\?' && { ! xfs_info / | grep -q -e 'ftype=1' || [ $major -lt 3 ] || { [ $major -eq 3 ] && [ $minor -lt 18 ]; }; }; then
            # If storage driver is overlay and (ftype!=1 OR kernel version less than 3.18)
            printf "${YELLOW}Changing docker storage driver to devicemapper."
            printf "Using overlay/overlay2 requires CentOS/RHEL 7.2 or higher and ftype=1 on xfs filesystems.\n"
            printf "It is recommended to configure devicemapper to use direct-lvm mode for production.${NC}\n"
            systemctl stop docker

            insertOrReplaceJsonParam /etc/docker/daemon.json storage-driver devicemapper

            systemctl start docker
        fi
    fi
}

_dockerUpgrade() {
    _should_skip_docker_ee_install
    if [ "$SHOULD_SKIP_DOCKER_EE_INSTALL" -eq "1" ]; then
        return
    fi

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

#######################################
# Checks if Docker EE should be installed or upgraded.
# Globals:
#   LSB_DIST
#   NO_CE_ON_EE
# Returns:
#   SHOULD_SKIP_DOCKER_EE_INSTALL
#######################################
SHOULD_SKIP_DOCKER_EE_INSTALL=
_should_skip_docker_ee_install() {
  SHOULD_SKIP_DOCKER_EE_INSTALL=
  if [ "$LSB_DIST" = "rhel" ] || [ "$LSB_DIST" = "ol" ] || [ "$LSB_DIST" = "sles" ]; then
      if [ -n "$NO_CE_ON_EE" ]; then
          SHOULD_SKIP_DOCKER_EE_INSTALL=1
          return
      fi
  fi
  SHOULD_SKIP_DOCKER_EE_INSTALL=0
}
