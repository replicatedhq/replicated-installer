
#######################################
#
# common.sh
#
#######################################

GREEN='\033[0;32m'
BLUE='\033[0;94m'
LIGHT_BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

#######################################
# Check if command exists.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if command exists
#######################################
commandExists() {
    command -v "$@" > /dev/null 2>&1
}

#######################################
# Check if replicated 1.2 is installed
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if replicated 1.2 is installed
#######################################
replicated12Installed() {
    commandExists replicated && replicated --version | grep -q "Replicated version 1\.2"
}

#######################################
# Gets curl or wget depending if cmd exits.
# Globals:
#   PROXY_ADDRESS
# Arguments:
#   None
# Returns:
#   URLGET_CMD
#######################################
URLGET_CMD=
getUrlCmd() {
    if commandExists "curl"; then
        URLGET_CMD="curl -sSL"
        if [ -n "$PROXY_ADDRESS" ]; then
            URLGET_CMD=$URLGET_CMD" -x $PROXY_ADDRESS"
        fi
    else
        URLGET_CMD="wget -qO-"
    fi
}

#######################################
# Generates a 32 char unique id.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   GUID_RESULT
#######################################
getGuid() {
    GUID_RESULT="$(head -c 128 /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
}

#######################################
# performs in-place sed substitution with escapting of inputs (http://stackoverflow.com/a/10467453/5344799)
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
safesed() {
    sed -i "s/$(echo $1 | sed -e 's/\([[\/.*]\|\]\)/\\&/g')/$(echo $2 | sed -e 's/[\/&]/\\&/g')/g" $3
}

#######################################
# Parses a semantic version string
# Globals:
#   None
# Arguments:
#   Version
# Returns:
#   major, minor, patch
#######################################
semverParse() {
    major="${1%%.*}"
    minor="${1#$major.}"
    minor="${minor%%.*}"
    patch="${1#$major.$minor.}"
    patch="${patch%%[-.]*}"
}

#######################################
# Compare two semvers.
# Returns -1 if A lt B, 0 if eq, 1 A gt B.
# Globals:
#   None
# Arguments:
#   Sem Version A
#   Sem Version B
# Returns:
#   SEMVER_COMPARE_RESULT
#######################################
SEMVER_COMPARE_RESULT=
semverCompare() {
    semverParse "$1"
    _a_major="$major"
    _a_minor="$minor"
    _a_patch="$patch"
    semverParse "$2"
    _b_major="$major"
    _b_minor="$minor"
    _b_patch="$patch"
    if [ "$_a_major" -lt "$_b_major" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_major" -gt "$_b_major" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    if [ "$_a_minor" -lt "$_b_minor" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_minor" -gt "$_b_minor" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    if [ "$_a_patch" -lt "$_b_patch" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_patch" -gt "$_b_patch" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    SEMVER_COMPARE_RESULT=0
}

#######################################
# Inserts a parameter into a json file. If the file does not exist, creates it. If the parameter is already set, replaces it.
# Globals:
#   None
# Arguments:
#   path, parameter name, value
# Returns:
#   None
#######################################
insertOrReplaceJsonParam() {
    if ! [ -f "$1" ]; then
        # If settings file does not exist
        mkdir -p "$(dirname "$1")"
        echo "{\"$2\": \"$3\"}" > "$1"
    else
        # Settings file exists
        if grep -q -E "\"$2\" *: *\"[^\"]*\"" "$1"; then
            # If settings file contains named setting, replace it
            sed -i -e "s/\"$2\" *: *\"[^\"]*\"/\"$2\": \"$3\"/g" "$1"
        else
            # Insert into settings file (with proper commas)
            if [ $(wc -c <"$1") -ge 5 ]; then
                # File long enough to actually have an entry, insert "name": "value",\n after first {
                _commonJsonReplaceTmp="$(awk "NR==1,/^{/{sub(/^{/, \"{\\\"$2\\\": \\\"$3\\\", \")} 1" "$1")"
                echo "$_commonJsonReplaceTmp" > "$1"
            else
                # file not long enough to actually have contents, replace wholesale
                echo "{\"$2\": \"$3\"}" > "$1"
            fi
        fi
    fi
}
