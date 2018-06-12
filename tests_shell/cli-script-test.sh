#!/bin/bash

. ./install_scripts/templates/common/cli-script.sh

testInstallCliFile()
{
    tmpDir="$(mktemp -d)"
    _installCliFile "$tmpDir" "echo" "CONTAINER"

    assertEquals "$("$tmpDir/replicated" -i COMMAND -ARG)" "-i CONTAINER replicated COMMAND -ARG"
    assertEquals "$("$tmpDir/replicatedctl" -i COMMAND -ARG)" "-i CONTAINER replicatedctl COMMAND -ARG"
    assertEquals "$("$tmpDir/replicated" -t COMMAND -ARG)" "-t CONTAINER replicated COMMAND -ARG"
    assertEquals "$("$tmpDir/replicatedctl" -t COMMAND -ARG)" "-t CONTAINER replicatedctl COMMAND -ARG"
    assertEquals "$("$tmpDir/replicated" -it COMMAND -ARG)" "-it CONTAINER replicated COMMAND -ARG"
    assertEquals "$("$tmpDir/replicatedctl" -it COMMAND -ARG)" "-it CONTAINER replicatedctl COMMAND -ARG"
    assertEquals "$("$tmpDir/replicated" -ti COMMAND -ARG)" "-it CONTAINER replicated COMMAND -ARG"
    assertEquals "$("$tmpDir/replicatedctl" -ti COMMAND -ARG)" "-it CONTAINER replicatedctl COMMAND -ARG"
    assertEquals "$("$tmpDir/replicated" --interactive --tty COMMAND -ARG)" "-it CONTAINER replicated COMMAND -ARG"
    assertEquals "$("$tmpDir/replicatedctl" --interactive --tty COMMAND -ARG)" "-it CONTAINER replicatedctl COMMAND -ARG"
    assertEquals "$("$tmpDir/replicated" --interactive=0 COMMAND -ARG)" "CONTAINER replicated COMMAND -ARG"
    assertEquals "$("$tmpDir/replicatedctl" --interactive=0 COMMAND -ARG)" "CONTAINER replicatedctl COMMAND -ARG"
    assertEquals "$("$tmpDir/replicated" --tty=0 COMMAND -ARG)" "CONTAINER replicated COMMAND -ARG"
    assertEquals "$("$tmpDir/replicatedctl" --tty=0 COMMAND -ARG)" "CONTAINER replicatedctl COMMAND -ARG"
    assertEquals "$("$tmpDir/replicated" --interactive=0 --tty=1 COMMAND -ARG)" "-t CONTAINER replicated COMMAND -ARG"
    assertEquals "$("$tmpDir/replicatedctl" --interactive=0 --tty=1 COMMAND -ARG)" "-t CONTAINER replicatedctl COMMAND -ARG"
}

testInstallCliFileAutodetect()
{
    if [ -t 0 ]; then
        assertEquals "$("$tmpDir/replicatedctl" COMMAND -ARG)" "-it CONTAINER replicatedctl COMMAND -ARG"
    elif [ -t 1 ]; then
        assertEquals "$("$tmpDir/replicatedctl" COMMAND -ARG)" "-i CONTAINER replicatedctl COMMAND -ARG"
    else
        assertEquals "$("$tmpDir/replicatedctl" COMMAND -ARG)" "CONTAINER replicatedctl COMMAND -ARG"
    fi
}

. shunit2
