#! /bin/bash
set -eu
cd $(dirname $0)/..

source scripts/check_installed.sh

install zsh sudo apt-get install zsh -y
chsh -s $(which zsh)

source scripts/setup_common.sh

zsh
