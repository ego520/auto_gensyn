#!/bin/bash

set -e
set -o pipefail

# ==================== 自定义配置区域 ====================
REPO_OWNER="ego520"
REPO_NAME="auto_gensyn"
REPO_BRANCH="main"
SCRIPT_PATH="install_gensyn.sh"
# ======================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 密码验证函数 - 使用您的自定义密码 "python"
verify_password() {
    local auth_file="$HOME/.ego_gensyn_auth"
    local max_attempts=3
    local attempt=1
    
    # 检查是否已经验证过
    if [[ -f "$auth_file" ]]; then
        local stored_hash=$(cat "$auth_file" 2>/dev/null || echo "")
        local machine_id=$(uname -m)-$(hostname)-$(whoami)
        local expected_hash=$(echo "$machine_id" | openssl dgst -sha256 2>/dev/null | cut -d' ' -f2 || echo "invalid")
        
        if [[ "$stored_hash" == "$expected_hash" && "$expected_hash" != "invalid" ]]; then
            log_success "身份验证通过，跳过密码验证"
            # 从验证文件中读取权限级别
            if [[ -f "$HOME/.ego_gensyn_permission" ]]; then
                export GENSYN_PERMISSION=$(cat "$HOME/.ego_gensyn_permission")
            else
                export GENSYN_PERMISSION="full"
            fi
            return 0
        else
            log_warning "检测到环境变化，需要重新验证"
            rm -f "$auth_file" 2>/dev/null || true
            rm -f "$HOME/.ego_gensyn_permission" 2>/dev/null || true
        fi
    fi
    
    # 首次运行或需要重新验证
    echo ""
    log_info "首次部署需要验证身份"
    echo "请输入部署密码（最多尝试 $max_attempts 次）"
    echo "提示：密码是 'python'"
    echo ""
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -n "密码 (尝试 $attempt/$max_attempts): "
        read -s password
        echo
        
        # 您的自定义密码 - "python"
        if [[ "$password" == "python" ]]; then
            log_success "密码验证成功！权限级别：完整权限"
            export GENSYN_PERMISSION="full"
            
            # 生成并保存验证文件
            local machine_id=$(uname -m)-$(hostname)-$(whoami)
            local auth_hash=$(echo "$machine_id" | openssl dgst -sha256 2>/dev/null | cut -d' ' -f2 || echo "default")
            echo "$auth_hash" > "$auth_file"
            echo "full" > "$HOME/.ego_gensyn_permission"
            chmod 600 "$auth_file" 2>/dev/null || true
            chmod 600 "$HOME/.ego_gensyn_permission" 2>/dev/null || true
            
            log_success "身份验证信息已保存，后续部署无需再次输入密码"
            return 0
        else
            log_error "密码错误"
            if [[ $attempt -lt $max_attempts ]]; then
                log_warning "还有 $((max_attempts - attempt)) 次机会"
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "密码验证失败，已达到最大尝试次数"
    exit 1
}

# 显示横幅
show_banner() {
    clear
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║      🚀 ego520 自定义 Gensyn 一键部署脚本                ║"
    echo "║      📦 仓库：$REPO_OWNER/$REPO_NAME                     ║"
    echo "║      🔐 密码：python                                     ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

# 主函数
main() {
    show_banner
    
    # 1. 密码验证
    verify_password
    
    # 2. 检测操作系统
    log_info "检测操作系统..."
    OS_TYPE="unknown"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS_TYPE="macos"
        log_success "检测到 macOS 系统"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]]; then
            OS_TYPE="ubuntu"
            log_success "检测到 Ubuntu/Debian 系统"
        fi
    fi
    
    if [[ "$OS_TYPE" == "unknown" ]]; then
        log_error "不支持的操作系统。仅支持 macOS 和 Ubuntu/Debian。"
        exit 1
    fi
    
    # 3. 系统优化
    log_info "优化系统配置..."
    
    # 修改文件描述符限制
    if [[ "$OS_TYPE" == "ubuntu" ]]; then
        if ! grep -q "fs.file-max" /etc/sysctl.conf; then
            echo "fs.file-max = 100000" | sudo tee -a /etc/sysctl.conf
            sudo sysctl -p
            log_success "已优化文件描述符限制"
        fi
    fi
    
    # 4. Hosts 配置（可选）
    log_info "配置网络加速..."
    read -p "是否配置 GitHub 加速？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! grep -q "raw.githubusercontent.com" /etc/hosts 2>/dev/null; then
            echo "199.232.68.133 raw.githubusercontent.com" | sudo tee -a /etc/hosts > /dev/null
            log_success "GitHub 加速已配置"
        else
            log_info "GitHub 加速已存在"
        fi
    fi
    
    # 5. 安装系统依赖
    log_info "安装系统依赖..."
    
    if [[ "$OS_TYPE" == "macos" ]]; then
        # macOS 依赖安装
        if ! command -v brew &>/dev/null; then
            log_info "安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        
        # 安装基础工具
        for pkg in git curl wget screen tmux; do
            if ! command -v $pkg &>/dev/null; then
                brew install $pkg
            fi
        done
        
    else
        # Ubuntu/Debian 依赖安装
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y git curl wget screen tmux build-essential \
            ca-certificates software-properties-common
        
        # 安装 Node.js (最新 LTS)
        if ! command -v node &>/dev/null; then
            log_info "安装 Node.js LTS..."
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt install -y nodejs
        fi
        
        # 安装 Python 3.10+
        if ! command -v python3 &>/dev/null; then
            sudo apt install -y python3 python3-pip python3-venv
        fi
    fi
    
    # 6. 显示系统信息
    log_info "系统信息汇总："
    echo "========================================"
    echo "系统: $(uname -srm)"
    echo "用户: $(whoami)"
    echo "主机: $(hostname)"
    echo "Python: $(python3 --version 2>/dev/null || echo '未安装')"
    echo "Node.js: $(node --version 2>/dev/null || echo '未安装')"
    echo "Git: $(git --version 2>/dev/null || echo '未安装')"
    echo "========================================"
    
    # 7. 创建项目目录
    log_info "创建项目目录..."
    PROJECT_DIR="$HOME/ego_gensyn"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # 8. 检查是否已有 rl-swarm
    if [[ -d "rl-swarm" ]]; then
        log_warning "检测到已存在的 rl-swarm 目录"
        read -p "是否更新？(y-更新/n-保留/q-退出): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd rl-swarm
            git pull origin 0.7.0
            log_success "rl-swarm 已更新"
        elif [[ $REPLY =~ ^[Qq]$ ]]; then
            log_info "用户取消操作"
            exit 0
        fi
    else
        log_info "克隆 rl-swarm 项目..."
        git clone -b 0.7.0 https://github.com/readyName/rl-swarm.git
    fi
    
    # 9. 进入项目目录
    cd "$PROJECT_DIR/rl-swarm" || {
        log_error "无法进入项目目录"
        exit 1
    }
    
    # 10. 设置执行权限
    chmod +x *.sh 2>/dev/null || true
    
    # 11. 生成桌面快捷方式 (macOS)
    if [[ "$OS_TYPE" == "macos" ]]; then
        log_info "生成桌面快捷方式..."
        DESKTOP_DIR="$HOME/Desktop"
        mkdir -p "$DESKTOP_DIR"
        
        # 生成启动脚本
        cat > "$DESKTOP_DIR/ego_gensyn.command" << 'EOF'
#!/bin/bash
cd ~/ego_gensyn/rl-swarm
./gensyn.sh
echo "按任意键退出..."
read -n 1
EOF
        chmod +x "$DESKTOP_DIR/ego_gensyn.command"
        log_success "桌面快捷方式已创建"
    fi
    
    # 12. 完成提示
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║         🎉 部署完成！                   ║"
    echo "╠══════════════════════════════════════════╣"
    echo "║                                          ║"
    echo "║  项目目录: $PROJECT_DIR                 ║"
    echo "║  认证文件: ~/.ego_gensyn_auth           ║"
    echo "║  启动命令: cd $PROJECT_DIR/rl-swarm    ║"
    echo "║            ./gensyn.sh                  ║"
    echo "║                                          ║"
    if [[ "$OS_TYPE" == "macos" ]]; then
        echo "║  macOS: 双击桌面 ego_gensyn.command     ║"
    fi
    echo "║                                          ║"
    echo "║  下次部署无需密码验证                    ║"
    echo "║                                          ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    
    # 13. 询问是否立即启动
    read -p "是否立即启动 gensyn？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "启动 gensyn..."
        ./gensyn.sh || {
            log_warning "启动失败，请手动检查"
            echo "可以尝试: cd $PROJECT_DIR/rl-swarm && ./gensyn.sh"
        }
    else
        log_info "您可以稍后手动启动："
        echo "cd $PROJECT_DIR/rl-swarm && ./gensyn.sh"
    fi
}

# 异常处理
trap 'log_error "脚本被中断"; exit 1' INT TERM

# 启动主函数
main "$@"
