#!/bin/bash

# MacDevKit: A comprehensive setup script for macOS development environments
# Author: jarvislin94
# License: MIT

# Set colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}\n"
}

# Function to print error messages
print_error() {
    echo -e "${RED}✗ $1${NC}\n"
}

# Function to print info messages
print_info() {
    echo -e "${CYAN}ℹ $1${NC}\n"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Append a line to a file only if it is not already present (idempotent)
append_once() {
    local line="$1"
    local file="$2"
    grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# Function to ask for confirmation
# Returns: 0 = proceed, 1 = skip, 2 = back to previous step (only when $3 = allow_back)
confirm_step() {
    local step_name="$1"
    local step_description="$2"
    local allow_back="${3:-}"

    echo -e "\n${YELLOW}▶ Step: ${step_name}${NC}\n"
    echo -e "${CYAN}Description:${NC} ${step_description}\n"

    local response=""
    if [[ -n "$allow_back" ]]; then
        echo -e "${YELLOW}Do you want to proceed with this step? (y/n, b = back to previous step)${NC}"
    else
        echo -e "${YELLOW}Do you want to proceed with this step? (y/n)${NC}"
    fi
    read -r response

    if [[ -n "$allow_back" && "$response" =~ ^[Bb] ]]; then
        echo -e "${YELLOW}Going back to the previous step${NC}"
        return 2
    fi

    if [[ "$response" =~ ^[Yy] ]]; then
        return 0 # True - proceed with step
    else
        echo -e "${YELLOW}Skipping: ${step_name}${NC}"
        return 1 # False - skip step
    fi
}

# Step 1: Install Xcode Command Line Tools
step_xcode_clt() {
    confirm_step "Install Xcode Command Line Tools" "Xcode Command Line Tools are required for many development tasks on macOS. This includes compilers, build tools, Git, and more. These tools are essential for most development work and are required by Homebrew." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing Xcode Command Line Tools"
    if command_exists xcode-select; then
        print_success "Xcode Command Line Tools already installed"
    else
        xcode-select --install
        print_success "Xcode Command Line Tools installation triggered"
        echo "Please wait for the installation to complete before continuing."
        echo "Press Enter when the installation is complete."
        read -r
    fi
}

# Step 2: Install Homebrew
step_homebrew() {
    confirm_step "Install Homebrew" "Homebrew is a package manager for macOS that allows you to easily install software and development tools. It's the foundation for installing most of the tools in this script." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing Homebrew"
    if command_exists brew; then
        print_success "Homebrew already installed"
        brew update
        print_success "Homebrew updated"
        return 0
    fi

    # Choose install source; on failure, return to this menu to try another source
    while true; do
        echo ""
        echo "Select Homebrew install source:"
        echo "  1) Official (GitHub)"
        echo "  2) Tsinghua TUNA mirror (mainland China)"
        echo "  3) USTC mirror (mainland China)"
        echo "  q) Abort"
        read -p "Enter choice [1-3/q] (default 1): " brew_source
        brew_source=${brew_source:-1}

        if [[ "$brew_source" == "q" ]]; then
            print_error "Homebrew installation aborted"
            exit 1
        fi

        # Clear mirror config possibly left over from a previous failed attempt
        unset HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN \
              HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE \
              HOMEBREW_INSTALL_FROM_API

        brew_mirror_env=()
        case "$brew_source" in
            2)
                tuna="https://mirrors.tuna.tsinghua.edu.cn"
                brew_mirror_env=(
                    "export HOMEBREW_API_DOMAIN=\"${tuna}/homebrew-bottles/api\""
                    "export HOMEBREW_BOTTLE_DOMAIN=\"${tuna}/homebrew-bottles\""
                    "export HOMEBREW_BREW_GIT_REMOTE=\"${tuna}/git/homebrew/brew.git\""
                    "export HOMEBREW_CORE_GIT_REMOTE=\"${tuna}/git/homebrew/homebrew-core.git\""
                )
                brew_install_git="${tuna}/git/homebrew/install.git"
                brew_install_url=""
                ;;
            3)
                ustc="https://mirrors.ustc.edu.cn"
                brew_mirror_env=(
                    "export HOMEBREW_API_DOMAIN=\"${ustc}/homebrew-bottles/api\""
                    "export HOMEBREW_BOTTLE_DOMAIN=\"${ustc}/homebrew-bottles\""
                    "export HOMEBREW_BREW_GIT_REMOTE=\"${ustc}/brew.git\""
                    "export HOMEBREW_CORE_GIT_REMOTE=\"${ustc}/homebrew-core.git\""
                )
                brew_install_git=""
                brew_install_url="${ustc}/misc/brew-install.sh"
                ;;
            *)
                brew_install_git=""
                brew_install_url=""
                ;;
        esac

        install_failed=""
        if [[ ${#brew_mirror_env[@]} -gt 0 ]]; then
            # Apply mirror env vars so the installer clones brew from the mirror
            for env_line in "${brew_mirror_env[@]}"; do
                eval "$env_line"
            done
            export HOMEBREW_INSTALL_FROM_API=1

            # The install script itself must also come from the mirror
            if [[ -n "$brew_install_git" ]]; then
                install_dir=$(mktemp -d)
                if ! git clone --depth=1 "$brew_install_git" "$install_dir"; then
                    print_error "Failed to clone Homebrew install script from mirror"
                    install_failed=1
                elif ! /bin/bash "$install_dir/install.sh"; then
                    print_error "Homebrew installation failed"
                    install_failed=1
                fi
                rm -rf "$install_dir"
            else
                install_script=$(curl -fsSL "$brew_install_url")
                if [[ -z "$install_script" ]]; then
                    print_error "Failed to download Homebrew install script from mirror"
                    install_failed=1
                elif ! /bin/bash -c "$install_script"; then
                    print_error "Homebrew installation failed"
                    install_failed=1
                fi
            fi
        else
            install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
            if [[ -z "$install_script" ]]; then
                print_error "Failed to download Homebrew install script (check network/proxy)"
                install_failed=1
            elif ! /bin/bash -c "$install_script"; then
                print_error "Homebrew installation failed"
                install_failed=1
            fi
        fi

        if [[ -n "$install_failed" ]]; then
            echo "Installation failed. Pick another source, or 'q' to abort."
            continue
        fi
        break
    done

    # Locate the installed brew binary (Apple Silicon or Intel)
    if [[ -x /opt/homebrew/bin/brew ]]; then
        brew_path=/opt/homebrew/bin/brew
    elif [[ -x /usr/local/bin/brew ]]; then
        brew_path=/usr/local/bin/brew
    else
        print_error "brew binary not found after installation"
        exit 1
    fi
    print_success "Homebrew installed"

    # Add Homebrew to PATH (idempotent: skip if already in ~/.zprofile)
    append_once "eval \"\$(${brew_path} shellenv)\"" ~/.zprofile
    eval "$(${brew_path} shellenv)"
    print_success "Homebrew added to PATH"

    # Persist mirror config so future brew update/install also use the mirror
    if [[ ${#brew_mirror_env[@]} -gt 0 ]]; then
        for env_line in "${brew_mirror_env[@]}"; do
            append_once "$env_line" ~/.zprofile
        done
        print_success "Homebrew mirror config saved to ~/.zprofile"
    fi
}

# Step 3: Install Git and configure
step_git() {
    confirm_step "Install and Configure Git" "Git is a version control system used for tracking changes in source code. This step will install Git and set up your global Git configuration with your name and email." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing and configuring Git"
    if command_exists git; then
        print_success "Git already installed"
    else
        brew install git
        print_success "Git installed"
    fi

    # Configure Git if not already configured
    if [ -z "$(git config --global user.name)" ]; then
        echo "Enter your Git username:"
        read -r git_username
        git config --global user.name "$git_username"

        echo "Enter your Git email:"
        read -r git_email
        git config --global user.email "$git_email"

        # Set some sensible Git defaults
        git config --global init.defaultBranch main
        git config --global core.editor "code --wait"
        git config --global pull.rebase false

        print_success "Git configured"
    else
        print_success "Git already configured"
    fi
}

# Step 4: Generate SSH key
step_ssh_key() {
    confirm_step "Generate SSH Key" "SSH keys are used for secure authentication with services like GitHub, GitLab, and remote servers. This step will generate an Ed25519 SSH key pair and add it to your SSH agent." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Generating SSH key"
    if [ -f ~/.ssh/id_ed25519 ]; then
        print_success "SSH key already exists"
    else
        echo "Generating a new SSH key (Ed25519 algorithm)"
        ssh-keygen -t ed25519 -C "$(git config --global user.email)"

        # Start the ssh-agent in the background
        eval "$(ssh-agent -s)"

        # Add SSH key to the ssh-agent
        ssh-add ~/.ssh/id_ed25519

        # Copy the SSH key to clipboard
        if command_exists pbcopy; then
            pbcopy < ~/.ssh/id_ed25519.pub
            print_success "SSH public key copied to clipboard"
            echo "Please add this key to your GitHub/GitLab account"
            echo "Public key: $(cat ~/.ssh/id_ed25519.pub)"
        else
            echo "Public key: $(cat ~/.ssh/id_ed25519.pub)"
            echo "Please copy this key and add it to your GitHub/GitLab account"
        fi
    fi
}

# Step 5: Install Visual Studio Code
step_vscode() {
    confirm_step "Install Visual Studio Code" "Visual Studio Code is a popular code editor with features like syntax highlighting, intelligent code completion, and debugging support. It has a rich ecosystem of extensions for various programming languages and tools." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing Visual Studio Code"
    if command_exists code; then
        print_success "VS Code already installed"
    else
        brew install --cask visual-studio-code
        print_success "VS Code installed"
    fi
}

# Install VS Code extensions (auto-skipped when VS Code is absent)
step_vscode_extensions() {
    command_exists code || return 3

    confirm_step "Install VS Code Extensions" "This step will install useful extensions for VS Code, including support for TypeScript, ESLint, Prettier, Python, Docker, GitHub Copilot, GitLens, Remote Containers, Live Server, and Code Spell Checker." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing VS Code extensions"
    extensions=(
        "ms-vscode.vscode-typescript-next"
        "dbaeumer.vscode-eslint"
        "esbenp.prettier-vscode"
        "ms-python.python"
        "ms-azuretools.vscode-docker"
        "github.copilot"
        "eamodio.gitlens"
        "ms-vscode-remote.remote-containers"
        "ritwickdey.liveserver"
        "streetsidesoftware.code-spell-checker"
    )

    for extension in "${extensions[@]}"; do
        print_info "Installing extension: $extension"
        code --install-extension "$extension"
    done
    print_success "VS Code extensions installed"
}

# Step 6: Install Node.js via NVM
step_node_nvm() {
    confirm_step "Install Node.js via NVM" "Node Version Manager (NVM) allows you to install and manage multiple versions of Node.js. This step will install NVM, the latest LTS version of Node.js, and several useful global npm packages like yarn, typescript, and nodemon." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing Node.js via NVM"
    if command_exists nvm; then
        print_success "NVM already installed"
        return 0
    fi

    if ! brew install nvm; then
        print_error "Failed to install NVM"
        exit 1
    fi

    # Create NVM directory
    mkdir -p ~/.nvm

    # Add NVM to shell profile (idempotent; path varies by brew prefix)
    nvm_prefix="$(brew --prefix nvm)"
    append_once 'export NVM_DIR="$HOME/.nvm"' ~/.zshrc
    append_once "[ -s \"${nvm_prefix}/nvm.sh\" ] && \\. \"${nvm_prefix}/nvm.sh\"" ~/.zshrc
    append_once "[ -s \"${nvm_prefix}/etc/bash_completion.d/nvm\" ] && \\. \"${nvm_prefix}/etc/bash_completion.d/nvm\"" ~/.zshrc

    # Source NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "${nvm_prefix}/nvm.sh" ] && \. "${nvm_prefix}/nvm.sh"

    print_success "NVM installed"

    # Install latest LTS version of Node.js
    print_info "Installing latest LTS version of Node.js"
    nvm install --lts
    nvm use --lts
    nvm alias default node

    print_success "Node.js LTS installed and set as default"

    # Install global npm packages
    if confirm_step "Install Global npm Packages" "This will install useful npm packages globally: yarn (package manager), typescript (typed JavaScript), ts-node (TypeScript execution), nodemon (auto-restart for Node.js), http-server (simple HTTP server), eslint (linter), and prettier (code formatter)."; then
        npm_packages=(
            "yarn"
            "typescript"
            "ts-node"
            "nodemon"
            "http-server"
            "eslint"
            "prettier"
        )

        for package in "${npm_packages[@]}"; do
            print_info "Installing npm package: $package"
            npm install -g "$package"
        done

        print_success "Global npm packages installed"
    fi
}

# Step 7: Install iTerm2
step_iterm2() {
    confirm_step "Install iTerm2" "iTerm2 is a replacement for the default Terminal app on macOS. It has many additional features like split panes, search, autocomplete, and more customization options." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing iTerm2"
    if [ -d "/Applications/iTerm.app" ]; then
        print_success "iTerm2 already installed"
    else
        brew install --cask iterm2
        print_success "iTerm2 installed"
    fi
}

# Step 8: Install and configure Oh My Zsh
step_oh_my_zsh() {
    confirm_step "Install Oh My Zsh" "Oh My Zsh is a framework for managing your Zsh configuration. It includes helpful functions, plugins, and themes. This step will also install the Powerlevel10k theme and useful plugins for autosuggestions and syntax highlighting." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing Oh My Zsh"
    if [ -d "$HOME/.oh-my-zsh" ]; then
        print_success "Oh My Zsh already installed"
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

        # Install Powerlevel10k theme
        print_info "Installing Powerlevel10k theme"
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

        # Install useful plugins
        print_info "Installing zsh-autosuggestions plugin"
        git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

        print_info "Installing zsh-syntax-highlighting plugin"
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

        # Update .zshrc
        print_info "Updating .zshrc configuration"
        sed -i '' 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
        sed -i '' 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

        print_success "Oh My Zsh installed and configured"
    fi
}

# Step 9: Install Docker
step_docker() {
    confirm_step "Install Docker" "Docker is a platform for developing, shipping, and running applications in containers. Containers allow you to package an application with all its dependencies and run it in any environment." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing Docker"
    if command_exists docker; then
        print_success "Docker already installed"
    else
        brew install --cask docker
        print_success "Docker installed"
        print_info "Please open Docker.app to complete the installation"
    fi
}

# Step 10: Install additional developer tools
step_dev_tools() {
    confirm_step "Install Additional Developer Tools" "This step will install various development tools including: build tools (cmake, ninja), programming languages (Python, Go, Rust), database tools (PostgreSQL, MySQL, SQLite), and cloud tools (AWS CLI, Terraform)." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Installing additional developer tools"

    # Package managers and build tools
    print_info "Installing build tools (cmake, ninja)"
    brew install cmake ninja

    # Programming languages
    if confirm_step "Install Programming Languages" "This will install Python, Go, and Rust programming languages."; then
        print_info "Installing programming languages (Python, Go, Rust)"
        brew install python go rust
    fi

    # Database tools
    if confirm_step "Install Database Tools" "This will install PostgreSQL, MySQL, and SQLite database systems."; then
        print_info "Installing database tools (PostgreSQL, MySQL, SQLite)"
        brew install postgresql mysql sqlite
    fi

    # Cloud tools
    if confirm_step "Install Cloud Tools" "This will install AWS CLI and Terraform for cloud infrastructure management."; then
        print_info "Installing cloud tools (AWS CLI, Terraform)"
        brew install awscli terraform
    fi

    # Useful command line tools
    if confirm_step "Install Command Line Tools" "This will install various useful command line tools like jq (JSON processor), ripgrep (fast grep), bat (better cat), and more."; then
        print_info "Installing command line tools"
        cli_tools=(
            "jq"           # JSON processor
            "ripgrep"      # Fast grep
            "fd"           # Fast find
            "bat"          # Better cat
            "exa"          # Better ls
            "htop"         # Better top
            "tldr"         # Simplified man pages
            "fzf"          # Fuzzy finder
            "tmux"         # Terminal multiplexer
            "tree"         # Directory tree
            "wget"         # File downloader
            "httpie"       # HTTP client
            "gh"           # GitHub CLI
        )

        for tool in "${cli_tools[@]}"; do
            print_info "Installing: $tool"
            brew install "$tool"
        done
    fi

    print_success "Additional developer tools installed"
}

# Step 11: Install useful applications via Homebrew Cask
step_apps() {
    print_section "Installing useful applications"

    apps=(
        "google-chrome"
        "firefox"
        "slack"
        "postman"
        "rectangle"     # Window manager
        "alfred"        # Spotlight replacement
        "notion"        # Note-taking
        "obsidian"      # Note-taking
        "figma"         # Design tool
    )

    echo -e "${CYAN}The following applications are available for installation:${NC}"
    local app_idx
    for app_idx in "${!apps[@]}"; do
        echo -e "  ${YELLOW}$((app_idx+1)).${NC} ${apps[$app_idx]}"
    done

    confirm_step "Install Applications" "This will install popular applications like Google Chrome, Firefox, Slack, Postman, Rectangle (window manager), Alfred (Spotlight replacement), Notion and Obsidian (note-taking apps), and Figma (design tool)." allow_back
    case $? in
        2) return 2 ;;
        1) echo "Skipping application installation"; return 0 ;;
    esac

    for app in "${apps[@]}"; do
        if confirm_step "Install $app" "This will install $app on your system."; then
            print_info "Installing: $app"
            brew install --cask "$app"
            print_success "$app installed"
        fi
    done
    print_success "Applications installation completed"
}

# Step 12: Configure macOS settings
step_macos_settings() {
    confirm_step "Configure macOS Settings" "This will configure various macOS settings optimized for development, including Finder preferences, keyboard settings, and security options. These changes will make your Mac more developer-friendly." allow_back
    case $? in
        2) return 2 ;;
        1) echo "Skipping macOS configuration"; return 0 ;;
    esac

    print_section "Configuring macOS settings"

    # Show hidden files in Finder
    if confirm_step "Show Hidden Files in Finder" "This will make Finder show hidden files (those starting with a dot)."; then
        defaults write com.apple.finder AppleShowAllFiles -bool true
        print_success "Finder set to show hidden files"
    fi

    # Show path bar in Finder
    if confirm_step "Show Path Bar in Finder" "This will display the path bar at the bottom of Finder windows."; then
        defaults write com.apple.finder ShowPathbar -bool true
        print_success "Finder path bar enabled"
    fi

    # Show status bar in Finder
    if confirm_step "Show Status Bar in Finder" "This will display the status bar at the bottom of Finder windows."; then
        defaults write com.apple.finder ShowStatusBar -bool true
        print_success "Finder status bar enabled"
    fi

    # Disable press-and-hold for keys in favor of key repeat
    if confirm_step "Enable Key Repeat" "This will disable the press-and-hold feature and enable key repeat, which is useful for coding."; then
        defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
        print_success "Key repeat enabled"
    fi

    # Set a faster keyboard repeat rate
    if confirm_step "Set Faster Keyboard Repeat Rate" "This will make keys repeat faster when held down."; then
        defaults write NSGlobalDomain KeyRepeat -int 2
        defaults write NSGlobalDomain InitialKeyRepeat -int 15
        print_success "Keyboard repeat rate increased"
    fi

    # Disable auto-correct
    if confirm_step "Disable Auto-Correct" "This will disable automatic text correction, which can be annoying when coding."; then
        defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
        print_success "Auto-correct disabled"
    fi

    # Require password immediately after sleep or screen saver begins
    if confirm_step "Enhance Security Settings" "This will require password immediately after sleep or screen saver begins."; then
        defaults write com.apple.screensaver askForPassword -int 1
        defaults write com.apple.screensaver askForPasswordDelay -int 0
        print_success "Security settings enhanced"
    fi

    # Save screenshots to the desktop
    if confirm_step "Configure Screenshot Location" "This will save screenshots to a 'Screenshots' folder on your Desktop."; then
        mkdir -p "${HOME}/Desktop/Screenshots"
        defaults write com.apple.screencapture location -string "${HOME}/Desktop/Screenshots"
        print_success "Screenshot location set to Desktop/Screenshots"
    fi

    # Save screenshots in PNG format
    if confirm_step "Set Screenshot Format to PNG" "This will save screenshots in PNG format."; then
        defaults write com.apple.screencapture type -string "png"
        print_success "Screenshot format set to PNG"
    fi

    # Restart affected applications
    print_info "Restarting Finder and SystemUIServer to apply changes"
    killall Finder
    killall SystemUIServer

    print_success "macOS settings configured"
}

# Step 13: Create a development workspace
step_workspace() {
    confirm_step "Create Development Workspace" "This will create a 'Workspace' directory in your home folder for organizing your development projects." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_section "Creating development workspace"
    mkdir -p ~/Workspace
    print_success "Created ~/Workspace directory"
}

# Final step: suggest a restart
step_restart() {
    confirm_step "Restart Computer" "It's recommended to restart your computer to ensure all changes take effect properly." allow_back
    case $? in 2) return 2 ;; 1) return 0 ;; esac

    print_info "Restarting your computer now..."
    sudo shutdown -r now
}

# Ordered list of steps; the driver below allows going back with 'b'
STEPS=(
    step_xcode_clt
    step_homebrew
    step_git
    step_ssh_key
    step_vscode
    step_vscode_extensions
    step_node_nvm
    step_iterm2
    step_oh_my_zsh
    step_docker
    step_dev_tools
    step_apps
    step_macos_settings
    step_workspace
    step_restart
)

# Run steps in order.
# Step return codes: 0/1 = done or skipped (move forward), 2 = go back,
# 3 = auto-skipped precondition (keep moving in the current direction,
# so going back can pass through it instead of bouncing forward).
run_steps() {
    # Deliberately uncommon names: bash locals are dynamically scoped, so a
    # step function reusing a generic name like `i` would corrupt this loop
    local _step_idx=0
    local _step_dir=1
    while (( _step_idx >= 0 && _step_idx < ${#STEPS[@]} )); do
        "${STEPS[$_step_idx]}"
        case $? in
            2) _step_dir=-1 ;;
            3) ;;
            *) _step_dir=1 ;;
        esac
        (( _step_idx += _step_dir ))
        if (( _step_idx < 0 )); then
            echo -e "${YELLOW}Already at the first step${NC}"
            _step_idx=0
            _step_dir=1
        fi
    done
}

# Welcome message
clear
cat << "EOF"
    __  ___          ____             __ __ _ __
   /  |/  /___ _____/ __ \___ _   __/ //_/(_) /_
  / /|_/ / __ `/ __/ / / / _ \ | / / ,<  / / __/
 / /  / / /_/ / /_/ /_/ /  __/ |/ / /| |/ / /_
/_/  /_/\__,_/\__/_____/\___/|___/_/ |_/_/\__/

EOF

echo -e "${YELLOW}Welcome to MacDevKit - Your Ultimate macOS Development Environment Setup Tool${NC}"
echo
echo -e "${CYAN}This script will help you:${NC}"
echo -e "  ${GREEN}✓${NC} Install essential developer tools"
echo -e "  ${GREEN}✓${NC} Configure your development environment"
echo -e "  ${GREEN}✓${NC} Set up programming languages and frameworks"
echo -e "  ${GREEN}✓${NC} Install useful applications"
echo -e "  ${GREEN}✓${NC} Optimize your macOS settings"
echo
echo -e "${YELLOW}Each step will be explained and you can choose to proceed (y), skip (n),${NC}"
echo -e "${YELLOW}or go back to the previous step (b).${NC}"
echo -e "${RED}Note: You may be asked for your password for some operations.${NC}"
echo
echo -e "${CYAN}Press Enter to begin your setup journey or Ctrl+C to exit...${NC}"
read -r

run_steps

# Final message
print_section "Setup Complete!"
echo -e "${GREEN}Your Mac has been set up for development.${NC}"
echo -e "${YELLOW}Some changes may require a restart to take effect.${NC}"
echo -e "${GREEN}Enjoy your new development environment!${NC}"
