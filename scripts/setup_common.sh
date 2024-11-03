#! /bin/bash
set -eu
cd $(dirname $0)/..

source scripts/check_installed.sh

install brew /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install sheldon
sheldon init --shell zsh -y

brew install lazygit
brew install lazydocker

brew install nvm
brew install plenv
