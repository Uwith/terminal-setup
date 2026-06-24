#!/bin/bash
#
# server-mgmt.sh — 服务器配置管理统一脚本
#
# 功能特性:
#   - 交互式选择安装 (opt-in)
#   - 完整状态追踪和备份系统
#   - 一键卸载/回滚能力
#   - 包更新管理
#   - 安装列表展示
#
# 平台支持: macOS (Homebrew), Debian/Ubuntu (apt), Windows WSL
# Shell支持: Fish, Zsh, Bash
#
# 使用方法:
#   ./server-mgmt.sh              # 交互式安装
#   ./server-mgmt.sh install      # 交互式安装
#   ./server-mgmt.sh uninstall    # 回滚所有更改
#   ./server-mgmt.sh update       # 更新所有已安装包
#   ./server-mgmt.sh update <pkg> # 更新指定包
#   ./server-mgmt.sh list         # 展示安装列表
#   ./server-mgmt.sh status       # 显示安装状态
#   ./server-mgmt.sh check-update # 检查可用更新
#
# 作者: Uwith + Mistral Vibe
# 许可证: MIT

set -euo pipefail

# =============================================================================
# 配置 & 状态
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# 状态目录用于备份和追踪
STATE_DIR="$HOME/.server-mgmt"
BACKUP_DIR="$STATE_DIR/backups"
STATE_FILE="$STATE_DIR/state.json"
INSTALLED_PACKAGES_FILE="$STATE_DIR/installed_packages.txt"
MODULES_FILE="$STATE_DIR/modules.txt"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 从 setup.sh 复用必要的函数和变量
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
                echo "linux"
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

has_cmd() {
    command -v "$1" &>/dev/null
}

# =============================================================================
# 主命令分发
# =============================================================================

show_help() {
    echo ""
    echo "Usage: $SCRIPT_NAME [OPTION|COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install              Interactive installation"
    echo "  uninstall            Rollback all changes and uninstall"
    echo "  uninstall <pkg>      Uninstall specific package"
    echo "  update               Update all installed packages"
    echo "  update <pkg>         Update specific package"
    echo "  list                 Show detailed installed packages list"
    echo "  status               Show installation status"
    echo "  check-update         Check for available updates"
    echo "  --help, -h           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME"
    echo "  $SCRIPT_NAME install"
    echo "  $SCRIPT_NAME update"
    echo "  $SCRIPT_NAME update fish"
    echo "  $SCRIPT_NAME uninstall zsh"
    echo "  $SCRIPT_NAME list"
    echo "  $SCRIPT_NAME status"
    echo "  $SCRIPT_NAME check-update"
    echo ""
}

# 检查依赖
check_dependencies() {
    if ! command -v jq &>/dev/null; then
        echo "jq is required but not installed. Installing jq..."
        case "$(uname -s)" in
            Darwin) brew install jq 2>/dev/null || echo "Please install jq: brew install jq" ;;
            Linux)  sudo apt-get install -y jq 2>/dev/null || echo "Please install jq: sudo apt-get install -y jq" ;;
        esac
    fi
}

# 更新功能
update_all() {
    local OS
    OS="$(detect_os 2>/dev/null || echo "")"
    
    echo ""
    echo -e "${BOLD}${CYAN}Updating all installed packages...${NC}"
    echo ""
    
    if [[ ! -f "$INSTALLED_PACKAGES_FILE" ]]; then
        echo "No installed packages found."
        echo "Run 'install' first to install packages."
        return 0
    fi
    
    local updated=0
    local errors=0
    local skipped=0
    
    # 先更新包管理器本身
    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                echo -e "${BLUE}[INFO] Updating Homebrew...${NC}"
                if brew update 2>/dev/null; then
                    echo -e "${GREEN}[OK] Homebrew updated${NC}"
                    updated=$((updated + 1))
                else
                    echo -e "${YELLOW}[WARN] Failed to update Homebrew${NC}"
                    errors=$((errors + 1))
                fi
                
                echo -e "${BLUE}[INFO] Upgrading Homebrew packages...${NC}"
                if brew upgrade 2>/dev/null; then
                    echo -e "${GREEN}[OK] Homebrew packages updated${NC}"
                    updated=$((updated + 1))
                else
                    echo -e "${YELLOW}[WARN] No Homebrew packages to update or update failed${NC}"
                fi
            fi
            ;;
        debian|wsl|linux)
            if command -v apt-get &>/dev/null; then
                echo -e "${BLUE}[INFO] Updating apt package lists...${NC}"
                if sudo apt-get update -y 2>/dev/null; then
                    echo -e "${GREEN}[OK] Package lists updated${NC}"
                    updated=$((updated + 1))
                else
                    echo -e "${YELLOW}[WARN] Failed to update package lists${NC}"
                    errors=$((errors + 1))
                fi
                
                echo -e "${BLUE}[INFO] Upgrading installed apt packages...${NC}"
                if sudo apt-get upgrade -y 2>/dev/null; then
                    echo -e "${GREEN}[OK] apt packages updated${NC}"
                    updated=$((updated + 1))
                else
                    echo -e "${YELLOW}[WARN] No apt packages to update or update failed${NC}"
                fi
            fi
            ;;
    esac
    
    # 更新单个包
    echo ""
    echo -e "${BLUE}[INFO] Updating individual packages...${NC}"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | xargs)"
        [[ -z "$line" ]] && continue
        
        local pkg_manager
        local pkg_name
        pkg_manager="$(echo "$line" | cut -d':' -f1)"
        pkg_name="$(echo "$line" | cut -d':' -f2-)"
        
        case "$pkg_manager" in
            brew)
                if command -v brew &>/dev/null && brew list "$pkg_name" &>/dev/null; then
                    echo -e "${BLUE}[INFO] Updating $pkg_name (Homebrew)...${NC}"
                    if brew upgrade "$pkg_name" 2>/dev/null; then
                        echo -e "${GREEN}[OK] Updated: $pkg_name${NC}"
                        updated=$((updated + 1))
                    else
                        echo -e "${YELLOW}[WARN] No update available for: $pkg_name${NC}"
                        skipped=$((skipped + 1))
                    fi
                fi
                ;;
            brew-cask)
                if command -v brew &>/dev/null && brew list --cask "$pkg_name" &>/dev/null; then
                    echo -e "${BLUE}[INFO] Updating $pkg_name (Homebrew Cask)...${NC}"
                    if brew upgrade --cask "$pkg_name" 2>/dev/null; then
                        echo -e "${GREEN}[OK] Updated: $pkg_name${NC}"
                        updated=$((updated + 1))
                    else
                        echo -e "${YELLOW}[WARN] No update available for: $pkg_name${NC}"
                        skipped=$((skipped + 1))
                    fi
                fi
                ;;
            apt)
                if command -v apt-get &>/dev/null && dpkg -s "$pkg_name" &>/dev/null 2>&1; then
                    echo -e "${BLUE}[INFO] Updating $pkg_name (apt)...${NC}"
                    if sudo apt-get install --only-upgrade -y "$pkg_name" 2>/dev/null; then
                        echo -e "${GREEN}[OK] Updated: $pkg_name${NC}"
                        updated=$((updated + 1))
                    else
                        echo -e "${YELLOW}[WARN] No update available for: $pkg_name${NC}"
                        skipped=$((skipped + 1))
                    fi
                fi
                ;;
            curl|bundled|symlink|snap|script)
                echo -e "${YELLOW}[WARN] Manual update required for $pkg_manager packages: $pkg_name${NC}"
                skipped=$((skipped + 1))
                ;;
            *)
                errors=$((errors + 1))
                echo -e "${RED}[ERROR] Unknown package manager: $pkg_manager for $pkg_name${NC}"
                ;;
        esac
    done < "$INSTALLED_PACKAGES_FILE"
    
    echo ""
    echo -e "${GREEN}Update complete!${NC}"
    echo -e "${BLUE}[INFO] Updated: $updated | Skipped: $skipped | Errors: $errors${NC}"
}

update_package() {
    local target_pkg="$1"
    
    if [[ -z "$target_pkg" ]]; then
        echo "Usage: $SCRIPT_NAME update <package>"
        echo "To update all packages, use: $SCRIPT_NAME update"
        return 1
    fi
    
    echo ""
    echo -e "${BOLD}${CYAN}Updating specific package: $target_pkg${NC}"
    echo ""
    
    if [[ ! -f "$INSTALLED_PACKAGES_FILE" ]]; then
        echo "No installed packages found."
        return 1
    fi
    
    local found=false
    local updated=false
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | xargs)"
        [[ -z "$line" ]] && continue
        
        local pkg_manager
        local pkg_name
        pkg_manager="$(echo "$line" | cut -d':' -f1)"
        pkg_name="$(echo "$line" | cut -d':' -f2-)"
        
        # 匹配包名（支持模糊匹配）
        if [[ "$pkg_name" == "$target_pkg" ]] || [[ "$pkg_name" == *"$target_pkg"* ]] || [[ "$target_pkg" == *"$pkg_name"* ]]; then
            found=true
            echo -e "${BLUE}[INFO] Found package: $pkg_name (via $pkg_manager)${NC}"
            
            case "$pkg_manager" in
                brew)
                    if command -v brew &>/dev/null && brew list "$pkg_name" &>/dev/null; then
                        echo -e "${BLUE}[INFO] Updating $pkg_name via Homebrew...${NC}"
                        if brew upgrade "$pkg_name" 2>/dev/null; then
                            echo -e "${GREEN}[OK] Updated: $pkg_name${NC}"
                            updated=true
                        else
                            echo -e "${YELLOW}[WARN] No update available or failed to update: $pkg_name${NC}"
                        fi
                    fi
                    ;;
                brew-cask)
                    if command -v brew &>/dev/null && brew list --cask "$pkg_name" &>/dev/null; then
                        echo -e "${BLUE}[INFO] Updating $pkg_name via Homebrew Cask...${NC}"
                        if brew upgrade --cask "$pkg_name" 2>/dev/null; then
                            echo -e "${GREEN}[OK] Updated: $pkg_name${NC}"
                            updated=true
                        else
                            echo -e "${YELLOW}[WARN] No update available or failed to update: $pkg_name${NC}"
                        fi
                    fi
                    ;;
                apt)
                    if command -v apt-get &>/dev/null && dpkg -s "$pkg_name" &>/dev/null 2>&1; then
                        echo -e "${BLUE}[INFO] Updating $pkg_name via apt...${NC}"
                        if sudo apt-get install --only-upgrade -y "$pkg_name" 2>/dev/null; then
                            echo -e "${GREEN}[OK] Updated: $pkg_name${NC}"
                            updated=true
                        else
                            echo -e "${YELLOW}[WARN] No update available or failed to update: $pkg_name${NC}"
                        fi
                    fi
                    ;;
                curl|bundled|symlink|snap|script)
                    echo -e "${YELLOW}[WARN] Manual update required for $pkg_manager packages: $pkg_name${NC}"
                    ;;
                *)
                    echo -e "${RED}[ERROR] Unknown package manager: $pkg_manager${NC}"
                    ;;
            esac
        fi
    done < "$INSTALLED_PACKAGES_FILE"
    
    if [[ "$found" == false ]]; then
        echo -e "${RED}[ERROR] Package '$target_pkg' not found in installed packages${NC}"
        echo -e "${BLUE}[INFO] Try: $SCRIPT_NAME list to see all installed packages${NC}"
        return 1
    fi
    
    if [[ "$updated" == true ]]; then
        echo -e "${GREEN}Package update complete${NC}"
    else
        echo -e "${YELLOW}[INFO] No updates were made (packages may already be up to date)${NC}"
    fi
}

# 检查可用更新
check_updates() {
    local OS
    OS="$(detect_os 2>/dev/null || echo "")"
    
    echo ""
    echo -e "${BOLD}${CYAN}Checking for available updates...${NC}"
    echo ""
    
    local updates_available=0
    local total_checked=0
    
    if [[ ! -f "$INSTALLED_PACKAGES_FILE" ]]; then
        echo "No installed packages found."
        return 0
    fi
    
    # 检查包管理器更新
    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                echo -e "${BLUE}[INFO] Checking Homebrew updates...${NC}"
                if brew outdated 2>/dev/null | grep -q .; then
                    echo ""
                    echo "  Homebrew packages with updates available:"
                    brew outdated 2>/dev/null | sed 's/^/    /'
                    updates_available=$((updates_available + 1))
                fi
                total_checked=$((total_checked + 1))
            fi
            ;;
        debian|wsl|linux)
            if command -v apt-get &>/dev/null; then
                echo -e "${BLUE}[INFO] Checking apt updates...${NC}"
                local apt_output
                apt_output=$(sudo apt-get --dry-run upgrade 2>/dev/null)
                local apt_updates
                apt_updates=$(echo "$apt_output" | grep -c "^Inst " || true)
                if [[ "$apt_updates" -gt 0 ]]; then
                    echo ""
                    echo "  apt packages with updates available: $apt_updates"
                    updates_available=$((updates_available + apt_updates))
                fi
                total_checked=$((total_checked + 1))
            fi
            ;;
    esac
    
    # 检查单个包
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | xargs)"
        [[ -z "$line" ]] && continue
        
        local pkg_manager
        local pkg_name
        pkg_manager="$(echo "$line" | cut -d':' -f1)"
        pkg_name="$(echo "$line" | cut -d':' -f2-)"
        
        case "$pkg_manager" in
            brew)
                if command -v brew &>/dev/null && brew list "$pkg_name" &>/dev/null; then
                    if brew outdated "$pkg_name" &>/dev/null | grep -q "$pkg_name"; then
                        echo "  - $pkg_name (Homebrew) has updates"
                        updates_available=$((updates_available + 1))
                    fi
                fi
                ;;
            brew-cask)
                if command -v brew &>/dev/null && brew list --cask "$pkg_name" &>/dev/null; then
                    if brew outdated --cask "$pkg_name" &>/dev/null | grep -q "$pkg_name"; then
                        echo "  - $pkg_name (Homebrew Cask) has updates"
                        updates_available=$((updates_available + 1))
                    fi
                fi
                ;;
        esac
    done < "$INSTALLED_PACKAGES_FILE"
    
    echo ""
    if [[ "$updates_available" -gt 0 ]]; then
        echo -e "${GREEN}Updates available: $updates_available${NC}"
        echo -e "${BLUE}[INFO] Run '$SCRIPT_NAME update' to install all updates${NC}"
    else
        echo -e "${GREEN}All packages are up to date!${NC}"
    fi
}

# 展示安装列表
list_packages() {
    echo ""
    echo -e "${BOLD}${CYAN}Installed Packages List${NC}"
    echo ""
    
    if [[ ! -f "$INSTALLED_PACKAGES_FILE" ]]; then
        echo "  No packages installed"
        echo ""
        echo -e "${BLUE}[INFO] Run 'install' to install packages first${NC}"
        return 0
    fi
    
    local total=0
    
    # 按包管理器分组
    declare -A manager_counts=()
    declare -A manager_packages=()
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | xargs)"
        [[ -z "$line" ]] && continue
        
        local pkg_manager
        local pkg_name
        pkg_manager="$(echo "$line" | cut -d':' -f1)"
        pkg_name="$(echo "$line" | cut -d':' -f2-)"
        
        manager_counts["$pkg_manager"]=$((manager_counts["$pkg_manager"] + 1))
        manager_packages["$pkg_manager"]+="$pkg_name "
        total=$((total + 1))
    done < "$INSTALLED_PACKAGES_FILE"
    
    echo -e "${BLUE}[INFO] Total installed packages: $total${NC}"
    echo ""
    
    # 展示各包管理器的包
    for manager in "${!manager_counts[@]}"; do
        local count=${manager_counts["$manager"]}
        local pkgs=${manager_packages["$manager"]}
        
        case "$manager" in
            brew)        echo -e "  ${BOLD}Homebrew Packages ($count):${NC}" ;;
            brew-cask)   echo -e "  ${BOLD}Homebrew Cask ($count):${NC}" ;;
            apt)          echo -e "  ${BOLD}apt Packages ($count):${NC}" ;;
            curl)         echo -e "  ${BOLD}Curl-installed ($count):${NC}" ;;
            bundled)      echo -e "  ${BOLD}Bundled Binaries ($count):${NC}" ;;
            symlink)      echo -e "  ${BOLD}Symlinked Packages ($count):${NC}" ;;
            snap)         echo -e "  ${BOLD}Snap Packages ($count):${NC}" ;;
            script)       echo -e "  ${BOLD}Script-installed ($count):${NC}" ;;
            *)            echo -e "  ${BOLD}${manager} Packages ($count):${NC}" ;;
        esac
        
        for pkg in $pkgs; do
            echo "    - $pkg"
        done
        echo ""
    done
    
    # 按类别展示
    echo -e "  ${BOLD}By Category:${NC}"
    echo ""
    
    # 定义类别
    local terminal_pkgs=("ghostty" "kitty" "alacritty")
    local shell_pkgs=("fish" "zsh" "bash")
    local prompt_pkgs=("starship")
    local font_pkgs=("nerd-fonts" "meslo")
    local cli_tools=("bat" "eza" "fd" "ripgrep" "btop" "zoxide" "jq" "tldr" "fzf" "git-delta" "lazygit")
    local version_managers=("fnm" "nvm")
    local multiplexers=("zellij" "tmux" "screen")
    
    local category_count=0
    
    for category in "Terminal Emulators" "Shells" "Prompts" "Fonts" "CLI Tools" "Version Managers" "Terminal Multiplexers"; do
        local pkg_list=()
        case "$category" in
            "Terminal Emulators") pkg_list=("${terminal_pkgs[@]}") ;;
            "Shells")            pkg_list=("${shell_pkgs[@]}") ;;
            "Prompts")           pkg_list=("${prompt_pkgs[@]}") ;;
            "Fonts")             pkg_list=("${font_pkgs[@]}") ;;
            "CLI Tools")        pkg_list=("${cli_tools[@]}") ;;
            "Version Managers") pkg_list=("${version_managers[@]}") ;;
            "Terminal Multiplexers") pkg_list=("${multiplexers[@]}") ;;
        esac
        
        echo -e "    ${BOLD}${category}:${NC}"
        local found_in_category=false
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="$(echo "$line" | xargs)"
            [[ -z "$line" ]] && continue
            
            local pkg_name
            pkg_name="$(echo "$line" | cut -d':' -f2-)"
            
            for pkg in "${pkg_list[@]}"; do
                if [[ "$pkg_name" == "$pkg" ]] || [[ "$pkg_name" == *"$pkg"* ]]; then
                    echo "      - $pkg_name"
                    found_in_category=true
                    break
                fi
            done
        done < "$INSTALLED_PACKAGES_FILE"
        
        if [[ "$found_in_category" == false ]]; then
            echo "      (none)"
        fi
    done
    
    echo ""
}

# 展示详细状态
show_status() {
    echo ""
    echo -e "${BOLD}${CYAN}Installation Status${NC}"
    echo ""
    
    if [[ ! -d "$STATE_DIR" ]]; then
        echo "  No installation found"
        echo ""
        echo -e "${BLUE}[INFO] To install, run: $SCRIPT_NAME install${NC}"
        return 0
    fi
    
    echo "  State directory: $STATE_DIR"
    echo "  Backups: $BACKUP_DIR"
    
    # 展示状态文件信息
    if [[ -f "$STATE_DIR/os.txt" ]]; then
        echo ""
        echo -e "  ${BOLD}Installation metadata:${NC}"
        local os_info
        os_info=$(cat "$STATE_DIR/os.txt" 2>/dev/null || echo "unknown")
        local installed_at
        installed_at=$(cat "$STATE_DIR/installed_at.txt" 2>/dev/null || echo "unknown")
        
        echo "    OS: $os_info"
        echo "    Installed: $installed_at"
    fi
    
    # 展示备份文件
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_count
        backup_count=$(find "$BACKUP_DIR" -name "*.bak" 2>/dev/null | wc -l)
        echo ""
        echo -e "  ${BOLD}Backups: ${backup_count} files${NC}"
        
        if [[ ${backup_count} -gt 0 ]]; then
            echo "  Backup files:"
            find "$BACKUP_DIR" -name "*.bak" 2>/dev/null | while read -r backup; do
                local filename
                filename=$(basename "$backup")
                echo "    - $filename"
            done
        fi
    fi
    
    # 展示已安装的包
    if [[ -f "$INSTALLED_PACKAGES_FILE" ]]; then
        local count
        count=$(wc -l < "$INSTALLED_PACKAGES_FILE" | tr -d ' ')
        echo ""
        echo -e "  ${BOLD}Installed packages: $count${NC}"
        
        if [[ $count -gt 0 ]]; then
            echo ""
            echo "  Package list:"
            local brew_count=0
            local apt_count=0
            local other_count=0
            
            while IFS= read -r line || [[ -n "$line" ]]; do
                line="$(echo "$line" | xargs)"
                [[ -z "$line" ]] && continue
                
                local pkg_manager
                pkg_manager="$(echo "$line" | cut -d':' -f1)"
                
                case "$pkg_manager" in
                    brew|brew-cask) brew_count=$((brew_count + 1)) ;;
                    apt)             apt_count=$((apt_count + 1)) ;;
                    *)               other_count=$((other_count + 1)) ;;
                esac
            done < "$INSTALLED_PACKAGES_FILE"
            
            echo "    - Homebrew: $brew_count packages"
            echo "    - apt: $apt_count packages"
            echo "    - Other: $other_count packages"
        fi
    fi
    
    echo ""
    echo -e "${BLUE}[INFO] Run '$SCRIPT_NAME list' for detailed package information${NC}"
    echo -e "${BLUE}[INFO] Run '$SCRIPT_NAME check-update' to check for available updates${NC}"
}

# 卸载指定包
uninstall_package() {
    local target_pkg="$1"
    
    if [[ -z "$target_pkg" ]]; then
        echo "Usage: $SCRIPT_NAME uninstall <package>"
        echo "To uninstall all packages, use: $SCRIPT_NAME uninstall"
        return 1
    fi
    
    echo ""
    echo -e "${BOLD}${CYAN}Uninstalling specific package: $target_pkg${NC}"
    echo ""
    
    if [[ ! -f "$INSTALLED_PACKAGES_FILE" ]]; then
        echo "No installed packages found."
        return 0
    fi
    
    local found=false
    local uninstalled=false
    local new_packages_file="$STATE_DIR/installed_packages.tmp"
    touch "$new_packages_file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | xargs)"
        [[ -z "$line" ]] && continue
        
        local pkg_manager
        local pkg_name
        pkg_manager="$(echo "$line" | cut -d':' -f1)"
        pkg_name="$(echo "$line" | cut -d':' -f2-)"
        
        # 匹配包名
        if [[ "$pkg_name" == "$target_pkg" ]] || [[ "$pkg_name" == *"$target_pkg"* ]] || [[ "$target_pkg" == *"$pkg_name"* ]]; then
            found=true
            echo -e "${BLUE}[INFO] Found package: $pkg_name (via $pkg_manager)${NC}"
            
            case "$pkg_manager" in
                brew)
                    if command -v brew &>/dev/null && brew list "$pkg_name" &>/dev/null; then
                        echo -e "${BLUE}[INFO] Uninstalling $pkg_name via Homebrew...${NC}"
                        if brew uninstall "$pkg_name" 2>/dev/null; then
                            echo -e "${GREEN}[OK] Uninstalled: $pkg_name${NC}"
                            uninstalled=true
                        else
                            echo -e "${YELLOW}[WARN] Failed to uninstall: $pkg_name${NC}"
                            echo "$line" >> "$new_packages_file"
                            continue
                        fi
                    fi
                    ;;
                brew-cask)
                    if command -v brew &>/dev/null && brew list --cask "$pkg_name" &>/dev/null; then
                        echo -e "${BLUE}[INFO] Uninstalling $pkg_name via Homebrew Cask...${NC}"
                        if brew uninstall --cask "$pkg_name" 2>/dev/null; then
                            echo -e "${GREEN}[OK] Uninstalled: $pkg_name${NC}"
                            uninstalled=true
                        else
                            echo -e "${YELLOW}[WARN] Failed to uninstall: $pkg_name${NC}"
                            echo "$line" >> "$new_packages_file"
                            continue
                        fi
                    fi
                    ;;
                apt)
                    if command -v apt-get &>/dev/null && dpkg -s "$pkg_name" &>/dev/null 2>&1; then
                        echo -e "${BLUE}[INFO] Uninstalling $pkg_name via apt...${NC}"
                        if sudo apt-get remove -y "$pkg_name" 2>/dev/null; then
                            echo -e "${GREEN}[OK] Uninstalled: $pkg_name${NC}"
                            uninstalled=true
                        else
                            echo -e "${YELLOW}[WARN] Failed to uninstall: $pkg_name${NC}"
                            echo "$line" >> "$new_packages_file"
                            continue
                        fi
                    fi
                    ;;
                curl)
                    echo -e "${BLUE}[INFO] Removing manually installed: $pkg_name${NC}"
                    if sudo rm -f "/usr/local/bin/$pkg_name" 2>/dev/null; then
                        echo -e "${GREEN}[OK] Removed: $pkg_name${NC}"
                        uninstalled=true
                    else
                        echo -e "${YELLOW}[WARN] Failed to remove: $pkg_name${NC}"
                        echo "$line" >> "$new_packages_file"
                        continue
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}[WARN] Cannot uninstall $pkg_manager packages: $pkg_name${NC}"
                    echo "$line" >> "$new_packages_file"
                    continue
                    ;;
            esac
            
            echo -e "${BLUE}[INFO] $pkg_name removed from package records${NC}"
        else
            echo "$line" >> "$new_packages_file"
        fi
    done < "$INSTALLED_PACKAGES_FILE"
    
    # 替换包文件
    if [[ -f "$new_packages_file" ]]; then
        mv "$new_packages_file" "$INSTALLED_PACKAGES_FILE"
    fi
    
    if [[ "$found" == false ]]; then
        echo -e "${RED}[ERROR] Package '$target_pkg' not found in installed packages${NC}"
        echo -e "${BLUE}[INFO] Try: $SCRIPT_NAME list to see all installed packages${NC}"
        return 1
    fi
    
    if [[ "$uninstalled" == true ]]; then
        echo -e "${GREEN}Package uninstall complete${NC}"
    else
        echo -e "${YELLOW}[INFO] No packages were uninstalled${NC}"
    fi
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    # 检查依赖
    check_dependencies
    
    # 如果有参数，处理命令
    if [[ $# -gt 0 ]]; then
        case "$1" in
            install)
                # 交互式安装
                echo ""
                echo -e "${BOLD}${CYAN}Starting interactive installation...${NC}"
                if [[ -f "$SCRIPT_DIR/setup.sh" ]]; then
                    # 使用现有的 setup.sh
                    bash "$SCRIPT_DIR/setup.sh" "${@:2}"
                else
                    echo "setup.sh not found, please use the original setup.sh"
                fi
                ;;
            uninstall)
                if [[ $# -gt 1 ]]; then
                    uninstall_package "$2"
                else
                    if [[ -f "$SCRIPT_DIR/setup.sh" ]]; then
                        bash "$SCRIPT_DIR/setup.sh" uninstall
                    else
                        echo "Uninstall functionality requires setup.sh"
                    fi
                fi
                ;;
            update)
                if [[ $# -gt 1 ]]; then
                    update_package "$2"
                else
                    update_all
                fi
                ;;
            list)
                list_packages
                ;;
            status)
                show_status
                ;;
            check-update)
                check_updates
                ;;
            --help|-h)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    else
        # 默认显示帮助
        show_help
    fi
}

# 运行 main 函数
main "$@"
