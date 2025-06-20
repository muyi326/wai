#!/bin/bash

# WAI Protocol Worker Node 部署脚本（macOS 版）
# 注意：此脚本通过 bash <(curl -fsSL URL) 方式运行 
SCRIPT_URL="https://raw.githubusercontent.com/muyi326/wai/refs/heads/main/autoTest.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置文件路径
CONFIG_FILE="$HOME/.wai_install_config"
MAX_RETRY=3
RETRY_COUNT=0

# 日志函数
log() { echo -e "${GREEN}[INFO] $1${NC}"; }
error() { 
    echo -e "${RED}[ERROR] $1${NC}"
    save_config
    if [ $RETRY_COUNT -lt $MAX_RETRY ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "将在5秒后重试 (${RETRY_COUNT}/${MAX_RETRY})..."
        sleep 5
        log "重新下载脚本并执行..."
        exec bash -c "$(curl -fsSL $SCRIPT_URL)"
    else
        log "已达到最大重试次数 ($MAX_RETRY)，停止重试"
        cleanup_config
        exit 1
    fi
}
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }

# 配置管理函数
save_config() {
    echo "USER_CONTINUE=\"$USER_CONTINUE\"" > "$CONFIG_FILE"
    echo "API_KEY=\"$API_KEY\"" >> "$CONFIG_FILE"
    echo "RETRY_COUNT=\"$RETRY_COUNT\"" >> "$CONFIG_FILE"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        [[ -z "$RETRY_COUNT" ]] && RETRY_COUNT=0
    else
        RETRY_COUNT=0
    fi
}

cleanup_config() {
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
}

# 系统检查
check_system() {
    log "检查系统环境..."
    [[ "$(uname)" != "Darwin" ]] && error "此脚本仅支持 macOS 系统"
    
    chip=$(sysctl -n machdep.cpu.brand_string)
    if [[ ! "$chip" =~ "Apple M" ]]; then
        warn "未检测到 Apple M 系列芯片，当前芯片: $chip"
        
        if [ -z "$USER_CONTINUE" ]; then
            read -p "是否继续? (y/n): " USER_CONTINUE
            save_config
        fi
        
        [[ "$USER_CONTINUE" != "y" && "$USER_CONTINUE" != "Y" ]] && {
            warn "用户退出安装"
            cleanup_config
            exit 0
        }
    else
        log "检测到 Apple M 系列芯片: $chip"
    fi
}

# 检查和安装 Homebrew
install_homebrew() {
    log "检查 Homebrew 是否已安装..."
    if command -v brew &> /dev/null; then
        log "Homebrew 已安装，版本：$(brew --version | head -n1)"
        log "更新 Homebrew..."
        brew update
    else
        log "未检测到 Homebrew，正在安装..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ $? -ne 0 ]]; then
            error "Homebrew 安装失败，请手动安装 Homebrew 后重试"
        fi
        # 配置 Homebrew 环境变量
        log "配置 Homebrew 环境变量..."
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
        log "Homebrew 安装成功"
    fi
}

# 安装依赖并跳过已安装项
install_dependencies() {
    log "检查并安装必要的依赖..."

    # 定义需要检查的通用工具
    local tools=("nano" "curl" "git" "wget" "jq" "automake" "autoconf" "htop")
    local tools_to_install=()

    # 检查每个工具是否已安装
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log "$tool 已安装，跳过"
        else
            tools_to_install+=("$tool")
        fi
    done

    # 安装缺失的工具
    if [ ${#tools_to_install[@]} -gt 0 ]; then
        log "安装缺失的工具：${tools_to_install[*]}"
        brew install "${tools_to_install[@]}"
        if [[ $? -ne 0 ]]; then
            error "依赖安装失败，请检查 Homebrew 和网络连接"
        fi
    else
        log "所有通用工具已安装，跳过"
    fi

    # 检查和安装 Python
    log "检查 Python..."
    if command -v python3 &> /dev/null; then
        log "Python 已安装，版本：$(python3 --version)"
    else
        log "安装 Python..."
        brew install python
        if ! command -v python3 &> /dev/null; then
            error "Python 安装失败，请检查 Homebrew 和网络连接"
        fi
        log "Python 安装成功，版本：$(python3 --version)"
    fi

    # 检查和安装 Node.js
    log "检查 Node.js..."
    if command -v node &> /dev/null; then
        log "Node.js 已安装，版本：$(node -v)"
    else
        log "安装 Node.js..."
        brew install node
        if ! command -v node &> /dev/null; then
            error "Node.js 安装失败，请检查 Homebrew 和网络连接"
        fi
        log "Node.js 安装成功，版本：$(node -v)"
    fi

    # 检查和安装 Yarn
    log "检查 Yarn..."
    if command -v yarn &> /dev/null; then
        log "Yarn 已安装，版本：$(yarn -v)"
    else
        log "安装 Yarn..."
        npm install -g yarn --force
        if [[ $? -ne 0 ]]; then
            error "Yarn 安装失败，请检查 npm 日志：/Users/$USER/.npm/_logs/*.log 或手动删除 /opt/homebrew/bin/yarn 后重试"
        fi
        log "Yarn 安装成功，版本：$(yarn -v)"
    fi
}

# 安装 WAI CLI 并配置 PATH
install_wai_cli() {
    log "检查 WAI CLI 是否已安装..."
    if command -v wai &> /dev/null; then
        log "WAI CLI 已安装，位置：$(which wai)"
    else
        log "安装 WAI CLI..."
        curl -fsSL https://app.w.ai/install.sh | bash
        if [[ $? -ne 0 ]]; then
            error "WAI CLI 安装失败，请检查网络连接或稍后重试"
        fi

        # 配置 PATH
        log "配置 PATH 以包含 /Users/$USER/.local/bin..."
        zshrc_file="$HOME/.zshrc"
        wai_bin_path="/Users/$USER/.local/bin"
        if grep -Fx "export PATH=\"$wai_bin_path:\$PATH\"" "$zshrc_file" > /dev/null; then
            log "PATH 已包含 $wai_bin_path，跳过写入"
        else
            echo "export PATH=\"$wai_bin_path:\$PATH\"" >> "$zshrc_file"
            if [[ $? -ne 0 ]]; then
                error "写入 PATH 到 ~/.zshrc 失败，请检查文件权限"
            fi
            log "PATH 已写入 ~/.zshrc"
        fi

        # 加载 .zshrc
        log "加载 ~/.zshrc 以更新 PATH..."
        if ! source "$zshrc_file" 2>/dev/null; then
            warn "加载 ~/.zshrc 失败，您可能需要手动运行 'source ~/.zshrc'"
        else
            log "PATH 更新成功"
        fi

        # 验证 WAI CLI 是否可用
        if ! command -v wai &> /dev/null; then
            error "WAI CLI 未正确安装，请检查 /Users/$USER/.local/bin/wai 是否存在或手动运行 'source ~/.zshrc'"
        fi
        log "WAI CLI 安装成功，位置：$(which wai)"
    fi
}

# 获取用户输入并配置永久环境变量
configure_env() {
    # 检查是否有保存的API密钥
    if [ -z "$API_KEY" ]; then
        log "请提供 WAI API 密钥"
        read -p "输入您的 WAI API 密钥: " API_KEY
        save_config
    fi
    
    if [[ -z "$API_KEY" ]]; then
        error "API 密钥不能为空"
    fi

    # 设置当前会话的环境变量
    export W_AI_API_KEY="$API_KEY"
    log "当前会话环境变量 W_AI_API_KEY 已设置"

    # 检查 ~/.zshrc 是否存在，若不存在则创建
    zshrc_file="$HOME/.zshrc"
    if [[ ! -f "$zshrc_file" ]]; then
        log "未找到 ~/.zshrc，创建新文件..."
        touch "$zshrc_file"
        chmod u+w "$zshrc_file"
        if [[ $? -ne 0 ]]; then
            error "创建 ~/.zshrc 失败，请检查文件权限"
        fi
    fi

    # 检查是否已有 W_AI_API_KEY，更新或追加
    log "检查 WAI API 密钥是否已写入 ~/.zshrc..."
    if grep -E "^export W_AI_API_KEY=" "$zshrc_file" > /dev/null; then
        log "W_AI_API_KEY 已存在于 ~/.zshrc，正在更新..."
        sed -i '' "s|^export W_AI_API_KEY=.*|export W_AI_API_KEY=\"$API_KEY\"|" "$zshrc_file"
        if [[ $? -ne 0 ]]; then
            error "更新 W_AI_API_KEY 到 ~/.zshrc 失败，请检查文件权限"
        fi
    else
        log "写入 WAI API 密钥到 ~/.zshrc..."
        echo "export W_AI_API_KEY=\"$API_KEY\"" >> "$zshrc_file"
        if [[ $? -ne 0 ]]; then
            error "写入 W_AI_API_KEY 到 ~/.zshrc 失败，请检查文件权限"
        fi
    fi
    log "环境变量 W_AI_API_KEY 已永久写入 ~/.zshrc"

    # 加载 ~/.zshrc 以确保当前会话生效
    log "加载 ~/.zshrc 以应用环境变量..."
    if ! source "$zshrc_file" 2>/dev/null; then
        warn "加载 ~/.zshrc 失败，尝试使用 zsh -c source..."
        zsh -c "source $zshrc_file" 2>/dev/null
        if [[ $? -ne 0 ]]; then
            warn "加载 ~/.zshrc 仍然失败，您需要手动运行 'source ~/.zshrc' 或在新终端中运行 'wai run'"
        else
            log "环境变量通过 zsh -c 加载成功"
        fi
    else
        log "环境变量加载成功"
    fi

    # 验证环境变量是否生效
    if [[ -z "$W_AI_API_KEY" ]]; then
        warn "环境变量 W_AI_API_KEY 未在当前会话生效，尝试直接设置..."
        export W_AI_API_KEY="$API_KEY"
        if [[ -z "$W_AI_API_KEY" ]]; then
            error "环境变量 W_AI_API_KEY 仍未生效，请检查 Shell 环境或手动运行 'export W_AI_API_KEY=$API_KEY'"
        fi
    fi
    log "环境变量 W_AI_API_KEY 已验证生效，值：$(echo $W_AI_API_KEY | cut -c1-4)****（隐藏部分字符）"
}

# 直接运行 wai run（前台）
start_wai() {
    log "正在启动 WAI Worker（前台运行）..."
    wai run
    if [[ $? -ne 0 ]]; then
        error "启动 wai run 失败，请检查 WAI CLI、环境变量 W_AI_API_KEY 或查看日志 (~/.wombo)"
    fi
}

# 提供监控命令
show_monitor_commands() {
    log "以下是常用监控命令："
    echo "  - 查看 CPU 和内存使用：htop"
    echo "  - 查看磁盘使用：du -sh ~/.wombo"
    echo "  - 停止 Worker：按 Ctrl+C 在终端中终止"
    echo "  - 查看 WAI 日志：cat ~/.wombo/*.log"
}

# 主函数
main() {
    load_config
    check_system
    install_homebrew
    install_dependencies
    install_wai_cli
    configure_env
    show_monitor_commands
    start_wai
    cleanup_config
    log "部署完成! WAI Worker 正在运行，按 Ctrl+C 停止"
}

# 执行入口
main
