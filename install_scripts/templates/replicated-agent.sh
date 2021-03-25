#!/bin/sh
set -e

CONFIG_DIR=/etc/replicated-agent
CONFIG_FILE=/etc/replicated-agent.conf
AUTOCONFIG_FILE=${CONFIG_DIR}/autoconfig.conf

check_daemon_ip() {
  VAL_STR=$(grep -Po '"ReplicatedDaemonIp":.*?[^\\]"' ${AUTOCONFIG_FILE}) || printf "Could not determine daemon IP address\n"
  if [ -z "${VAL_STR}" ]
  then
    exit 1
  fi

  OIFS=$IFS
  IFS=':'
  set -- $VAL_STR
  IFS=$OIFS

  IP=$2
  if [ {{ '${#IP}' }} -lt 9 ] # 9 because ip will have quotes around it
  then
    printf "Daemon IP address is invalid.  ${AUTOCONFIG_FILE} file may be corrupted\n"
    exit 1
  else
    printf "Will use daemon IP=${IP}\n"
  fi
}

save_autoconfig() {
  if [ -s ${AUTOCONFIG_FILE} ]
  then
    check_daemon_ip
    echo "Will not replace ${AUTOCONFIG_FILE}"
  else
    if [ -z "${DAEMON_ADDRESS}" ]
    then
      printf "Daemon IP address is required.  Use the daemon_address=<ip> option\n"
      exit 1
    fi

    if [ -z "${SECURE_TOKEN}" ]
    then
      printf "Secure token is required.  Use secure_token=<token> option\n"
      printf "The token can be found on the Hosts screen in Replicated console.\n"
      exit 1
    fi

    mkdir -p ${CONFIG_DIR}
    cat > ${AUTOCONFIG_FILE}  <<EOF
{
  "SelfRegister":true,
  "PatchServerPort":"9873",
  "ReplicatedDaemonIp":"${DAEMON_ADDRESS}",
  "SecureToken":"${SECURE_TOKEN}"
}
EOF
  fi
}

save_config() {
  if [ -s ${CONFIG_FILE} ]
  then
    echo "Will not replace ${CONFIG_FILE}"
  else
    if [ -n "${PRIVATE_IP}" ] || [ -n "${HOST_ID}" ]
    then
      printf "{\n" > ${CONFIG_FILE} >> ${CONFIG_FILE}
      if [ -n "${PRIVATE_IP}" ]
      then
        if [ -n "${HOST_ID}" ]
        then
          printf "\t\"LocalAddress\":\"${PRIVATE_IP}\",\n" >> ${CONFIG_FILE}
        else
          printf "\t\"LocalAddress\":\"${PRIVATE_IP}\"\n" >> ${CONFIG_FILE}
        fi
      fi
      if [ -n "${HOST_ID}" ]
      then
        printf "\t\"HostId\":\"${HOST_ID}\"\n" >> ${CONFIG_FILE}
      fi
      printf "}\n" >> ${CONFIG_FILE}
    fi
  fi
}

command_exists() {
    command -v "$@" > /dev/null 2>&1
}

if [ -z "$REPLICATED_TEMP_DIR" ]; then
    REPLICATED_TEMP_DIR="$(mktemp -d --suffix=replicated)"
fi

case "$(uname -m)" in
    *64)
        ;;
    *)
        echo >&2 'Error: you are not using a 64bit platform.'
        echo >&2 'Replicated currently only supports 64bit platforms.'
        exit 1
        ;;
esac

user="$(id -un 2>/dev/null || true)"

sh_c='sh -c'
if [ "$user" != 'root' ]; then
    if command_exists sudo; then
        sh_c='sudo -E sh -c'
    elif command_exists su; then
        sh_c='su -c'
    else
        echo >&2 'Error: this installer needs the ability to run commands as root.'
        echo >&2 'We are unable to find either "sudo" or "su" available to make this happen.'
        exit 1
    fi
fi

curl=''
if command_exists curl; then
    curl='curl -sSL'
elif command_exists wget; then
    curl='wget -qO-'
elif command_exists busybox && busybox --list-modules | grep -q wget; then
    curl='busybox wget -qO-'
fi

proxy_address=""
while [ "$1" != "" ]; do
    PARAM=`echo "$1" | awk -F= '{print $1}'`
    VALUE=`echo "$1" | awk -F= '{print $2}'`
    case $PARAM in
        http-proxy|http_proxy)
            proxy_address=$VALUE
            export http_proxy=${proxy_address}
            export https_proxy=${proxy_address}
            export HTTP_PROXY=${proxy_address}
            export HTTPS_PROXY=${proxy_address}
            ;;
        daemon-address|daemon_address)
            DAEMON_ADDRESS="${VALUE}"
            ;;
        secure-token|secure_token)
            SECURE_TOKEN="${VALUE}"
            ;;
        private-ip|private_ip)
            PRIVATE_IP="${VALUE}"
            ;;
        host-id|host_id)
            HOST_ID="${VALUE}"
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            exit 1
            ;;
    esac
    shift
done

lsb_dist=''
if [ -r /etc/os-release ]; then
    _dist="$(. /etc/os-release && echo "$ID")"
    _dist="$(echo "$_dist" | tr '[:upper:]' '[:lower:]')"
    _version="$(. /etc/os-release && echo "$VERSION_ID")"
    case "$_dist" in
        ubuntu)
            oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
            [ $1 -ge 10 ] && lsb_dist=$_dist
        ;;
        debian)
            oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
            [ $1 -ge 7 ] && lsb_dist=$_dist
        ;;
        fedora)
            oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
            [ $1 -ge 20 ] && lsb_dist=$_dist
        ;;
        rhel)
            oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
            [ $1 -ge 7 ] && lsb_dist=$_dist
        ;;
        centos)
            oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
            [ $1 -ge 7 ] && lsb_dist=$_dist
        ;;
        amzn)
            [ "$_version" = "2015.03" ] && lsb_dist=$_dist
        ;;
    esac
elif grep -q "Amazon.*2014\.03" /etc/system-release; then
    lsb_dist=amzn
fi

cat > /etc/logrotate.d/replicated  <<-EOF
/var/log/replicated/*.log {
  size 500k
  rotate 4
  nocreate
  compress
  notifempty
  missingok
}
EOF

case "$lsb_dist" in
    fedora|rhel|centos|amzn)
        save_autoconfig
        save_config

        cat > /etc/yum.repos.d/replicated.repo <<-EOF
[replicated]
name=Replicated Repository
baseurl={{ replicated_install_url }}/yum/{{ channel_name }}
EOF

        gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 822819BB
        gpg --export -a 822819BB > "$REPLICATED_TEMP_DIR/replicated_pub.asc"
        rpm --import "$REPLICATED_TEMP_DIR/replicated_pub.asc"

        # Enable secondary repos and install deps.
        yum install -y yum-utils
        case "$lsb_dist" in
            amzn)
                yum-config-manager --enable epel/x86_64
                yum makecache
            ;;
            rhel)
                yum-config-manager --enable rhui-REGION-rhel-server-extras
                yum makecache
            ;;
        esac
        yum install -y python-hashlib

        yum install -y replicated-agent

        case "$lsb_dist" in
            amzn)
                # Amazon Linux uses upstart.
                start replicated-agent
            ;;
            *)
                systemctl daemon-reload
                systemctl enable replicated-agent
                systemctl restart replicated-agent
            ;;
        esac

        exit 0
    ;;

    ubuntu|debian)
        save_autoconfig
        save_config

        export DEBIAN_FRONTEND=noninteractive

        did_apt_get_update=
        apt_get_update() {
            if [ -z "$did_apt_get_update" ]; then
                ( set -x; $sh_c 'apt-get update' )
                did_apt_get_update=1
            fi
        }

        if [ ! -e /usr/lib/apt/methods/https ]; then
            apt_get_update
            ( set -x; $sh_c 'apt-get install -y -q apt-transport-https' )
        fi
        if [ -z "$curl" ]; then
            apt_get_update
            ( set -x; $sh_c 'apt-get install -y -q curl' )
            curl='curl -sSL'
        fi
        (
            set -x

            echo "deb {{ replicated_install_url }}/apt all {{ channel_name }}" | sudo tee /etc/apt/sources.list.d/replicated.list
            apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 68386EDB2C8B75CA615A8C985D4781862AFFAC40

            apt-get update
            apt-get install -y {{ packagename_agent }}

            if command_exists systemctl; then
                systemctl enable replicated-agent
            fi
        )

        exit 0
    ;;
esac

cat >&2 <<'EOF'

  Either your platform is not easily detectable, is not supported by this
  installer script, or does not yet have a package for Replicated.
  Please visit the following URL for more detailed installation instructions:

    http://docs.replicated.com/docs/installing-replicated

EOF
exit 1
