#!/usr/bin/env bash

echo "Checking Versioning"

if [ -e ./ALIASES ]; then
    git restore ALIASES --source=main
    PREV_LTS="$(grep 'lts' ALIASES | cut -d "=" -f2)"
    PREV_VERSION="$(grep 'current' ALIASES | cut -d "=" -f2)"
    export PREV_LTS
    export PREV_VERSION
fi

checkVersions() {
    local currentVersion=$1
    local prevVersion=$2
    if ! [ -e ./ALIASES ]; then
        echo "Skipping version check"
    elif [[ $prevVersion != "$currentVersion" ]]; then
        if [ "$(printf '%s\n' "$currentVersion" "$prevVersion" | sort -V | head -n1)" = "$currentVersion" ]; then
            echo "Please check your versions. current: $currentVersion previous: $prevVersion"
            exit 1
        else
            echo "Version check passed"
        fi
    else
        echo "Same version detected"
    fi
}