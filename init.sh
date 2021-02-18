# INSTALL xcode utilities
xcode-select --install

# INSTALL homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

# ADD zsh configuration
ln -s -f ./.zshrc ~/.zshrc

# ADD tmux configuration
ln -s -f $(pwd)/tmux.conf ~/.tmux.conf
ln -s -f $(pwd).tmux.conf.local ~/.tmux.conf.local

# ADD nvim configuration
ln -s -f $(pwd)/nvim ~/.config/nvim
