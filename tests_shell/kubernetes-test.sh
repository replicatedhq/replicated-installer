#!/bin/bash

. ./install_scripts/templates/common/common.sh
. ./install_scripts/templates/common/kubernetes.sh


testGetRookVersion()
{
    local rookImageTag=
    function kubectl() {
        echo " image: blah:$rookImageTag"
    }
    export kubectl

    rookImageTag=v1.0.6-20200512
    getRookVersion
    assertEquals "rook version with pre-release" "1.0.6" "$ROOK_VERSION"

    rookImageTag=v1.0.3
    getRookVersion
    assertEquals "rook version without pre-release" "1.0.3" "$ROOK_VERSION"

    rookImageTag=v0.8.1
    getRookVersion
    assertEquals "rook 0.8.1" "0.8.1" "$ROOK_VERSION"
}

testGetEtcdVersion()
{
    local etcdImageTag=
    function kubectl() {
        echo " image: blah:$etcdImageTag"
    }
    export kubectl

    etcdImageTag=3.4.7-20200602
    getEtcdVersion
    assertEquals "etcd version with pre-release" "3.4.7" "$ETCD_VERSION"

    etcdImageTag=3.3.10
    getEtcdVersion
    assertEquals "etcd version without pre-release" "3.3.10" "$ETCD_VERSION"
}

testIsEtcd33()
{
    local etcdImageTag=
    function kubectl() {
        echo " image: blah:$etcdImageTag"
    }
    export kubectl

    etcdImageTag=3.4.7-20200602
    if isEtcd33 ; then
        assertEquals "etcd $etcdImageTag" "1" "0"
    fi

    etcdImageTag=3.3.10
    if ! isEtcd33 ; then
        assertEquals "etcd $etcdImageTag" "0" "1"
    fi

    etcdImageTag=3.2.24
    if isEtcd33 ; then
        assertEquals "etcd $etcdImageTag" "1" "0"
    fi
}

. shunit2
