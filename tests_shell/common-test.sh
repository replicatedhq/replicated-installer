#!/bin/bash

. ./install_scripts/templates/common/common.sh

testCreateInsertUpdateJson()
{
    tempTestingJSONfile=$(mktemp)

    insertOrReplaceJsonParam "$tempTestingJSONfile" alpha beta
    insertOrReplaceJsonParam "$tempTestingJSONfile" gamma delta
    insertOrReplaceJsonParam "$tempTestingJSONfile" epsilon zeta
    assertTrue "File was not created" "[ -r $tempTestingJSONfile ]"
    assertTrue "File does not contain all three key:value pairs" "[ $(cat "$tempTestingJSONfile" | grep -c -e ':.*:.*:') -eq 1 ]"

    insertOrReplaceJsonParam "$tempTestingJSONfile" alpha theta
    assertTrue "File contains replaced value" "[ $(cat "$tempTestingJSONfile" | grep -c -e 'beta') -eq 0 ]"
    assertTrue "File lacks new value" "[ $(cat "$tempTestingJSONfile" | grep -c -e 'theta') -eq 1 ]"

    rm "$tempTestingJSONfile"
}

. shunit2
