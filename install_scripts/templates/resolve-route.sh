#!/bin/bash

printf "
            404: Not Found
            There was an error processing the request to generate the installation script

                Request Path: {{ path }}

            Please visit https://help.replicated.com/ for installation guides and documentation

"

exit 1
