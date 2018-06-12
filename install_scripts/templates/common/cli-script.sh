
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
  read -r -d '' _flags << EOF
interactive=
tty=

while [ "\$1" != "" ]; do
  case "\$1" in
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
fi

flags=
if [ "\$interactive" = "1" ] && [ "\$tty" = "1" ]; then
  flags=" -it"
elif [ "\$interactive" = "1" ]; then
  flags=" -i"
elif [ "\$tty" = "1" ]; then
  flags=" -t"
fi
EOF

  cat > "${1}/replicated" <<-EOF
#!/bin/sh

${_flags}

${2} \$flags \
  ${3} \
  replicated "\$@"
EOF
  chmod a+x "${1}/replicated"
  cat > "${1}/replicatedctl" <<-EOF
#!/bin/sh

${_flags}

${2} \$flags \
  ${3} \
  replicatedctl "\$@"
EOF
  chmod a+x "${1}/replicatedctl"
}
