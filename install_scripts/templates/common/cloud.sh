#######################################
#
# cloud.sh
#
#######################################

AWS="AWS"
AZURE="Azure"
GCP="GCP"

#######################################
# Determine the cloud
# Globals:
#   None:
# Arguments:
#   None:
# Returns:
#   CLOUD
#######################################
CLOUD=
detect_cloud() {
    if commandExists "curl"; then
        if curl --noproxy "*" --max-time 5 --connect-timeout 2 --fail --silent http://169.254.169.254/latest/meta-data > /dev/null; then
            CLOUD=$AWS
            return 0
        fi

        # Azure
        if curl --noproxy "*" --max-time 5 --connect-timeout 2 --fail --silent -H "Metadata:true" http://169.254.169.254/metadata/instance/network?api-version=2017-08-01 > /dev/null; then
            CLOUD=$AZURE
            return 0
        fi

        # Google
        if curl --noproxy "*" --max-time 5 --connect-timeout 2 --fail --silent -H "Metadata-Flavor: Google" "http://metadata.google.internal" > /dev/null; then
            CLOUD=$GCP
            return 0
        fi
    else
        # AWS
        if wget --no-proxy -t 1 --timeout=5 --connect-timeout 2 -q0- "http://169.254.169.254/latest/meta-data/" 2>/dev/null; then
            CLOUD=$AWS
            return 0
        fi

        # AZURE
        if wget --no-proxy -t 1 --timeout=5 --connect-timeout=2 -q0- -H "Metadata:true" http://169.254.169.254/metadata/instance/network?api-version=2017-08-01 2>&1 > /dev/null; then
            CLOUD=$AZURE
            return 0
        fi

        # Google
        if wget --no-proxy -t 1 --timeout=5 --connect-timeout=2 -q0- -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/" 2>/dev/null; then
            CLOUD=$GCP
            return 0
        fi
    fi

    return 1
}
