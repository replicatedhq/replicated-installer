
#######################################
#
# cli-script.sh
#
#######################################

#######################################
# Writes the replicated CLI to /usr/local/bin/replicated
# Wtires the replicated CLI V2 to /usr/local/bin/replicatedctl
# Globals:
#   None
# Arguments:
#   Container name/ID or script that identifies the container to run the commands in
# Returns:
#   None
#######################################
installCLIFile() {
  cat > /usr/local/bin/replicated <<-EOF
#!/bin/sh

# test if stdin is a terminal
if [ -t 0 ]; then
  sudo docker exec -it ${1} replicated "\$@"
elif [ -t 1 ]; then
  sudo docker exec -i ${1} replicated "\$@"
else
  sudo docker exec ${1} replicated "\$@"
fi
EOF
  chmod a+x /usr/local/bin/replicated
  cat > /usr/local/bin/replicatedctl <<-EOF
#!/bin/sh

# test if stdin is a terminal
if [ -t 0 ]; then
  sudo docker exec -it ${1} replicatedctl "\$@"
elif [ -t 1 ]; then
  sudo docker exec -i ${1} replicatedctl "\$@"
else
  sudo docker exec ${1} replicatedctl "\$@"
fi
EOF
  chmod a+x /usr/local/bin/replicatedctl
}


#######################################
# Writes the replicated CLI to /usr/local/bin/replicated
# Wrires the replicated CLI V2 to /usr/local/bin/replicatedctl
#
# between `-c replicated`, `--`, and `kubectl`, this is now specialized enough
# that it doesn't make sense to try to kludge it into
# the shared function (above) used by swarm/native
#
# Globals:
#   None
# Arguments:
#   Container name/ID or script that identifies the container to run the commands in
# Returns:
#   None
#######################################
installKubernetesCLIFile() {
  cat > /usr/local/bin/replicated <<-EOF
#!/bin/sh

# test if stdin is a terminal
if [ -t 0 ]; then
  kubectl exec -it -c replicated ${1} replicated -- "\$@"
elif [ -t 1 ]; then
  kubectl exec -i -c replicated ${1} replicated -- "\$@"
else
  kubectl exec -c replicated ${1} replicated -- "\$@"
fi
EOF
  chmod a+x /usr/local/bin/replicated
  cat > /usr/local/bin/replicatedctl <<-EOF
#!/bin/sh

# test if stdin is a terminal
if [ -t 0 ]; then
  kubectl exec -it -c replicated ${1} replicatedctl -- "\$@"
elif [ -t 1 ]; then
  kubectl exec -i -c replicated ${1} replicatedctl -- "\$@"
else
  kubectl exec -c replicated ${1} replicatedctl -- "\$@"
fi
EOF
  chmod a+x /usr/local/bin/replicatedctl
}
