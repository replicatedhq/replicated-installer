#!/bin/sh
# This script is meant to be downloaded of bootstraped AMI instance running Ubuntu 14.04
#   'curl -sSL {{ replicated_install_url }}/utils/aws/ubuntu1404/replicated-init > /etc/replicated-bootstrap/init-defaults.sh'
# or:
#   'wget -qO- {{ replicated_install_url }}/utils/aws/ubuntu1404/replicated-init > /etc/replicated-bootstrap/init-defaults.sh'

set -e

PUBLIC_ADDRESS=""

get_ips() {
	# Use AWS services to get IPs
	PUBLIC_ADDRESS="$(curl --max-time 5 --connect-timeout 2 -qSfs http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)"
	PRIVATE_ADDRESS="$(curl --max-time 5 --connect-timeout 2 -qSfs http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || true)"
}

set_vars() {
	NODENAME="$(hostname)"
	DAEMON_TOKEN="$(head -c 128 /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)" # Generate random token
	RELEASE_CHANNEL="{{ channel_name }}"
	DAEMON_ENDPOINT="$PRIVATE_ADDRESS:9879"
	REPLICATED_OPTS="-e LOG_LEVEL=info -e DAEMON_TOKEN=$DAEMON_TOKEN -e NODENAME=$NODENAME"
	PUBLIC_ADDRESS_OPT=""
	if [ -n "$PUBLIC_ADDRESS" ]; then
		PUBLIC_ADDRESS_OPT="-e PUBLIC_ADDRESS=$PUBLIC_ADDRESS"
	fi
	REPLICATED_OPERATOR_OPTS="-e LOG_LEVEL=info $PUBLIC_ADDRESS_OPT -e TAGS=local -e NODENAME=$NODENAME"
}

write_replicated_configuration() {
	cat > /etc/default/replicated <<-EOF
RELEASE_CHANNEL=$RELEASE_CHANNEL
PRIVATE_ADDRESS=$PRIVATE_ADDRESS
SKIP_OPERATOR_INSTALL=0
REPLICATED_OPTS="$REPLICATED_OPTS"
EOF
}

write_replicated_operator_configuration() {
	cat > /etc/default/replicated-operator <<-EOF
RELEASE_CHANNEL=$RELEASE_CHANNEL
DAEMON_ENDPOINT=$DAEMON_ENDPOINT
DAEMON_TOKEN=$DAEMON_TOKEN
PRIVATE_ADDRESS=$PRIVATE_ADDRESS
REPLICATED_OPERATOR_OPTS="$REPLICATED_OPERATOR_OPTS"
EOF
}

start_replicated() {
	mv /etc/replicated-bootstrap/replicated.conf /etc/init
	mv /etc/replicated-bootstrap/replicated-stop.conf /etc/init
	mv /etc/replicated-bootstrap/replicated-operator.conf /etc/init
	mv /etc/replicated-bootstrap/replicated-operator-stop.conf /etc/init
	mv /etc/replicated-bootstrap/replicated-ui.conf /etc/init
	mv /etc/replicated-bootstrap/replicated-ui-stop.conf /etc/init
	mv /etc/init/replicated-init.conf /etc/replicated-bootstrap
	chmod a-x /etc/replicated-bootstrap/init-defaults.sh
	service replicated start || true
	service replicated-ui start || true
	service replicated-operator start || true
}

################################################################################
# Execution starts here
################################################################################

get_ips
set_vars
write_replicated_configuration
write_replicated_operator_configuration
start_replicated

exit 0
