#! /bin/bash
set -eu
cd $(dirname $0)/..

source scripts/check_installed.sh

install brew /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ln -sf 
