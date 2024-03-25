# INSTALL xcode utilities
xcode-select --install

# INSTALL homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

# INSTALL pngm
curl -fsSL https://get.pnpm.io/install.sh | sh -

brew install neofetch go antigen nvm gh git-flow git-lfs helm neovim ruby terraform tree wget kubernetes-cli act ngrok vagrant htop rustup-init oven-sh/bun/bun openjdk@11 aquasecurity/trivy/trivy derailed/k9s/k9 lazydocker tnk-studio/tools/lazykube pipx ripgrep

brew tap homebrew/cask-fonts adoptopenjdk/openjdk
brew install --cask font-fira-code visual-studio-code runjs font-hack-nerd-font raycast adoptopenjdk8 wezterm

# ADD k9s theme
OUT="${XDG_CONFIG_HOME:-$HOME/Library/Application Support}/k9s/skins"
mkdir -p "$OUT"
curl -L https://github.com/catppuccin/k9s/archive/main.tar.gz | tar xz -C "$OUT" --strip-components=2 k9s-main/dist

# ADD zsh configuration
ln -s "$(pwd)/.zshrc" ~/.zshrc

# ADD neofetch configuration
ln -s "$(pwd)/neofetch.conf" ~/.config/neofetch

# ADD tmux configuration
ln -s "$(pwd)/.tmux.conf" ~/.tmux.conf
ln -s "$(pwd)/.tmux.conf.local" ~/.tmux.conf.local
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm


# ADD nvim configuration
ln -s "$(pwd)/lvim" ~/.config/lvim

# ADD wezterm configuration
mkdir -p ~/.config/wezterm
ln -s "$(pwd)/wezterm.lua" ~/.config/wezterm.lua

# ADD powerline font
git clone https://github.com/powerline/fonts.git
cd fonts && ./install.sh

# INSTALL node
nvm install stable
nvm alias default stable

corepack enable

# INSTALL lunarvim

yes | head -n 3 | LV_BRANCH='release-1.3/neovim-0.9' bash <(curl -s https://raw.githubusercontent.com/LunarVim/LunarVim/release-1.3/neovim-0.9/utils/installer/install.sh)
