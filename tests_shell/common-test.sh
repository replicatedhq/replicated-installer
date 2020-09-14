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

    rm -f "$tempTestingJSONfile"
}

testSplitHostPort()
{
    splitHostPort "1.1.1.1:9876"
    assertEquals "Split host port 1.1.1.1:9876 failed, host" "1.1.1.1" "$HOST"
    assertEquals "Split host port 1.1.1.1:9876 failed, port" "9876" "$PORT"

    splitHostPort "1.1.1.1"
    assertEquals "Split host port 1.1.1.1 failed, host" "1.1.1.1" "$HOST"
    assertEquals "Split host port 1.1.1.1 failed, port" "" "$PORT"

    splitHostPort ""
    assertEquals "Split host port failed, host" "" "$HOST"
    assertEquals "Split host port failed, port" "" "$PORT"
}

testInsertJSONArray()
{
    local tmp=$(mktemp)

    insertJSONArray "$tmp" "exec-opts" "native.cgroupdriver=systemd"
    ret=$?
    assertTrue "File was not created" "[ -r $tmp ]"
    assertTrue "Insert was not successful" "[ $ret = 0 ]"
    assertTrue "File does not have exec-opts" "cat $tmp | grep 'exec-opts' | grep '\[\"native.cgroupdriver=systemd\"\]'"

    insertJSONArray "$tmp" "exec-opts" "native.cgroupdriver=cgroupfs"
    ret=$?
    assertTrue "Parameter was overwritten" "[ $ret = 1 ]"

    insertJSONArray "$tmp" "insecure-registries" "10.100.100.100"
    ret=$?
    assertTrue "Insert was not successful" "[ $ret = 0 ]"
    assertTrue "File lost exec-opts" "cat $tmp | grep 'exec-opts' | grep '\[\"native.cgroupdriver=systemd\"\]'"
    assertTrue "File does not have insecure-registries" "cat $tmp | grep 'insecure-registries' | grep '\[\"10.100.100.100\"\]'"

    rm -f "$tmp"
}

. shunit2
