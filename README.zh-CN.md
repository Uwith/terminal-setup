# Terminal Setup

> 一个现代化、用户友好的终端环境配置脚本，具有 **交互式选择安装**、**完整状态追踪** 和 **一键卸载/回滚** 功能。

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 特性

### 相较于传统脚本的核心优势

| 功能 | 本项目 | 传统脚本 (如 lewislulu/terminal-setup) |
|------|--------|--------------------------------------|
| **安装模式** | 选择加入式 (用户选择每个组件) | 选择退出式 (默认安装所有内容) |
| **回滚能力** | 完全卸载并恢复配置 | 仅部分备份，不移除包 |
| **状态追踪** | 记录所有已安装的包 | 不追踪已安装的包 |
| **配置备份** | 所有修改文件的时间戳备份 | 备份但无集中管理 |
| **用户控制** | 每一步都需要确认 [y/N] | 大部分步骤自动运行 |

### 解决的痛点

1. **不再强制全家桶安装**
   - 传统脚本会在未经询问的情况下安装数十个工具
   - 本脚本在安装 **每个组件** 前都会询问确认
   - 你可以只安装 Fish shell 而不安装任何 CLI 工具，或者反之

2. **完整的回滚机制**
   - 所有修改的配置文件都会带有时间戳备份
   - 所有已安装的包 (brew/apt/curl) 都会被记录
   - `./setup.sh uninstall` 会自动:
     - 恢复所有备份的配置文件
     - 卸载所有已记录的包
     - 清理状态目录

3. **透明的状态管理**
   - 所有安装数据保存到 `~/.terminal-setup/`
   - `./setup.sh status` 显示确切的安装内容
   - 易于审计和管理

4. **跨平台智能**
   - 自动检测 macOS (使用 Homebrew)
   - 自动检测 Debian/Ubuntu (使用 apt)
   - 处理 WSL 特殊情况
   - 提供特定于平台的安装方法

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/Uwith/terminal-setup.git
cd terminal-setup

# 运行交互式安装
./setup.sh

# 或者直接运行 (curl 管道)
bash <(curl -fsSL https://raw.githubusercontent.com/Uwith/terminal-setup/main/setup.sh)
```

## 使用方法

### 交互式安装

```bash
./setup.sh
```

这将启动一个交互式流程，询问你确认每个组件:

```
===========================================================
  Terminal Setup Script - 交互式配置
===========================================================

此脚本将帮助你配置现代终端环境。
你将被要求确认每个步骤 (y/N)。
所有更改都可以通过以下命令回滚: ./setup.sh uninstall

[INFO] 检测到 macOS

=== 第1步: 包管理器 ===
? 是否安装 Homebrew? [y/N]

=== 第2步: 终端模拟器 ===
? 是否安装 Ghostty 终端模拟器? [y/N]

=== 第3步: Nerd 字体 ===
? 是否安装 MesloLGS NF nerd 字体? [y/N]

=== 第4步: Shell 设置 ===
  请选择你的 Shell:
  1) Fish - 现代 Shell，惊艳的默认配置，非 POSIX
  2) Zsh  - POSIX 兼容，通过插件获得类似 fish 的功能
  3) 跳过 Shell 安装

选择 [1/2/3, 默认: 3]: 1
? 是否安装 Fish Shell? [y/N]
? 是否设置 Fish 为默认 Shell? [y/N]
...
```

### 一键卸载

```bash
./setup.sh uninstall
```

这将:
1. 恢复所有备份的配置文件 (`.bashrc`, `.zshrc`, `config.fish` 等)
2. 卸载脚本安装的所有包 (Homebrew, apt, 手动安装的)
3. 清理状态目录
4. 显示移除的内容摘要

### 查看安装状态

```bash
./setup.sh status
```

显示:
- 状态目录位置
- 所有备份文件列表
- 所有已安装的包
- 安装时间戳

### 显示帮助

```bash
./setup.sh --help
./setup.sh -h
```

## 可用组件

所有组件都是 **可选的**，只有在你确认后才会安装:

### 终端模拟器
- **Ghostty** (macOS) - GPU 加速的终端模拟器
- Linux: 提供手动安装说明
- WSL: 在 Windows 端运行，使用 Windows Terminal

### Shell
- **Fish** - 现代 Shell，内置自动建议和语法高亮
- **Zsh** - POSIX 兼容，配有类似 fish 的插件 (自动建议、语法高亮)

### Shell 提示符
- **Starship** - 跨 Shell 提示符，使用 Catppuccin Mocha 主题

### Nerd 字体
- **MesloLGS NF** - 显示图标和 powerline 字形的字体

### 现代 CLI 工具
- **bat** - 带有语法高亮和行号的 `cat` 命令
- **eza** - 带有图标、git 状态、树形视图的 `ls` 命令
- **fd** - 快速且用户友好的 `find` 替代工具
- **ripgrep (rg)** - 快速的 grep 替代工具
- **btop** - 美观的系统监控工具
- **zoxide** - 智能 `cd`，会学习你的习惯
- **jq** - JSON 处理器
- **tldr** - 带有示例的简化 man 页面
- **fzf** - 模糊查找器
- **git-delta** - 带有语法高亮的漂亮 git diff
- **lazygit** - Git 文本用户界面

### 版本管理器
- **fnm** - 快速 Node 版本管理器 (基于 Rust，~1ms Shell 启动时间)

### 终端多路复用器
- **Zellij** - 现代终端多路复用器 (类似 tmux，但有更好的用户体验)

### 配置文件
- Shell 配置文件 (`.zshrc`, `config.fish`)
- Starship 配置 (`starship.toml`)
- 自定义函数 (set-ssh-key)
- Git 配置 (用于 delta)

## 架构

### 状态目录结构

```
~/.terminal-setup/
├── backups/              # 所有带有时间戳的备份配置文件
│   ├── .zshrc.1719000000.bak
│   ├── config.fish.1719000001.bak
│   └── starship.toml.1719000002.bak
├── installed_packages.txt  # 所有已安装包的列表
├── os.txt                 # 检测到的操作系统
├── installed_at.txt       # 安装时间戳
├── shell.txt             # 选择的 Shell 类型
└── state.json            # 结构化的状态信息
```

### 包追踪格式

每个已安装的包都会记录在 `installed_packages.txt` 中，并标记其安装方法:

```
brew:fish
brew:starship
brew:bat
apt:zsh-autosuggestions
curl:fnm
bundled:eza
symlink:bat
```

这使得 uninstall 命令能够准确知道每个包是如何安装的以及如何移除它。

## 平台支持

| 平台 | 状态 | 包管理器 | 备注 |
|------|------|----------|------|
| **macOS** | 完全支持 | Homebrew | 主要目标平台 |
| **Debian/Ubuntu** | 完全支持 | apt | 所有工具可用 |
| **WSL** | 完全支持 | apt | Windows Subsystem for Linux |
| **Windows (原生)** | 不支持 | - | 请使用 WSL |

## 与 lewislulu/terminal-setup 的对比

### 本项目的改进点

1. **用户选择**
   - **之前**: `./setup.sh --fish` 会安装 Ghostty、Fish、所有 CLI 工具、Starship、字体等
   - **现在**: 每个组件都会 **单独询问确认**

2. **回滚能力**
   - **之前**: 备份配置文件，但无法卸载包
   - **现在**: `./setup.sh uninstall` 移除包 **并** 恢复配置

3. **状态可见性**
   - **之前**: 没有集中状态，难以知道安装了什么
   - **现在**: `./setup.sh status` 显示完整的安装状态

4. **安全性**
   - **之前**: 脚本在未经明确确认的情况下进行更改
   - **现在**: 每个更改都需要明确的用户确认 [y/N]

### 继承的工具

本项目保持了来自 lewislulu/terminal-setup 的优秀工具选择:
- 相同的现代 CLI 工具 (bat, eza, fd, rg 等)
- 相同的 Shell 选项 (Fish, Zsh)
- 相同的提示符 (Starship)
- 相同的字体 (MesloLGS NF)
- 相同的额外功能 (fnm, Zellij)

### 新增功能

1. **交互式选择加入** - 每个组件都需要明确确认
2. **包追踪** - 记录每个包的安装方式
3. **完整卸载** - 移除包并恢复配置
4. **状态管理** - 集中追踪所有更改
5. **状态命令** - 随时查看安装状态
6. **更好的错误处理** - 使用 `set -euo pipefail` 提高稳健性

## Shell 配置

### Fish Shell

如果你安装 Fish，将会配置以下内容:

```fish
# Starship 提示符
starship init fish | source

# 缩写
abbr -a ls "eza --icons --group-directories-first"
abbr -a ll "eza -la --icons --group-directories-first"
abbr -a cat "bat"
abbr -a find "fd"
abbr -a grep "rg"

# zoxide
zoxide init fish | source

# fzf
fzf --fish | source

# 自定义函数
set-ssh-key [key-name]  # 切换 SSH 密钥
```

### Zsh

如果你安装 Zsh，将会配置以下内容:

```zsh
# Starship 提示符
eval "$(starship init zsh)"

# 插件
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# fzf
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh

# zoxide
eval "$(zoxide init zsh)"

# 别名
alias ls="eza --icons --group-directories-first"
alias cat="bat"
alias find="fd"
alias grep="rg"

# 自定义函数
set-ssh-key [key-name]  # 切换 SSH 密钥
```

## 贡献

欢迎贡献！请随时提交问题或拉取请求。

### 开发

1. Fork 仓库
2. 创建功能分支 (`git checkout -b feature/your-feature`)
3. 进行更改
4. 在多个平台上测试脚本
5. 提交更改 (`git commit -m 'feat: your feature'`)
6. 推送到分支 (`git push origin feature/your-feature`)
7. 创建 Pull Request

## 许可证

本项目采用 MIT 许可证 - 详情请查看 [LICENSE](LICENSE) 文件。

## 鸣谢

- 灵感来自 [lewislulu/terminal-setup](https://github.com/lewislulu/terminal-setup)
- 感谢所有被包含在本设置中的出色 CLI 工具的开发者
- 特别感谢 Homebrew、Fish Shell 和 Zsh 社区

## 支持

如果你遇到任何问题或有疑问，请在 GitHub 上创建 Issue。

---

**祝你有愉快的现代终端体验！**
