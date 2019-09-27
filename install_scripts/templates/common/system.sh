
#######################################
#
# system.sh
#
#######################################

#######################################
# Requires a 64 bit platform or exits with an error.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
require64Bit() {
    case "$(uname -m)" in
        *64)
            ;;
        *)
            echo >&2 'Error: you are not using a 64bit platform.'
            echo >&2 'This installer currently only supports 64bit platforms.'
            exit 1
            ;;
    esac
}

#######################################
# Requires that the script be run with the root user.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   USER
#######################################
USER=
requireRootUser() {
    USER="$(id -un 2>/dev/null || true)"
    if [ "$USER" != "root" ]; then
        echo >&2 "Error: This script requires admin privileges. Please re-run it as root."
        exit 1
    fi
}

#######################################
# Detects the linux distribution.
# Upon failure exits with an error.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   LSB_DIST
#   DIST_VERSION - should be MAJOR.MINOR e.g. 16.04 or 7.4
#   DIST_VERSION_MAJOR
#######################################
LSB_DIST=
DIST_VERSION=
DIST_VERSION_MAJOR=
detectLsbDist() {
    _dist=
    _error_msg="We have checked /etc/os-release and /etc/centos-release files."
    if [ -f /etc/centos-release ] && [ -r /etc/centos-release ]; then
        # CentOS 6 example: CentOS release 6.9 (Final)
        # CentOS 7 example: CentOS Linux release 7.5.1804 (Core)
        _dist="$(cat /etc/centos-release | cut -d" " -f1)"
        _version="$(cat /etc/centos-release | sed 's/Linux //' | cut -d" " -f3 | cut -d "." -f1-2)"
    elif [ -f /etc/os-release ] && [ -r /etc/os-release ]; then
        _dist="$(. /etc/os-release && echo "$ID")"
        _version="$(. /etc/os-release && echo "$VERSION_ID")"
    elif [ -f /etc/redhat-release ] && [ -r /etc/redhat-release ]; then
        # this is for RHEL6
        _dist="rhel"
        _major_version=$(cat /etc/redhat-release | cut -d" " -f7 | cut -d "." -f1)
        _minor_version=$(cat /etc/redhat-release | cut -d" " -f7 | cut -d "." -f2)
        _version=$_major_version
    elif [ -f /etc/system-release ] && [ -r /etc/system-release ]; then
        if grep --quiet "Amazon Linux" /etc/system-release; then
            # Special case for Amazon 2014.03
            _dist="amzn"
            _version=`awk '/Amazon Linux/{print $NF}' /etc/system-release`
        fi
    else
        _error_msg="$_error_msg\nDistribution cannot be determined because neither of these files exist."
    fi

    if [ -n "$_dist" ]; then
        _error_msg="$_error_msg\nDetected distribution is ${_dist}."
        _dist="$(echo "$_dist" | tr '[:upper:]' '[:lower:]')"
        case "$_dist" in
            ubuntu)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 12."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 12 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            debian)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 7."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 7 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            fedora)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 21."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 21 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            rhel)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 6."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            centos)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 6."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            amzn)
                _error_msg="$_error_msg\nHowever detected version $_version is not one of\n    2, 2.0, 2018.03, 2017.09, 2017.03, 2016.09, 2016.03, 2015.09, 2015.03, 2014.09, 2014.03."
                [ "$_version" = "2" ] || [ "$_version" = "2.0" ] || \
                [ "$_version" = "2018.03" ] || \
                [ "$_version" = "2017.03" ] || [ "$_version" = "2017.09" ] || \
                [ "$_version" = "2016.03" ] || [ "$_version" = "2016.09" ] || \
                [ "$_version" = "2015.03" ] || [ "$_version" = "2015.09" ] || \
                [ "$_version" = "2014.03" ] || [ "$_version" = "2014.09" ] && \
                LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$_version
                ;;
            sles)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 12."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 12 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            ol)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 6."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            *)
                _error_msg="$_error_msg\nThat is an unsupported distribution."
                ;;
        esac
    fi

    if [ -z "$LSB_DIST" ]; then
        echo >&2 "$(echo | sed "i$_error_msg")"
        echo >&2 ""
        echo >&2 "Please visit the following URL for more detailed installation instructions:"
        echo >&2 ""
        echo >&2 "  https://help.replicated.com/docs/distributing-an-application/installing/"
        exit 1
    fi
}

#######################################
# Detects the init system.
# Upon failure exits with an error.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   INIT_SYSTEM
#######################################
INIT_SYSTEM=
detectInitSystem() {
    if [[ "$(/sbin/init --version 2>/dev/null)" =~ upstart ]]; then
        INIT_SYSTEM=upstart
    elif [[ "$(systemctl 2>/dev/null)" =~ -\.mount ]]; then
        INIT_SYSTEM=systemd
    elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
        INIT_SYSTEM=sysvinit
    else
        echo >&2 "Error: failed to detect init system or unsupported."
        exit 1
    fi
}

#######################################
# Finds the init system conf dir. One of /etc/default, /etc/sysconfig
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   CONFDIR
#######################################
CONFDIR=
detectInitSystemConfDir() {
    # NOTE: there was a bug in support bundle that creates a dir in place of non-existant conf files
    if [ -d /etc/default/replicated ] || [ -d /etc/default/replicated-operator ]; then
        if [ -d /etc/default/replicated ]; then
            rm -rf /etc/default/replicated
        fi
        if [ -d /etc/default/replicated-operator ]; then
            rm -rf /etc/default/replicated-operator
        fi
        if [ ! "$(ls -A /etc/default 2>/dev/null)" ]; then
            # directory is empty, probably exists because of support bundle
            rm -rf /etc/default
        fi
    fi
    if [ -d /etc/sysconfig/replicated ] || [ -d /etc/sysconfig/replicated-operator ]; then
        if [ -d /etc/sysconfig/replicated ]; then
            rm -rf /etc/sysconfig/replicated
        fi
        if [ -d /etc/sysconfig/replicated-operator ]; then
            rm -rf /etc/sysconfig/replicated-operator
        fi
        if [ ! "$(ls -A /etc/sysconfig 2>/dev/null)" ]; then
            # directory is empty, probably exists because of support bundle
            rm -rf /etc/sysconfig
        fi
    fi

    # prefer dir if config is already found
    if [ -f /etc/default/replicated ] || [ -f /etc/default/replicated-operator ]; then
        CONFDIR="/etc/default"
    elif [ -f /etc/sysconfig/replicated ] || [ -f /etc/sysconfig/replicated-operator ]; then
        CONFDIR="/etc/sysconfig"
    elif [ "$INIT_SYSTEM" = "systemd" ] && [ -d /etc/sysconfig ]; then
        CONFDIR="/etc/sysconfig"
    else
        CONFDIR="/etc/default"
    fi
    mkdir -p "$CONFDIR"
}

#######################################
# prevent a package from being automatically updated
# Globals:
#   LSB_DIST
# Arguments:
#   None
# Returns:
#   None
#######################################
lockPackageVersion() {
    case $LSB_DIST in
        rhel|centos)
            yum install -y yum-plugin-versionlock
            yum versionlock ${1}-*
            ;;
        ubuntu)
            apt-mark hold $1
            ;;
    esac
}
