#!/bin/bash

#
# This script is meant for quick & easy uninstall via:
#   'curl -sSL {{ replicated_install_url }}/uninstall | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/uninstall | sudo bash'
#

set -e

{% include 'common/common.sh' %}
{% include 'common/system.sh' %}
{% include 'common/prompt.sh' %}


################################################################################
# Code starts here
################################################################################

printf "${RED}This script will uninstall Replicated and all it's data. Are you sure you want to proceed?${NC}"
if ! confirmN; then
    exit 0
fi

detectInitSystem

set +e

if [ $INIT_SYSTEM == "upstart" ] ; then
    printf "${YELLOW}Stopping Replicated components${NC}"
    stop replicated
    stop replicated-ui
    stop replicated-operator
elif [ $INIT_SYSTEM == "sysvinit" ] ; then
    printf "${YELLOW}Stopping Replicated components${NC}"
    service replicated stop 
    service replicated-ui stop
    service replicated-operator stop
elif [ $INIT_SYSTEM == "systemd" ] ; then 
    printf "${YELLOW}Stopping Replicated components${NC}"
    systemctl stop replicated
    systemctl stop replicated-ui
    systemctl stop replicated-operator
else
    printf "${RED}Failed to stop Replicated components because init system sas not detected${NC}"
    exit 1
fi

sleep 1

printf "${YELLOW}Removing Replicated containers and images${NC}"

docker stop replicated replicated-operator replicated-ui 
docker rm -f replicated replicated-ui replicated-operator
docker rm -f replicated-premkit retraced-api retraced-processor retraced-cron retraced-nsqd retraced-postgres replicated-statsd
docker images | grep "quay\.io/replicated" | awk '{print $3}' | xargs sudo docker rmi -f
docker images | grep "registry\.replicated\.com/library" | awk '{print $3}' | xargs sudo docker rmi -f
rm -rf /var/lib/replicated* /etc/replicated* /etc/init/replicated* /etc/default/replicated* /etc/systemd/system/replicated* /etc/sysconfig/replicated* /etc/systemd/system/multi-user.target.wants/replicated* /var/run/replicated* /etc/init.d/replicated*

printf "${GREEN}Replicated has been uninstalled successfully!${NC}"
