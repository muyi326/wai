#!/bin/bash

# WAI Protocol Worker Node 部署脚本（macOS 版）
# 注意：此脚本通过 bash <(curl -fsSL URL) 方式运行
SCRIPT_URL="https://gist.githubusercontent.com/muyi326/4f09a8982f24595b647bbc999ca23d08/raw/autoWai.sh"

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
        
        # 改进的重启机制：使用更可靠的下载方式
        TEMP_FILE=$(mktemp)
        log "尝试重新下载脚本..."
        
        # 尝试多种下载方式
        if curl --retry 3 --retry-delay 2 --connect-timeout 30 -fsSL "$SCRIPT_URL" -o "$TEMP_FILE" || \
           wget -q --tries=3 --timeout=30 "$SCRIPT_URL" -O "$TEMP_FILE" || \
           python -c "import urllib.request; urllib.request.urlretrieve('$SCRIPT_URL', '$TEMP_FILE')" 2>/dev/null
        then
            # 检查脚本完整性
            if [ -s "$TEMP_FILE" ] && tail -1 "$TEMP_FILE" | grep -q "main"; then
                log "下载完成，执行脚本..."
                chmod +x "$TEMP_FILE"
                exec "$TEMP_FILE"
            else
                warn "下载的脚本不完整，尝试备用下载源..."
                # 尝试直接使用Gist ID下载
                ALT_URL="https://gist.githubusercontent.com/muyi326/4f09a8982f24595b647bbc999ca23d08/raw/autoWai.sh"
                if curl -fsSL "$ALT_URL" -o "$TEMP_FILE"; then
                    log "备用下载源成功，执行脚本..."
                    chmod +x "$TEMP_FILE"
                    exec "$TEMP_FILE"
                else
                    error "备用下载源也失败，请检查网络连接"
                fi
            fi
        else
            warn "下载失败，尝试直接执行上次下载的脚本..."
            # 检查是否有本地副本
            if [ -f "$0" ]; then
                log "找到本地脚本副本，直接执行..."
                exec "$0"
            else
                error "无法下载脚本且没有本地副本"
            fi
        fi
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

# [保留其他函数不变：install_homebrew, install_dependencies, install_wai_cli, configure_env, start_wai, show_monitor_commands]

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
