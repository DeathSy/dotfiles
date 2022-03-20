# INSTALL xcode utilities
xcode-select --install

# INSTALL homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

brew install go antigen tmux thefuck nvm gh git-flow git-lfs helm neovim ruby terraform tree wget

# ADD zsh configuration
ln -s $(pwd)/.zshrc ~/.zshrc

# ADD tmux configuration
ln -s $(pwd)/tmux.conf ~/.tmux.conf
ln -s $(pwd).tmux.conf.local ~/.tmux.conf.local

# ADD nvim configuration
ln -s $(pwd)/nvim ~/.config/nvim

# ADD iCloud configurations config to it's place

ln -s ~/Library/Mobile\ Documents/com\~apple\~CloudDocs/workspace ~/workspace
ln -s ~/Library/Mobile\ Documents/com\~apple\~CloudDocs/workspace/keypairs ~/.ssh/keypairs
ln -s ~/Library/Mobile\ Documents/com\~apple\~CloudDocs/workspace/infra/config ~/.ssh/config

# ADD powerline font
git clone https://github.com/powerline/fonts.git
cd fonts && ./install.sh
