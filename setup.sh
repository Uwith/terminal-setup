#!/bin/bash
#
# terminal-setup — Interactive Terminal Environment Setup Script
#
# A modern, user-friendly terminal configuration script with:
#   - Opt-in interactive installation (choose what you want)
#   - Complete state tracking and backup system
#   - One-command uninstall/rollback capability
#
# Platforms: macOS (Homebrew), Debian/Ubuntu (apt), Windows WSL
# Shells:   Fish, Zsh
# Tools:    Starship, bat, eza, fd, ripgrep, btop, zoxide, jq, tldr, delta, lazygit, fzf
#
# Usage:
#   ./setup.sh              # Interactive installation
#   ./setup.sh --help       # Show help
#   ./setup.sh uninstall     # Rollback all changes
#   ./setup.sh status       # Show installation status
#
# Author: Uwith
# License: MIT

set -euo pipefail

# =============================================================================
# Configuration & State
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# State directory for backups and tracking
STATE_DIR="$HOME/.terminal-setup"
BACKUP_DIR="$STATE_DIR/backups"
STATE_FILE="$STATE_DIR/state.json"
INSTALLED_PACKAGES_FILE="$STATE_DIR/installed_packages.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Logging Functions
# =============================================================================

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}"; }
log_question() { echo -e "${BOLD}${MAGENTA}? ${NC}$*${CYAN} [y/N]${NC}"; }

# =============================================================================
# State Management Functions
# =============================================================================

# Initialize state directory and files
init_state() {
    mkdir -p "$STATE_DIR" "$BACKUP_DIR"
    
    # Initialize state file if not exists
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << 'EOF'
{
  "version": "1.0",
  "installed_at": "",
  "os": "",
  "shell": "",
  "modules": {},
  "backups": []
}
EOF
    fi
    
    # Initialize packages file
    touch "$INSTALLED_PACKAGES_FILE"
}

# Record installed package
record_package() {
    local pkg="$1"
    if [[ -n "$pkg" ]]; then
        echo "$pkg" >> "$INSTALLED_PACKAGES_FILE"
        log_info "Recorded: $pkg"
    fi
}

# Backup a file with timestamp
backup_file() {
    local file="$1"
    if [[ -f "$file" && ! -L "$file" ]]; then
        local timestamp
        timestamp="$(date +%s)"
        local backup_path="$BACKUP_DIR/$(basename "$file").$timestamp.bak"
        
        cp "$file" "$backup_path"
        chmod 644 "$backup_path"
        
        # Record backup in state
        local backup_record="{\"file\": \"$file\", \"backup\": \"$backup_path\", \"timestamp\": $timestamp}"
        
        # Simple append to backups array - for full rollback we'll use the backup files
        log_info "Backed up: $file -> $backup_path"
        return 0
    fi
    return 1
}

# Restore a backup file
restore_file() {
    local file="$1"
    local backup_path="$2"
    
    if [[ -f "$backup_path" ]]; then
        cp "$backup_path" "$file"
        log_success "Restored: $file from $backup_path"
        return 0
    fi
    return 1
}

# Find latest backup for a file
find_latest_backup() {
    local file="$1"
    local filename
    filename="$(basename "$file")"
    
    # Find the latest backup for this file
    local latest=""
    local latest_time=0
    
    for backup in "$BACKUP_DIR"/${filename}.*; do
        if [[ -f "$backup" ]]; then
            local btime
            btime="$(echo "$backup" | grep -oE '[0-9]+\.bak$' | sed 's/\.bak$//')"
            if [[ "$btime" -gt "$latest_time" ]]; then
                latest_time="$btime"
                latest="$backup"
            fi
        fi
    done
    
    echo "$latest"
}

# =============================================================================
# OS Detection
# =============================================================================

detect_os() {
    local uname_out
    uname_out="$(uname -s)"

    case "$uname_out" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
                echo "wsl"
            elif [[ -f /etc/debian_version ]] || grep -qi 'debian\|ubuntu' /etc/os-release 2>/dev/null; then
                echo "debian"
            else
                echo "unsupported"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows-native"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

# Get package manager based on OS
get_package_manager() {
    local os="$1"
    case "$os" in
        macos)
            echo "brew"
            ;;
        debian|wsl)
            echo "apt"
            ;;
        *)
            echo ""
            ;;
    esac
}

# =============================================================================
# Command Availability Check
# =============================================================================

has_cmd() {
    command -v "$1" &>/dev/null
}

# =============================================================================
# Package Installation Functions
# =============================================================================

# Install package using appropriate package manager
pkg_install() {
    local pkg="$1"
    local os="$2"
    
    case "$os" in
        macos)
            if brew list "$pkg" &>/dev/null; then
                log_success "$pkg already installed"
                return 0
            fi
            log_info "Installing $pkg via Homebrew..."
            brew install "$pkg"
            record_package "brew:$pkg"
            log_success "$pkg installed"
            ;;
        debian|wsl)
            if dpkg -s "$pkg" &>/dev/null 2>&1; then
                log_success "$pkg already installed"
                return 0
            fi
            log_info "Installing $pkg via apt..."
            sudo apt-get install -y "$pkg"
            record_package "apt:$pkg"
            log_success "$pkg installed"
            ;;
    esac
}

# Install cask (macOS only)
cask_install() {
    local cask="$1"
    if [[ "$OS" != "macos" ]]; then
        log_warn "Cask install is macOS-only, skipping $cask"
        return 0
    fi
    
    if brew list --cask "$cask" &>/dev/null; then
        log_success "$cask already installed"
        return 0
    fi
    
    log_info "Installing $cask via Homebrew Cask..."
    brew install --cask "$cask"
    record_package "brew-cask:$cask"
    log_success "$cask installed"
}

# Install via curl (for tools not in package managers)
install_via_curl() {
    local name="$1"
    local url="$2"
    local install_path="$3"
    
    if [[ -z "$install_path" ]]; then
        install_path="/usr/local/bin/$name"
    fi
    
    if has_cmd "$name"; then
        log_success "$name already installed"
        return 0
    fi
    
    log_info "Installing $name from $url..."
    curl -fsSL "$url" | sudo tee "$install_path" >/dev/null
    sudo chmod +x "$install_path"
    record_package "curl:$name"
    log_success "$name installed"
}

# =============================================================================
# Uninstall / Rollback Functions
# =============================================================================

uninstall_all() {
    log_header "Uninstalling and rolling back all changes"
    
    # Check if state directory exists
    if [[ ! -d "$STATE_DIR" ]]; then
        log_warn "No state directory found at $STATE_DIR"
        log_warn "Nothing to uninstall"
        return 0
    fi
    
    # Restore all backup files
    log_info "Restoring backup files..."
    if [[ -d "$BACKUP_DIR" ]]; then
        local restored=0
        for backup in "$BACKUP_DIR"/*.bak; do
            if [[ -f "$backup" ]]; then
                local original
                original="$(echo "$backup" | sed 's/\.[0-9]\+\.bak$//')"
                local home_original
                home_original="$HOME/$(basename "$original")"
                
                # Try to restore to original location
                if [[ -f "$home_original" ]]; then
                    restore_file "$home_original" "$backup"
                    restored=$((restored + 1))
                fi
            fi
        done
        log_success "Restored $restored backup files"
    fi
    
    # Uninstall packages
    log_info "Uninstalling installed packages..."
    if [[ -f "$INSTALLED_PACKAGES_FILE" ]]; then
        local uninstalled=0
        local errors=0
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="$(echo "$line" | xargs)"
            [[ -z "$line" ]] && continue
            
            local pkg_manager
            local pkg_name
            pkg_manager="$(echo "$line" | cut -d':' -f1)"
            pkg_name="$(echo "$line" | cut -d':' -f2-)"
            
            case "$pkg_manager" in
                brew)
                    if brew list "$pkg_name" &>/dev/null; then
                        log_info "Uninstalling $pkg_name (Homebrew)..."
                        if brew uninstall "$pkg_name" 2>/dev/null; then
                            uninstalled=$((uninstalled + 1))
                            log_success "Uninstalled: $pkg_name"
                        else
                            errors=$((errors + 1))
                            log_warn "Failed to uninstall: $pkg_name"
                        fi
                    fi
                    ;;
                brew-cask)
                    if brew list --cask "$pkg_name" &>/dev/null; then
                        log_info "Uninstalling $pkg_name (Homebrew Cask)..."
                        if brew uninstall --cask "$pkg_name" 2>/dev/null; then
                            uninstalled=$((uninstalled + 1))
                            log_success "Uninstalled: $pkg_name"
                        else
                            errors=$((errors + 1))
                            log_warn "Failed to uninstall: $pkg_name"
                        fi
                    fi
                    ;;
                apt)
                    if dpkg -s "$pkg_name" &>/dev/null 2>&1; then
                        log_info "Uninstalling $pkg_name (apt)..."
                        if sudo apt-get remove -y "$pkg_name" 2>/dev/null; then
                            uninstalled=$((uninstalled + 1))
                            log_success "Uninstalled: $pkg_name"
                        else
                            errors=$((errors + 1))
                            log_warn "Failed to uninstall: $pkg_name"
                        fi
                    fi
                    ;;
                curl)
                    log_info "Removing manually installed: $pkg_name"
                    if sudo rm -f "/usr/local/bin/$pkg_name" 2>/dev/null; then
                        uninstalled=$((uninstalled + 1))
                        log_success "Removed: $pkg_name"
                    else
                        errors=$((errors + 1))
                        log_warn "Failed to remove: $pkg_name"
                    fi
                    ;;
                *)
                    errors=$((errors + 1))
                    log_warn "Unknown package manager: $pkg_manager for $pkg_name"
                    ;;
            esac
        done < "$INSTALLED_PACKAGES_FILE"
        
        log_success "Uninstalled $uninstalled packages ($errors errors)"
    fi
    
    # Remove state directory
    log_info "Cleaning up state directory..."
    rm -rf "$STATE_DIR"
    log_success "Cleanup complete"
    
    echo ""
    log_success "Uninstall complete! All changes have been rolled back."
    log_info "Note: Some system-wide changes may require manual cleanup."
}

# Show status
show_status() {
    log_header "Installation Status"
    
    if [[ ! -d "$STATE_DIR" ]]; then
        echo "  No installation found"
        return 0
    fi
    
    echo "  State directory: $STATE_DIR"
    echo "  Backups: $BACKUP_DIR"
    
    if [[ -f "$STATE_FILE" ]]; then
        echo ""
        echo "  Installed modules:"
        cat "$STATE_FILE" | grep -A 100 '"modules"' | head -20
    fi
    
    if [[ -f "$INSTALLED_PACKAGES_FILE" ]]; then
        local count
        count="$(wc -l < "$INSTALLED_PACKAGES_FILE" | tr -d ' ')"
        echo ""
        echo "  Installed packages: $count"
        echo ""
        echo "  Packages list:"
        cat "$INSTALLED_PACKAGES_FILE"
    fi
}

# Show help
show_help() {
    echo ""
    echo "Usage: $SCRIPT_NAME [OPTION|COMMAND]"
    echo ""
    echo "Commands:"
    echo "  ./setup.sh              Interactive installation"
    echo "  ./setup.sh uninstall    Rollback all changes and uninstall"
    echo "  ./setup.sh status      Show installation status"
    echo "  ./setup.sh --help       Show this help message"
    echo ""
    echo "Features:"
    echo "  - Opt-in interactive installation (choose what you want)"
    echo "  - Complete state tracking and backup system"
    echo "  - One-command uninstall/rollback"
    echo "  - Cross-platform support (macOS, Linux)"
    echo ""
}

# =============================================================================
# Interactive Installation Functions
# =============================================================================

# Ask user for confirmation
ask_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local answer=""
    
    log_question "$prompt"
    read -r answer
    
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    
    case "$answer" in
        [Yy]|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Install Homebrew (macOS)
install_homebrew() {
    if ! has_cmd brew; then
        if ask_confirm "Install Homebrew?"; then
            log_info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            # Auto-detect Homebrew prefix
            if [[ -d /opt/homebrew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -d /usr/local/Homebrew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            
            record_package "brew:homebrew"
            log_success "Homebrew installed"
        else
            log_info "Skipping Homebrew"
            return 1
        fi
    else
        log_success "Homebrew already installed"
    fi
    return 0
}

# Install basic tools for Debian/Ubuntu
install_basic_tools() {
    local tools=("curl" "git" "wget" "unzip" "build-essential")
    
    if ask_confirm "Install basic build tools (curl, git, etc.)?"; then
        for tool in "${tools[@]}"; do
            pkg_install "$tool" "$OS"
        done
        return 0
    fi
    return 1
}

# Install terminal emulator
install_terminal() {
    case "$OS" in
        macos)
            if ask_confirm "Install Ghostty terminal emulator?"; then
                cask_install "ghostty"
                return 0
            fi
            ;;
        debian)
            log_info "Ghostty is not easily available on Linux via apt."
            echo "  Options to install Ghostty on Linux:"
            echo "    - Snap:    sudo snap install ghostty"
            echo "    - Build:   https://ghostty.org/docs/install/build"
            echo "    - Or use any other terminal (kitty, alacritty, etc.)"
            if ask_confirm "Skip terminal emulator installation?"; then
                return 0
            fi
            ;;
        wsl)
            log_info "WSL detected — terminal emulator runs on the Windows side."
            echo "  Install Ghostty for Windows: https://ghostty.org"
            echo "  Or use Windows Terminal, which works great with WSL."
            return 0
            ;;
    esac
    return 1
}

# Install Nerd Font (MesloLGS NF)
install_nerd_font() {
    # Determine font directory based on OS
    local FONT_DIR=""
    case "$OS" in
        macos)
            FONT_DIR="$HOME/Library/Fonts"
            ;;
        debian|wsl)
            FONT_DIR="$HOME/.local/share/fonts"
            ;;
    esac
    
    local MESLO_FONTS=(
        "MesloLGS NF Regular.ttf"
        "MesloLGS NF Bold.ttf"
        "MesloLGS NF Italic.ttf"
        "MesloLGS NF Bold Italic.ttf"
    )
    
    local FONT_SRC_DIR="$SCRIPT_DIR/fonts"
    local FONT_INSTALLED=true
    
    # Check if fonts are already installed
    for font in "${MESLO_FONTS[@]}"; do
        [[ ! -f "$FONT_DIR/$font" ]] && FONT_INSTALLED=false && break
    done
    
    if $FONT_INSTALLED; then
        log_success "MesloLGS NF fonts already installed"
        return 0
    fi
    
    if ask_confirm "Install MesloLGS NF nerd fonts?"; then
        log_info "Installing MesloLGS NF fonts..."
        mkdir -p "$FONT_DIR"
        
        for font in "${MESLO_FONTS[@]}"; do
            if [[ -f "$FONT_SRC_DIR/$font" ]]; then
                cp "$FONT_SRC_DIR/$font" "$FONT_DIR/$font"
            else
                log_warn "Font not found in repo: $font"
            fi
        done
        
        # Rebuild font cache on Linux
        if [[ "$OS" == "debian" || "$OS" == "wsl" ]]; then
            if has_cmd fc-cache; then
                fc-cache -fv "$FONT_DIR"
            fi
        fi
        
        log_success "MesloLGS NF fonts installed"
        return 0
    fi
    return 1
}

# Install Fish Shell
install_fish() {
    if ask_confirm "Install Fish Shell?"; then
        case "$OS" in
            macos)
                pkg_install "fish" "$OS"
                
                local FISH_PATH
                FISH_PATH="$(which fish)"
                if ! grep -qxF "$FISH_PATH" /etc/shells 2>/dev/null; then
                    log_info "Adding Fish to /etc/shells..."
                    echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
                fi
                
                if [[ "$SHELL" != "$FISH_PATH" ]]; then
                    if ask_confirm "Set Fish as default shell?"; then
                        chsh -s "$FISH_PATH"
                        log_success "Default shell changed to Fish"
                    fi
                fi
                ;;
            debian|wsl)
                # Fish PPA for latest version on Ubuntu/Debian
                if [[ -f /etc/lsb-release ]] && grep -qi ubuntu /etc/lsb-release 2>/dev/null; then
                    log_info "Adding Fish PPA for latest version..."
                    sudo apt-add-repository -y ppa:fish-shell/release-3
                    sudo apt-get update
                fi
                pkg_install "fish" "$OS"
                
                local FISH_PATH
                FISH_PATH="$(which fish)"
                if ! grep -qxF "$FISH_PATH" /etc/shells 2>/dev/null; then
                    log_info "Adding Fish to /etc/shells..."
                    echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
                fi
                
                if [[ "$SHELL" != "$FISH_PATH" ]]; then
                    if ask_confirm "Set Fish as default shell?"; then
                        chsh -s "$FISH_PATH"
                        log_success "Default shell changed to Fish"
                    fi
                fi
                ;;
        esac
        return 0
    fi
    return 1
}

# Install Zsh Shell with plugins
install_zsh() {
    if ask_confirm "Install Zsh Shell with fish-like plugins?"; then
        case "$OS" in
            macos)
                # Zsh is pre-installed on macOS, just install the plugins
                local plugins=("zsh-autosuggestions" "zsh-syntax-highlighting" "zsh-completions")
                for plugin in "${plugins[@]}"; do
                    if ! brew list "$plugin" &>/dev/null; then
                        pkg_install "$plugin" "$OS"
                    fi
                done
                
                local ZSH_PATH
                ZSH_PATH="$(which zsh)"
                if [[ "$SHELL" != "$ZSH_PATH" ]]; then
                    if ask_confirm "Set Zsh as default shell?"; then
                        chsh -s "$ZSH_PATH"
                        log_success "Default shell changed to Zsh"
                    fi
                fi
                ;;
            debian|wsl)
                # Install Zsh if not present
                pkg_install "zsh" "$OS"
                
                # Install Zsh plugins from apt or git clone
                local ZSH_PLUGINS_DIR="/usr/share"
                
                # zsh-autosuggestions
                if [[ ! -f "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
                   ! dpkg -s zsh-autosuggestions &>/dev/null 2>&1; then
                    log_info "Installing zsh-autosuggestions..."
                    if ! sudo apt-get install -y zsh-autosuggestions 2>/dev/null; then
                        log_info "apt package not available, cloning from git..."
                        sudo git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS_DIR/zsh-autosuggestions"
                    fi
                    record_package "apt:zsh-autosuggestions"
                fi
                
                # zsh-syntax-highlighting
                if [[ ! -f "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
                   ! dpkg -s zsh-syntax-highlighting &>/dev/null 2>&1; then
                    log_info "Installing zsh-syntax-highlighting..."
                    if ! sudo apt-get install -y zsh-syntax-highlighting 2>/dev/null; then
                        log_info "apt package not available, cloning from git..."
                        sudo git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
                    fi
                    record_package "apt:zsh-syntax-highlighting"
                fi
                
                local ZSH_PATH
                ZSH_PATH="$(which zsh)"
                if [[ "$SHELL" != "$ZSH_PATH" ]]; then
                    if ask_confirm "Set Zsh as default shell?"; then
                        chsh -s "$ZSH_PATH"
                        log_success "Default shell changed to Zsh"
                    fi
                fi
                ;;
        esac
        return 0
    fi
    return 1
}

# Install shell choice
install_shell() {
    log_header "Shell Setup"
    
    echo "  Please choose your shell:"
    echo "  1) Fish - Modern shell, amazing defaults, not POSIX"
    echo "  2) Zsh  - POSIX-compatible, fish-like with plugins"
    echo "  3) Skip shell installation"
    echo ""
    
    while true; do
        read -rp "Choose [1/2/3, default: 3]: " choice
        case "$choice" in
            1|fish)
                install_fish
                echo "fish" > "$STATE_DIR/shell.txt"
                return 0
                ;;
            2|zsh)
                install_zsh
                echo "zsh" > "$STATE_DIR/shell.txt"
                return 0
                ;;
            3|"")
                echo "skip" > "$STATE_DIR/shell.txt"
                return 0
                ;;
            *)
                echo "Please enter 1, 2, or 3."
                ;;
        esac
    done
}

# Install Starship prompt
install_starship() {
    if ask_confirm "Install Starship prompt?"; then
        case "$OS" in
            macos)
                pkg_install "starship" "$OS"
                ;;
            debian|wsl)
                if [[ -f "$SCRIPT_DIR/bin/linux-x86_64/starship" ]]; then
                    # Use bundled binary
                    log_info "Installing Starship from bundled binary..."
                    sudo cp "$SCRIPT_DIR/bin/linux-x86_64/starship" /usr/local/bin/starship
                    sudo chmod +x /usr/local/bin/starship
                    record_package "bundled:starship"
                else
                    # Download from GitHub releases
                    log_info "Downloading Starship from GitHub releases..."
                    local starship_arch
                    case "$(uname -m)" in
                        x86_64)  starship_arch="x86_64" ;;
                        aarch64) starship_arch="aarch64" ;;
                        *) log_error "Unsupported arch for Starship: $(uname -m)" ;;
                    esac
                    local starship_tmp
                    starship_tmp="$(mktemp -d)"
                    curl -fsSL "https://github.com/starship/starship/releases/latest/download/starship-${starship_arch}-unknown-linux-musl.tar.gz" \
                        | tar xz -C "$starship_tmp" \
                        && sudo cp "$starship_tmp/starship" /usr/local/bin/starship \
                        && sudo chmod +x /usr/local/bin/starship
                    rm -rf "$starship_tmp"
                    record_package "curl:starship"
                fi
                ;;
        esac
        
        # Deploy Starship config
        if ask_confirm "Deploy Starship configuration (Catppuccin Mocha theme)?"; then
            mkdir -p "$HOME/.config"
            backup_file "$HOME/.config/starship.toml"
            
            if [[ -f "$SCRIPT_DIR/configs/starship.toml" ]]; then
                cp "$SCRIPT_DIR/configs/starship.toml" "$HOME/.config/starship.toml"
                log_success "Starship config deployed"
            else
                # Create default Starship config
                cat > "$HOME/.config/starship.toml" << 'EOF'
# Starship Configuration - Catppuccin Mocha Theme

# Get editor completions based on the current shell
format = "$schema"

# Inserts a blank line between shell prompts
add_newline = true

# Replace the "❯" symbol in the prompt with "➜"
[character] # The name of the module we are configuring is "character"
success_symbol = "[➜](bold green)" # The "success_symbol" segment is being set to "➜" with the color "bold green"
error_symbol = "[✗](bold red)"

# Disable the package module, hiding it from the prompt completely
[package]
disabled = true

# The prefix "*" represents the repository root that we match on. The prefix "." represents
# the current directory. In this case, we are matching on the repository root only as
# we use `*` and not `*` or `.`.
[directory]
truncation_length = 3 # The number of parent directories that the current directory should be truncated to
style = "bold cyan"

# Here we disable the `read_only` option for the python module. This means that the
# prompt will not display a 🔒 when a file is read only, which is the default behavior.
[python]
disabled = false
pyenv_version_name = true
pyenv_prefix = "venv "

# Disable the rust module
[rust]
disabled = true

# Node.js module
[nodejs]
disabled = false

# Git module
[git_branch]
symbol = " "

[git_status]
format = "([\[$all_status$ahead_behind\]]($style) )"

# Catppuccin Mocha theme colors
[palette]
mocha = "#1e1e2e"
rosewater = "#f5e0dc"
flamingo = "#f2cdcd"
pink = "#f5c2e7"
majenta = "#cba6f7"
red = "#f38ba8"
maroon = "#eba0ac"
peach = "#fab387"
yellow = "#f9e2af"
green = "#a6e3a1"
teal = "#94e2d5"
sky = "#89d185"
sapphire = "#89b4fa"
blue = "#89b4fa"
lavender = "#b4befe"
text = "#cdd6f4"
subtext1 = "#cdd6f4"
subtext0 = "#cdd6f4"
overlay2 = "#cdd6f4"
overlay1 = "#cdd6f4"
overlay0 = "#6c7086"
surface2 = "#313244"
surface1 = "#45475a"
surface0 = "#45475a"
base = "#1e1e2e"
mantle = "#181825"
crust = "#11111b"
EOF
                log_success "Starship config created with Catppuccin Mocha theme"
            fi
        fi
        return 0
    fi
    return 1
}

# Install modern CLI tools
install_cli_tools() {
    log_header "Modern CLI Tools"
    
    local TOOLS=(
        "bat:Modern cat with syntax highlighting"
        "eza:Modern ls with icons and colors"
        "fd:Fast and user-friendly find"
        "ripgrep:Fast grep alternative"
        "btop:Beautiful system monitor"
        "zoxide:Smart cd that learns your habits"
        "jq:JSON processor"
        "tldr:Simplified man pages with examples"
        "fzf:Fuzzy finder"
        "git-delta:Beautiful git diffs"
        "lazygit:Git TUI"
    )
    
    for tool_desc in "${TOOLS[@]}"; do
        local tool
        tool="$(echo "$tool_desc" | cut -d':' -f1)"
        local desc
        desc="$(echo "$tool_desc" | cut -d':' -f2-)"
        
        if ask_confirm "Install ${tool} (${desc})?"; then
            case "$OS" in
                macos)
                    pkg_install "$tool" "$OS"
                    ;;
                debian|wsl)
                    # Special handling for Debian/Ubuntu
                    case "$tool" in
                        bat)
                            if ! has_cmd bat; then
                                if ! pkg_install "bat" "$OS"; then
                                    # On Debian/Ubuntu, bat might be batcat
                                    if has_cmd batcat; then
                                        mkdir -p "$HOME/.local/bin"
                                        ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
                                        record_package "symlink:bat"
                                        log_success "bat symlink created"
                                    else
                                        log_warn "Could not install bat"
                                    fi
                                fi
                            fi
                            ;;
                        eza)
                            if ! has_cmd eza; then
                                if ! pkg_install "eza" "$OS"; then
                                    # Try bundled binary
                                    if [[ -f "$SCRIPT_DIR/bin/linux-x86_64/eza" ]]; then
                                        sudo cp "$SCRIPT_DIR/bin/linux-x86_64/eza" /usr/local/bin/eza
                                        sudo chmod +x /usr/local/bin/eza
                                        record_package "bundled:eza"
                                    else
                                        log_warn "Could not install eza"
                                    fi
                                fi
                            fi
                            ;;
                        fd)
                            if ! has_cmd fd; then
                                if ! pkg_install "fd-find" "$OS"; then
                                    # On Debian/Ubuntu, fd might be fdfind
                                    if has_cmd fdfind; then
                                        mkdir -p "$HOME/.local/bin"
                                        ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
                                        record_package "symlink:fd"
                                        log_success "fd symlink created"
                                    else
                                        log_warn "Could not install fd"
                                    fi
                                fi
                            fi
                            ;;
                        ripgrep)
                            pkg_install "ripgrep" "$OS"
                            ;;
                        btop)
                            if ! has_cmd btop; then
                                if ! pkg_install "btop" "$OS"; then
                                    if has_cmd snap; then
                                        sudo snap install btop
                                        record_package "snap:btop"
                                    else
                                        log_warn "Could not install btop"
                                    fi
                                fi
                            fi
                            ;;
                        zoxide)
                            if ! has_cmd zoxide; then
                                if ! pkg_install "zoxide" "$OS"; then
                                    if has_cmd snap; then
                                        sudo snap install zoxide
                                        record_package "snap:zoxide"
                                    elif [[ -f "$SCRIPT_DIR/scripts/install-zoxide.sh" ]]; then
                                        bash "$SCRIPT_DIR/scripts/install-zoxide.sh"
                                        record_package "script:zoxide"
                                    else
                                        log_warn "Could not install zoxide"
                                    fi
                                fi
                            fi
                            ;;
                        jq)
                            pkg_install "jq" "$OS"
                            ;;
                        tldr)
                            if ! has_cmd tldr; then
                                if ! pkg_install "tealdeer" "$OS"; then
                                    if [[ -f "$SCRIPT_DIR/bin/linux-x86_64/tldr" ]]; then
                                        sudo cp "$SCRIPT_DIR/bin/linux-x86_64/tldr" /usr/local/bin/tldr
                                        sudo chmod +x /usr/local/bin/tldr
                                        record_package "bundled:tldr"
                                    else
                                        log_warn "Could not install tldr"
                                    fi
                                fi
                            fi
                            ;;
                        git-delta|delta)
                            if ! has_cmd delta; then
                                if ! pkg_install "git-delta" "$OS"; then
                                    if [[ -f "$SCRIPT_DIR/bin/linux-x86_64/delta" ]]; then
                                        sudo cp "$SCRIPT_DIR/bin/linux-x86_64/delta" /usr/local/bin/delta
                                        sudo chmod +x /usr/local/bin/delta
                                        record_package "bundled:delta"
                                    else
                                        log_warn "Could not install delta"
                                    fi
                                fi
                            fi
                            ;;
                        lazygit)
                            if ! has_cmd lazygit; then
                                if ! pkg_install "lazygit" "$OS"; then
                                    if [[ -f "$SCRIPT_DIR/bin/linux-x86_64/lazygit" ]]; then
                                        sudo cp "$SCRIPT_DIR/bin/linux-x86_64/lazygit" /usr/local/bin/lazygit
                                        sudo chmod +x /usr/local/bin/lazygit
                                        record_package "bundled:lazygit"
                                    else
                                        log_warn "Could not install lazygit"
                                    fi
                                fi
                            fi
                            ;;
                        fzf)
                            pkg_install "fzf" "$OS"
                            ;;
                        *)
                            pkg_install "$tool" "$OS"
                            ;;
                    esac
                    ;;
            esac
        fi
    done
}

# Install fnm + Node.js
install_fnm() {
    log_header "fnm + Node.js (Node Version Manager)"
    
    log_info "fnm is a Fast Node Manager (Rust-based, ~1ms shell startup)"
    echo "  Note: fnm manages its own Node.js versions."
    echo "  If you already have Node.js installed, fnm may shadow it."
    echo ""
    
    if ask_confirm "Install fnm (Fast Node Manager)?"; then
        case "$OS" in
            macos)
                pkg_install "fnm" "$OS"
                ;;
            debian|wsl)
                log_info "Installing fnm via official installer..."
                curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
                export PATH="$HOME/.local/share/fnm:$PATH"
                record_package "curl:fnm"
                ;;
        esac
        
        if has_cmd fnm; then
            # Load fnm
            eval "$(fnm env --use-on-cd)"
            
            if ask_confirm "Install Node.js LTS?"; then
                fnm install --lts
                fnm default lts-latest
                fnm use lts-latest
                log_success "Node.js LTS installed"
            fi
        fi
        return 0
    fi
    return 1
}

# Install Zellij
install_zellij() {
    log_header "Zellij (Terminal Multiplexer)"
    
    echo "  Zellij is a modern terminal multiplexer (like tmux, but better UX)."
    echo ""
    
    if ask_confirm "Install Zellij?"; then
        case "$OS" in
            macos)
                pkg_install "zellij" "$OS"
                ;;
            debian|wsl)
                if [[ -f "$SCRIPT_DIR/bin/linux-x86_64/zellij" ]]; then
                    sudo cp "$SCRIPT_DIR/bin/linux-x86_64/zellij" /usr/local/bin/zellij
                    sudo chmod +x /usr/local/bin/zellij
                    record_package "bundled:zellij"
                else
                    log_info "Downloading Zellij from GitHub releases..."
                    local zellij_arch
                    case "$(uname -m)" in
                        x86_64)  zellij_arch="x86_64" ;;
                        aarch64) zellij_arch="aarch64" ;;
                        *) log_warn "Unsupported arch for Zellij: $(uname -m)"; return 1 ;;
                    esac
                    local zellij_url="https://github.com/zellij-org/zellij/releases/latest/download/zellij-${zellij_arch}-unknown-linux-musl.tar.gz"
                    local zellij_tmp
                    zellij_tmp="$(mktemp -d)"
                    curl -fsSL "$zellij_url" | tar xz -C "$zellij_tmp" \
                        && sudo cp "$zellij_tmp/zellij" /usr/local/bin/zellij \
                        && sudo chmod +x /usr/local/bin/zellij
                    rm -rf "$zellij_tmp"
                    record_package "curl:zellij"
                fi
                ;;
        esac
        
        log_success "Zellij installed"
        return 0
    fi
    return 1
}

# Deploy shell configuration files
deploy_shell_config() {
    log_header "Shell Configuration"
    
    # Determine which shell is being used
    local shell_type=""
    if [[ -f "$STATE_DIR/shell.txt" ]]; then
        shell_type="$(cat "$STATE_DIR/shell.txt")"
    fi
    
    if [[ "$shell_type" == "fish" ]]; then
        # Fish configuration
        local FISH_CONFIG_DIR="$HOME/.config/fish"
        mkdir -p "$FISH_CONFIG_DIR"
        
        if ask_confirm "Deploy Fish configuration?"; then
            backup_file "$FISH_CONFIG_DIR/config.fish"
            
            if [[ -f "$SCRIPT_DIR/configs/config.fish" ]]; then
                cp "$SCRIPT_DIR/configs/config.fish" "$FISH_CONFIG_DIR/config.fish"
            else
                # Create basic Fish config
                cat > "$FISH_CONFIG_DIR/config.fish" << 'EOF'
# Fish Shell Configuration

# Starship prompt
starship init fish | source

# Abbreviations (compatible with Fish 3.x and 4.x)
if status is-interactive
    abbr -a ls "eza --icons --group-directories-first"
    abbr -a ll "eza -la --icons --group-directories-first"
    abbr -a lt "eza --tree --icons --level=2"
    abbr -a cat "bat"
    abbr -a find "fd"
    abbr -a grep "rg"
    abbr -a top "btop"
    abbr -a lg "lazygit"
    abbr -a cd "z"
end

# zoxide
zoxide init fish | source

# fzf
fzf --fish | source
set -gx FZF_DEFAULT_OPTS '--height 40% --layout=reverse --border'
if command -q fd
    set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
    set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden --follow --exclude .git'
end

# Local bin (Linux)
if test -d "$HOME/.local/bin"
    fish_add_path "$HOME/.local/bin"
end
EOF
            fi
            log_success "Fish config deployed"
        fi
        
        # Fish functions
        if ask_confirm "Add custom Fish functions (set-ssh-key)?"; then
            mkdir -p "$FISH_CONFIG_DIR/functions"
            cat > "$FISH_CONFIG_DIR/functions/set-ssh-key.fish" << 'EOF'
function set-ssh-key --description "Switch SSH key"
    if test (count $argv) -eq 0
        echo "Usage: set-ssh-key [key-name]"
        echo ""
        echo "Available keys:"
        for key in ~/.ssh/id_*
            basename "$key" | string replace -r '\..*$' ''
        end
        return 1
    end
    
    local key_name=$argv[1]
    local key_path="$HOME/.ssh/$key_name"
    
    if not test -f "$key_path"
        echo "Key not found: $key_path"
        return 1
    end
    
    # Clear SSH agent
    ssh-add -D
    
    # Add the key
    ssh-add "$key_path"
    
    echo "SSH key set to: $key_name"
end
EOF
            log_success "Fish functions deployed"
        fi
        
    elif [[ "$shell_type" == "zsh" ]]; then
        # Zsh configuration
        if ask_confirm "Deploy Zsh configuration?"; then
            backup_file "$HOME/.zshrc"
            
            if [[ -f "$SCRIPT_DIR/configs/.zshrc" ]]; then
                cp "$SCRIPT_DIR/configs/.zshrc" "$HOME/.zshrc"
            else
                # Create basic Zsh config
                cat > "$HOME/.zshrc" << 'EOF'
# Zsh Configuration

# Path
export PATH="$HOME/.local/bin:$PATH"

# Starship prompt
eval "$(starship init zsh)"

# Zsh plugins
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# fzf
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

# zoxide
eval "$(zoxide init zsh)"

# Aliases
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first"
alias lt="eza --tree --icons --level=2"
alias cat="bat"
alias find="fd"
alias grep="rg"
alias top="btop"
alias lg="lazygit"

# fnm (if installed)
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd)"
fi

# SSH key switcher
set-ssh-key() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: set-ssh-key [key-name]"
        echo ""
        echo "Available keys:"
        ls -1 ~/.ssh/id_* 2>/dev/null | xargs -I {} basename {} | sed 's/\..*$//' || echo "  (none)"
        return 1
    fi
    
    local key_name="$1"
    local key_path="$HOME/.ssh/$key_name"
    
    if [[ ! -f "$key_path" ]]; then
        echo "Key not found: $key_path"
        return 1
    fi
    
    # Clear SSH agent
    ssh-add -D
    
    # Add the key
    ssh-add "$key_path"
    
    echo "SSH key set to: $key_name"
}
EOF
            fi
            log_success "Zsh config deployed"
        fi
    fi
}

# Configure git for delta
configure_git() {
    if ask_confirm "Configure git to use delta as pager?"; then
        if has_cmd delta || [[ -f "$INSTALLED_PACKAGES_FILE" && grep -q "delta" "$INSTALLED_PACKAGES_FILE" ]]; then
            git config --global core.pager delta
            git config --global interactive.diffFilter "delta --color-only"
            git config --global delta.navigate true
            git config --global delta.dark true
            git config --global delta.line-numbers true
            git config --global delta.side-by-side true
            git config --global merge.conflictstyle diff3
            git config --global diff.colorMoved default
            log_success "git-delta configured"
        else
            log_warn "git-delta is not installed, skipping git configuration"
        fi
    fi
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    # Parse arguments
    if [[ $# -gt 0 ]]; then
        case "$1" in
            uninstall)
                uninstall_all
                exit 0
                ;;
            status)
                show_status
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    fi
    
    # Welcome message
    echo ""
    echo -e "${BOLD}${CYAN}==========================================================="
    echo -e "  Terminal Setup Script - Interactive Configuration"
    echo -e "===========================================================${NC}"
    echo ""
    echo "This script will help you configure a modern terminal environment."
    echo "You will be asked to confirm each step (y/N)."
    echo "All changes can be rolled back with: ${BOLD}./setup.sh uninstall${NC}"
    echo ""
    
    # Detect OS
    OS="$(detect_os)"
    case "$OS" in
        macos)
            log_info "Detected macOS"
            ;;
        debian)
            log_info "Detected Debian/Ubuntu Linux"
            ;;
        wsl)
            log_info "Detected Windows WSL"
            ;;
        windows-native)
            log_error "Native Windows (MINGW/MSYS/Cygwin) is not supported."
            echo "Please install WSL: https://learn.microsoft.com/en-us/windows/wsl/install"
            echo "Then run this script inside WSL."
            exit 1
            ;;
        *)
            log_error "Unsupported OS: $(uname -s)"
            echo "This script supports macOS, Debian/Ubuntu, and Windows WSL."
            exit 1
            ;;
    esac
    
    # Initialize state
    init_state
    
    # Record OS and timestamp
    echo "$OS" > "$STATE_DIR/os.txt"
    echo "$(date -Iseconds)" > "$STATE_DIR/installed_at.txt"
    
    # Step 1: Package Manager
    log_header "Step 1: Package Manager"
    
    case "$OS" in
        macos)
            install_homebrew
            ;;
        debian|wsl)
            install_basic_tools
            ;;
    esac
    
    # Step 2: Terminal Emulator
    install_terminal
    
    # Step 3: Nerd Font
    install_nerd_font
    
    # Step 4: Shell
    install_shell
    
    # Step 5: Starship Prompt
    install_starship
    
    # Step 6: CLI Tools
    install_cli_tools
    
    # Step 7: fnm + Node.js
    install_fnm
    
    # Step 8: Zellij
    install_zellij
    
    # Step 9: Deploy Shell Configuration
    deploy_shell_config
    
    # Step 10: Configure git
    configure_git
    
    # Final summary
    echo ""
    echo -e "${BOLD}${GREEN}==========================================================="
    echo -e "  ✅ Installation Complete!"
    echo -e "===========================================================${NC}"
    echo ""
    echo "  What was installed:"
    if [[ -f "$STATE_DIR/shell.txt" ]]; then
        local shell
        shell="$(cat "$STATE_DIR/shell.txt")"
        if [[ "$shell" != "skip" ]]; then
            echo "    - Shell: $shell"
        fi
    fi
    echo "    - Starship: $(has_cmd starship && echo 'Yes' || echo 'No')"
    echo "    - CLI Tools: See $INSTALLED_PACKAGES_FILE"
    echo ""
    echo "  State saved to: $STATE_DIR"
    echo "  Backups saved to: $BACKUP_DIR"
    echo ""
    echo "  Next steps:"
    echo "    1. Restart your terminal"
    echo "    2. To rollback: ${BOLD}./setup.sh uninstall${NC}"
    echo "    3. To check status: ${BOLD}./setup.sh status${NC}"
    echo ""
    
    # Save state summary
    cat > "$STATE_DIR/summary.txt" << EOF
Terminal Setup Installation Summary
==================================
Date: $(date -Iseconds)
OS: $OS

Installed Packages:
EOF
    if [[ -f "$INSTALLED_PACKAGES_FILE" ]]; then
        cat "$INSTALLED_PACKAGES_FILE" >> "$STATE_DIR/summary.txt"
    fi
    
    echo -e "${GREEN}Done!${NC}"
}

# Run main function
main "$@"
