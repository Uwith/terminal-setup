# Terminal Setup

> A modern, user-friendly terminal environment configuration script with **opt-in interactive installation**, **complete state tracking**, and **one-command uninstall/rollback capability**.

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Other Languages:** [简体中文](../README.md)

## Features

### Core Advantages Over Traditional Scripts

| Feature | This Project | Traditional Scripts (e.g., lewislulu/terminal-setup) |
|---------|-------------|--------------------------------------------|
| **Installation Mode** | Opt-in (user chooses each component) | Opt-out (installs everything by default) |
| **Rollback Capability** | Full uninstall with config restoration | Partial backup only, no package removal |
| **State Tracking** | Records all installed packages | No tracking of installed packages |
| **Config Backup** | Timestamped backups of all modified files | Backs up but no centralized management |
| **User Control** | Confirm each step with [y/N] | Most steps run automatically |

### Pain Points Solved

1. **No More "Full House" Installation**
   - Traditional scripts install dozens of tools without asking
   - This script asks for confirmation before installing **each component**
   - You can install just Fish shell without any CLI tools, or vice versa

2. **Complete Rollback Mechanism**
   - All modified config files are backed up with timestamps
   - All installed packages (brew/apt/curl) are recorded
   - `./setup.sh uninstall` automatically:
     - Restores all backup config files
     - Uninstalls all recorded packages
     - Cleans up the state directory

3. **Transparent State Management**
   - All installation data saved to `~/.terminal-setup/`
   - `./setup.sh status` shows exactly what was installed
   - Easy to audit and manage

4. **Cross-Platform Intelligence**
   - Auto-detects macOS (uses Homebrew)
   - Auto-detects Debian/Ubuntu (uses apt)
   - Handles WSL special cases
   - Provides platform-specific installation methods

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Uwith/terminal-setup.git
cd terminal-setup

# Run interactive installation
./setup.sh

# Or run directly (curl pipe)
bash <(curl -fsSL https://raw.githubusercontent.com/Uwith/terminal-setup/main/setup.sh)
```

## Usage

### Interactive Installation

```bash
./setup.sh
```

This starts an interactive process where you'll be asked to confirm each component:

```
===========================================================
  Terminal Setup Script - Interactive Configuration
===========================================================

This script will help you configure a modern terminal environment.
You will be asked to confirm each step (y/N).
All changes can be rolled back with: ./setup.sh uninstall

[INFO] Detected macOS

=== Step 1: Package Manager ===
? Install Homebrew? [y/N]

=== Step 2: Terminal Emulator ===
? Install Ghostty terminal emulator? [y/N]

=== Step 3: Nerd Font ===
? Install MesloLGS NF nerd fonts? [y/N]

=== Step 4: Shell Setup ===
  Please choose your shell:
  1) Fish - Modern shell, amazing defaults, not POSIX
  2) Zsh  - POSIX-compatible, fish-like with plugins
  3) Skip shell installation

Choose [1/2/3, default: 3]: 1
? Install Fish Shell? [y/N]
? Set Fish as default shell? [y/N]
...
```

### One-Command Uninstall

```bash
./setup.sh uninstall
```

This will:
1. Restore all backup configuration files (`.bashrc`, `.zshrc`, `config.fish`, etc.)
2. Uninstall all packages installed by the script (Homebrew, apt, manually installed)
3. Clean up the state directory
4. Display a summary of what was removed

### Check Installation Status

```bash
./setup.sh status
```

Shows:
- State directory location
- List of all backup files
- All installed packages
- Installation timestamp

### Show Help

```bash
./setup.sh --help
./setup.sh -h
```

## Available Components

All components are **optional** and will only be installed if you confirm:

### Terminal Emulator
- **Ghostty** (macOS) - GPU-accelerated terminal emulator
- For Linux: Manual installation instructions provided
- For WSL: Runs on Windows side, use Windows Terminal

### Shell
- **Fish** - Modern shell with built-in autosuggestions and syntax highlighting
- **Zsh** - POSIX-compatible with fish-like plugins (autosuggestions, syntax-highlighting)

### Shell Prompt
- **Starship** - Cross-shell prompt with Catppuccin Mocha theme

### Nerd Fonts
- **MesloLGS NF** - Nerd Font for icons and powerline glyphs

### Modern CLI Tools
- **bat** - `cat` with syntax highlighting and line numbers
- **eza** - `ls` with icons, git status, tree view
- **fd** - Fast and user-friendly `find` replacement
- **ripgrep (rg)** - Fast grep alternative
- **btop** - Beautiful system monitor
- **zoxide** - Smart `cd` that learns your habits
- **jq** - JSON processor
- **tldr** - Simplified man pages with examples
- **fzf** - Fuzzy finder
- **git-delta** - Beautiful git diffs with syntax highlighting
- **lazygit** - Git TUI

### Version Managers
- **fnm** - Fast Node Manager (Rust-based, ~1ms shell startup)

### Terminal Multiplexer
- **Zellij** - Modern terminal multiplexer (like tmux, but better UX)

### Configuration Files
- Shell configurations (`.zshrc`, `config.fish`)
- Starship configuration (`starship.toml`)
- Custom functions (set-ssh-key)
- Git configuration for delta

## Architecture

### State Directory Structure

```
~/.terminal-setup/
├── backups/              # All backup config files with timestamps
│   ├── .zshrc.1719000000.bak
│   ├── config.fish.1719000001.bak
│   └── starship.toml.1719000002.bak
├── installed_packages.txt  # List of all installed packages
├── os.txt                 # Detected OS
├── installed_at.txt       # Installation timestamp
├── shell.txt             # Selected shell type
└── state.json            # Structured state information
```

### Package Tracking Format

Each installed package is recorded in `installed_packages.txt` with its installation method:

```
brew:fish
brew:starship
brew:bat
apt:zsh-autosuggestions
curl:fnm
bundled:eza
symlink:bat
```

This allows the uninstall command to know exactly how each package was installed and how to remove it.

## Platform Support

| Platform | Status | Package Manager | Notes |
|----------|--------|----------------|-------|
| **macOS** | Fully Supported | Homebrew | Primary target |
| **Debian/Ubuntu** | Fully Supported | apt | All tools available |
| **WSL** | Fully Supported | apt | Windows Subsystem for Linux |
| **Windows (native)** | Not Supported | - | Use WSL instead |

## Comparison with lewislulu/terminal-setup

### What This Project Improves

1. **User Choice**
   - **Before**: `./setup.sh --fish` installs Ghostty, Fish, all CLI tools, Starship, fonts, etc.
   - **After**: You're asked for **each component** individually

2. **Rollback Capability**
   - **Before**: Backs up config files, but no way to uninstall packages
   - **After**: `./setup.sh uninstall` removes packages AND restores configs

3. **State Visibility**
   - **Before**: No centralized state, hard to know what was installed
   - **After**: `./setup.sh status` shows complete installation state

4. **Safety**
   - **Before**: Script makes changes without explicit confirmation
   - **After**: Every change requires explicit user confirmation [y/N]

### Tools Inherited from Original Project

This project maintains compatibility with the excellent tool selection from lewislulu/terminal-setup:
- Same modern CLI tools (bat, eza, fd, rg, etc.)
- Same shell options (Fish, Zsh)
- Same prompt (Starship)
- Same fonts (MesloLGS NF)
- Same extras (fnm, Zellij)

### New Features Added

1. **Interactive Opt-in** - Every component requires explicit confirmation
2. **Package Tracking** - Records how each package was installed
3. **Full Uninstall** - Removes packages and restores configs
4. **State Management** - Centralized tracking of all changes
5. **Status Command** - View installation state at any time
6. **Better Error Handling** - Uses `set -euo pipefail` for robustness

## Shell Configuration

### Fish Shell

If you install Fish, the following will be configured:

```fish
# Starship prompt
starship init fish | source

# Abbreviations
abbr -a ls "eza --icons --group-directories-first"
abbr -a ll "eza -la --icons --group-directories-first"
abbr -a cat "bat"
abbr -a find "fd"
abbr -a grep "rg"

# zoxide
zoxide init fish | source

# fzf
fzf --fish | source

# Custom function
set-ssh-key [key-name]  # Switch SSH keys
```

### Zsh

If you install Zsh, the following will be configured:

```zsh
# Starship prompt
eval "$(starship init zsh)"

# Plugins
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# fzf
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh

# zoxide
eval "$(zoxide init zsh)"

# Aliases
alias ls="eza --icons --group-directories-first"
alias cat="bat"
alias find="fd"
alias grep="rg"

# Custom function
set-ssh-key [key-name]  # Switch SSH keys
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

### Development

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Test the script on multiple platforms
5. Commit your changes (`git commit -m 'feat: your feature'`)
6. Push to the branch (`git push origin feature/your-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [lewislulu/terminal-setup](https://github.com/lewislulu/terminal-setup)
- Thanks to all the developers of the amazing CLI tools included in this setup
- Special thanks to the Homebrew, Fish Shell, and Zsh communities

## Support

If you encounter any issues or have questions, please open an issue on GitHub.

---

**Enjoy your modern terminal experience!**
