#!/bin/bash

PATH="{{ path }}"

{% include 'common/common.sh' %}

#######################################
# Prints 404 with associated bad path.
# Globals:
#   PATH
# Arguments:
#   None
# Returns:
#   None
#######################################
printf "${RED}
            404: Not Found
            There was an error processing the request to generate the installation script

                Request path: $PATH

            Please visit https://help.replicated.com/ for installation guides and documentation${NC}\n\n\
"

exit 1
