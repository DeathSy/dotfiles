# INSTALL xcode utilities
xcode-select --install

# INSTALL homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

brew install go antigen tmux thefuck nvm gh git-flow git-lfs helm neovim ruby terraform tree wget docker docker-compose colima kubernetes-cli act ngrok fastlane cocoapods exa alt-tab

brew tap homebrew/cask-fonts
brew install --cask font-fira-code visual-studio-code runjs fig font-hack-nerd-font

# ADD zsh configuration
ln -s $(pwd)/.zshrc ~/.zshrc

# ADD tmux configuration
ln -s $(pwd)/.tmux.conf ~/.tmux.conf
ln -s $(pwd)/.tmux.conf.local ~/.tmux.conf.local
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# ADD nvim configuration
ln -s $(pwd)/nvim ~/.config/nvim

# ADD iCloud configurations config to it's place

ln -s ~/Library/Mobile\ Documents/com\~apple\~CloudDocs/workspace ~/workspace
ln -s ~/Library/Mobile\ Documents/com\~apple\~CloudDocs/workspace/keypairs ~/.ssh/keypairs
ln -s ~/Library/Mobile\ Documents/com\~apple\~CloudDocs/workspace/infra/config ~/.ssh/config

# ADD powerline font
git clone https://github.com/powerline/fonts.git
cd fonts && ./install.sh

# Setting up docker plugin 

mkdir -p ~/.docker/cli-plugins
ln -sfn $(brew --prefix)/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose

# Setting up native ruby plugin
sudo gem install bundler:2.2.27 cocoapods

# INSTALL node
nvm install 16

