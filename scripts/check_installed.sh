#! /bin/bash

function install() {
    local cmd=$1
    if command -v $cmd &> /dev/null; then
        echo "$cmd is already installed"
    else
        echo "Installing $1"
        shift
        "$@"

        # check if cmd is installed
        if command -v $cmd &> /dev/null; then
            echo "$cmd is installed"
        else
            echo "installing $cmd failed"
            exit 1
        fi
    fi
}
