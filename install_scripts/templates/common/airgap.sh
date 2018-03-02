
#######################################
#
# airgap.sh
#
#######################################

#######################################
# Loads replicated main images into docker
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
airgapLoadReplicatedImages() {
    docker load < replicated.tar
    docker load < replicated-ui.tar
}

#######################################
# Loads replicated operator image into docker
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
airgapLoadOperatorImage() {
    docker load < replicated-operator.tar
}

#######################################
# Loads replicated support images into docker
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
airgapLoadSupportImages() {
    docker load < cmd.tar
    docker load < statsd-graphite.tar
    docker load < premkit.tar
    docker load < debian.tar
}

#######################################
# Loads Retraced images into docker, these images power the replicated audit logs
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
airgapMaybeLoadSupportBundle() {
    if [ -f support-bundle.tar ]; then
      printf "Loading support bundle image\n"
      docker load < support-bundle.tar
    fi

}

#######################################
# Loads Retraced images into docker, these images power the replicated audit logs
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
airgapMaybeLoadRetraced() {
    if [ -f retraced-bundle.tar.gz ]; then
      printf "Loading audit log images from package\n"
      tar xzvf retraced-bundle.tar.gz
      docker load < retraced-postgres.tar
      docker load < retraced-nsqd.tar
      docker load < retraced-db.tar
      docker load < retraced-processor.tar
      docker load < retraced-api.tar
      docker load < retraced-cron.tar
      # redis is included in Retraced <= 1.1.10
      if [ -f retraced-redis.tar ]; then
        docker load < retraced-redis.tar
      fi
    fi

}
