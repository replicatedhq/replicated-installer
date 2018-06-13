#!/bin/bash

set -e

./tests_shell/docker-version-test.sh

./tests_shell/common-test.sh

./tests_shell/cli-script-test.sh
