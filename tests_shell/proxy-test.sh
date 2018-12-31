#!/bin/bash

. ./install_scripts/templates/common/proxy.sh

test_configureDockerProxyUpstartNew()
{
    tempTestingFile="$(mktemp)"
    read -r -d '' expected <<EOF
# Generated by replicated install script
export http_proxy="33.33.33.33"
export NO_PROXY="44.44.44.44"
EOF
    expected="$(printf "\n$expected")"

    _configureDockerProxyUpstart "$tempTestingFile" "33.33.33.33" "44.44.44.44"
    assertEquals "$expected" "$(cat $tempTestingFile)"

    rm -f "$tempTestingFile"
}

test_configureDockerProxyUpstartEmpty()
{
    tempTestingFile="$(mktemp)"
    cat > $tempTestingFile <<EOF
before
EOF
    read -r -d '' expected <<EOF
before

# Generated by replicated install script
export http_proxy="33.33.33.33"
export NO_PROXY="44.44.44.44"
EOF

    _configureDockerProxyUpstart "$tempTestingFile" "33.33.33.33" "44.44.44.44"
    assertEquals "$expected" "$(cat $tempTestingFile)"

    rm -f "$tempTestingFile"
}

test_configureDockerProxyUpstartFound()
{
    tempTestingFile="$(mktemp)"
    cat > $tempTestingFile <<EOF
before

# Generated by replicated install script
export http_proxy="11.11.11.11"
export NO_PROXY=22.22.22.22

after
EOF
    read -r -d '' expected <<EOF
before

# Generated by replicated install script
export http_proxy="33.33.33.33"
export NO_PROXY="44.44.44.44"

after
EOF

    _configureDockerProxyUpstart "$tempTestingFile" "33.33.33.33" "44.44.44.44"
    assertEquals "$expected" "$(cat $tempTestingFile)"

    rm -f "$tempTestingFile"
}

test_configureDockerProxyUpstartCase()
{
    tempTestingFile="$(mktemp)"
    cat > $tempTestingFile <<EOF
before

export HTTP_PROXY="11.11.11.11"
export NO_PROXY="22.22.22.22"

after
EOF
    read -r -d '' expected <<EOF
before

export HTTP_PROXY="11.11.11.11"
export NO_PROXY="44.44.44.44"

after

# Generated by replicated install script
export http_proxy="33.33.33.33"
EOF

    _configureDockerProxyUpstart "$tempTestingFile" "33.33.33.33" "44.44.44.44"
    assertEquals "$expected" "$(cat $tempTestingFile)"

    rm -f "$tempTestingFile"
}

test_configureDockerProxySystemdNew()
{
    tempTestingFile="$(mktemp)"
    read -r -d '' expected <<EOF
# Generated by replicated install script
[Service]
Environment= "HTTP_PROXY=33.33.33.33" "NO_PROXY=44.44.44.44"
EOF

    _configureDockerProxySystemd "$tempTestingFile" "33.33.33.33" "44.44.44.44"
    assertEquals "$expected" "$(cat $tempTestingFile)"

    rm -f "$tempTestingFile"
}

test_configureDockerProxySystemdEmpty()
{
    tempTestingFile="$(mktemp)"
    cat > $tempTestingFile <<EOF
before
EOF
    read -r -d '' expected <<EOF
before
EOF

    _configureDockerProxySystemd "$tempTestingFile" "33.33.33.33" "44.44.44.44"
    assertEquals "$expected" "$(cat $tempTestingFile)"

    rm -f "$tempTestingFile"
}

test_configureDockerProxySystemdFound()
{
    tempTestingFile="$(mktemp)"
    cat > $tempTestingFile <<EOF
# Generated by replicated install script
[Service]
Environment="HTTP_PROXY=11.11.11.11" "A=b" "NO_PROXY=22.22.22.22"
EOF
    read -r -d '' expected <<EOF
# Generated by replicated install script
[Service]
Environment="A=b" "HTTP_PROXY=33.33.33.33" "NO_PROXY=44.44.44.44"
EOF

    _configureDockerProxySystemd "$tempTestingFile" "33.33.33.33" "44.44.44.44"
    assertEquals "$expected" "$(cat $tempTestingFile)"

    rm -f "$tempTestingFile"
}

test_configureDockerProxySystemdCase()
{
    tempTestingFile="$(mktemp)"
    cat > $tempTestingFile <<EOF
# Generated by replicated install script
[Service]
Environment="http_proxy=11.11.11.11" "A=b" "NO_PROXY=22.22.22.22"
EOF
    read -r -d '' expected <<EOF
# Generated by replicated install script
[Service]
Environment="http_proxy=11.11.11.11" "A=b" "HTTP_PROXY=33.33.33.33" "NO_PROXY=44.44.44.44"
EOF

    _configureDockerProxySystemd "$tempTestingFile" "33.33.33.33" "44.44.44.44"
    assertEquals "$expected" "$(cat $tempTestingFile)"

    rm -f "$tempTestingFile"
}

test_getNoProxyAddresses()
{
    ADDITIONAL_NO_PROXY="146.148.47.17"
    getNoProxyAddresses "10.128.0.39" "10.128.0.39/32"
    assertEquals "10.128.0.39,10.128.0.39/32,127.0.0.1,146.148.47.17,172.17.0.1,localhost" "$NO_PROXY_ADDRESSES"
}

. shunit2
