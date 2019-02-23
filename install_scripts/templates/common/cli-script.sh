
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
installCliFile() {
  _installCliFile "/usr/local/bin" "$1" "$2"
}

_installCliFile() {
  set +e
  read -r -d '' _flags <<EOF
interactive=
tty=
push=
no_tty=
is_admin=

while [ "\$1" != "" ]; do
  case "\$1" in
    # replicated admin shell alias support
    admin )
      is_admin=1
      ;;
    --no-tty )
      no_tty=1
      ;;
    --help | -h )
      push=\$push" \$1"
      ;;
    -i | --interactive | --interactive=1 )
      interactive=1
      ;;
    --interactive=0 )
      interactive=0
      ;;
    -t | --tty | --tty=1 )
      tty=1
      ;;
    --tty=0 )
      tty=0
      ;;
    -it | -ti )
      interactive=1
      tty=1
      ;;
    * )
      break
      ;;
  esac
  shift
done

# test if stdin is a terminal
if [ -z "\$interactive" ] && [ -z "\$tty" ]; then
  if [ -t 0 ]; then
    interactive=1
    tty=1
  elif [ -t 1 ]; then
    interactive=1
  fi
elif [ -z "\$tty" ] || [ "\$tty" = "0" ]; then
  # if flags explicitly set then use new behavior for no-tty
  no_tty=1
fi

if [ "\$is_admin" = 1 ]; then
  if [ "\$no_tty" = 1 ]; then
    push=" --no-tty"\$push
  fi
  push=" admin"\$push
fi

flags=
if [ "\$interactive" = "1" ] && [ "\$tty" = "1" ]; then
  flags=" -it"
elif [ "\$interactive" = "1" ]; then
  flags=" -i"
elif [ "\$tty" = "1" ]; then
  flags=" -t"
fi

# do not lose the quotes in arguments
opts=''
for i in "\$@"; do
  case "\$i" in
    *\\'*)
      i=\`printf "%s" "\$i" | sed "s/'/'\\"'\\"'/g"\`
      ;;
    *) : ;;
  esac
  opts="\$opts '\$i'"
done

EOF
  set -e

  cat > "${1}/replicated" <<-EOF
#!/bin/bash

set -eo pipefail

${_flags}

sh -c "${2} \$flags \\
  ${3} \\
  replicated\$push \$(printf "%s" "\$opts")"
EOF
  chmod a+x "${1}/replicated"
  cat > "${1}/replicatedctl" <<-EOF
#!/bin/bash

set -eo pipefail

${_flags}

sh -c "${2} \$flags \\
  ${3} \\
  replicatedctl\$push \$(printf "%s" "\$opts")"
EOF
  chmod a+x "${1}/replicatedctl"
}

#######################################
# Blocks until `replicatedctl system status` succeeds
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
waitReplicatedctlReady() {
    logSubstep "wait for replicated to report ready"
    for i in {1..30}; do
        if isReplicatedctlReady; then
            return 0
        fi
        sleep 2
    done
    return 1
}

#######################################
# Return code 0 unless `replicatedctl system status` succeeds
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
isReplicatedctlReady() {
    /usr/local/bin/replicatedctl system status 2>/dev/null | grep -q '"ready"'
}
