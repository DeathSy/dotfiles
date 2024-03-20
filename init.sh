# INSTALL xcode utilities
xcode-select --install

# INSTALL homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

# INSTALL pngm
curl -fsSL https://get.pnpm.io/install.sh | sh -

brew install go antigen nvm gh git-flow git-lfs helm neovim ruby terraform tree wget kubernetes-cli act ngrok vagrant htop rustup-init oven-sh/bun/bun openjdk@11 aquasecurity/trivy/trivy derailed/k9s/k9 lazydocker tnk-studio/tools/lazykube

brew tap homebrew/cask-fonts adoptopenjdk/openjdk
brew install --cask font-fira-code visual-studio-code runjs font-hack-nerd-font raycast adoptopenjdk8

# ADD zsh configuration
ln -s $(pwd)/.zshrc ~/.zshrc
source ~/.zshrc

pip install harlequin

# ADD tmux configuration
ln -s $(pwd)/.tmux.conf ~/.tmux.conf
ln -s $(pwd)/.tmux.conf.local ~/.tmux.conf.local
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# ADD nvim configuration
ln -s $(pwd)/nvim ~/.config/nvim

# ADD powerline font
git clone https://github.com/powerline/fonts.git
cd fonts && ./install.sh

# INSTALL node
nvm install stable
nvm alias default stable

corepack enable
