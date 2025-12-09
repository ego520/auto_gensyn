
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
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${PURPLE}🔸 $1${NC}"
}

log_debug() {
    echo -e "${CYAN}🐛 $1${NC}"
}

# 密码验证函数 - 使用 base64 编码的密码
verify_password() {
    local auth_file="$HOME/.ego_gensyn_auth"
    local max_attempts=3
    local attempt=1
    
    # 显示欢迎信息
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║              ego520 自定义 Gensyn 部署脚本                 ║"
    echo "║                仓库：$REPO_OWNER/$REPO_NAME                ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
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
    log_info "首次部署需要验证身份"
    echo "请输入部署密码（最多尝试 $max_attempts 次）"
    echo "提示：密码查看个人资料"
    echo ""
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -n "🔐 密码 (尝试 $attempt/$max_attempts): "
        read -s password
        echo
        local password1_encoded="cHl0aG9u"  
        
        # 计算输入密码
        local input_encoded=$(echo -n "$password" | base64 2>/dev/null || echo "invalid")
        
        if [[ "$input_encoded" == "invalid" ]]; then
            log_error "密码编码失败，请重试"
            attempt=$((attempt + 1))
            continue
        fi
        
        if [[ "$input_encoded" == "$password1_encoded" ]]; then
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
                echo "提示：密码是 'python' (base64: cHl0aG9u)"
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "密码验证失败，已达到最大尝试次数"
    log_error "如果您忘记了密码，请删除验证文件重新开始："
    echo "rm -f ~/.ego_gensyn_auth ~/.ego_gensyn_permission"
    exit 1
}

# 检测操作系统
detect_os() {
    log_step "检测操作系统..."
    OS_TYPE="unknown"
    OS_NAME=""
    OS_VERSION=""
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS_TYPE="macos"
        OS_NAME="macOS"
        OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
        log_success "检测到 $OS_NAME $OS_VERSION"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        
        case "$ID" in
            ubuntu|debian)
                OS_TYPE="ubuntu"
                log_success "检测到 $OS_NAME $OS_VERSION"
                ;;
            centos|rhel|fedora)
                OS_TYPE="centos"
                log_success "检测到 $OS_NAME $OS_VERSION"
                ;;
            *)
                OS_TYPE="linux"
                log_warning "检测到 Linux 系统: $OS_NAME"
                ;;
        esac
    elif [[ -f /etc/redhat-release ]]; then
        OS_TYPE="centos"
        OS_NAME=$(cat /etc/redhat-release)
        log_success "检测到 $OS_NAME"
    else
        log_warning "无法识别的操作系统，尝试继续..."
        OS_TYPE="linux"
    fi
    
    export OS_TYPE
    export OS_NAME
    export OS_VERSION
}

# 安装系统依赖
install_dependencies() {
    log_step "安装系统依赖..."
    
    case "$OS_TYPE" in
        macos)
            install_dependencies_macos
            ;;
        ubuntu|debian)
            install_dependencies_ubuntu
            ;;
        centos)
            install_dependencies_centos
            ;;
        *)
            log_warning "不支持的操作系统类型，跳过依赖安装"
            ;;
    esac
}

install_dependencies_macos() {
    log_info "安装 macOS 依赖..."
    
    # 检查 Homebrew
    if ! command -v brew &>/dev/null; then
        log_info "安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # 配置 Homebrew 环境
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc
        fi
    fi
    
    # 安装基础工具
    local packages=(
        "git:git"
        "curl:curl"
        "wget:wget"
        "screen:screen"
        "tmux:tmux"
        "python3:python@3.10"
        "node:node"
        "jq:jq"
    )
    
    for check_cmd in "openssl" "unzip" "tar"; do
        packages+=("$check_cmd:$check_cmd")
    done
    
    for package in "${packages[@]}"; do
        IFS=':' read -r check_cmd brew_pkg <<< "$package"
        if ! command -v "$check_cmd" &>/dev/null; then
            log_info "安装 $brew_pkg..."
            if brew install "$brew_pkg"; then
                log_success "$brew_pkg 安装成功"
            else
                log_warning "$brew_pkg 安装失败，继续..."
            fi
        else
            log_debug "$check_cmd 已安装"
        fi
    done
}

install_dependencies_ubuntu() {
    log_info "安装 Ubuntu/Debian 依赖..."
    
    # 更新包列表
    sudo apt update -y
    
    # 安装基础工具
    local packages=(
        "git:git"
        "curl:curl"
        "wget:wget"
        "screen:screen"
        "tmux:tmux"
        "python3:python3 python3-pip python3-venv"
        "jq:jq"
        "unzip:unzip"
        "tar:tar"
        "build-essential:build-essential"
        "ca-certificates:ca-certificates"
        "software-properties-common:software-properties-common"
        "openssl:openssl"
    )
    
    for package in "${packages[@]}"; do
        IFS=':' read -r check_cmd pkg_list <<< "$package"
        if ! command -v "$check_cmd" &>/dev/null; then
            log_info "安装 $pkg_list..."
            if sudo apt install -y $pkg_list; then
                log_success "$pkg_list 安装成功"
            else
                log_warning "$pkg_list 安装失败，继续..."
            fi
        else
            log_debug "$check_cmd 已安装"
        fi
    done
    
    # 安装 Node.js (最新 LTS)
    if ! command -v node &>/dev/null; then
        log_info "安装 Node.js LTS..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt install -y nodejs
        log_success "Node.js 安装成功"
    fi
    
    # 升级 pip
    if command -v pip3 &>/dev/null; then
        pip3 install --upgrade pip setuptools wheel
    fi
}

install_dependencies_centos() {
    log_info "安装 CentOS/RHEL 依赖..."
    
    # 安装基础工具
    sudo yum install -y epel-release
    sudo yum install -y git curl wget screen tmux python3 python3-pip \
        jq unzip tar gcc-c++ make openssl
    
    # 安装 Node.js
    if ! command -v node &>/dev/null; then
        log_info "安装 Node.js..."
        curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
        sudo yum install -y nodejs
    fi
}

# 配置系统优化
configure_system() {
    log_step "配置系统优化..."
    
    case "$OS_TYPE" in
        ubuntu|debian|centos)
            # 修改文件描述符限制
            if ! grep -q "fs.file-max" /etc/sysctl.conf 2>/dev/null; then
                log_info "优化文件描述符限制..."
                echo "fs.file-max = 100000" | sudo tee -a /etc/sysctl.conf > /dev/null
                echo "vm.swappiness = 10" | sudo tee -a /etc/sysctl.conf > /dev/null
                sudo sysctl -p
                log_success "系统参数优化完成"
            fi
            
            # 修改用户限制
            if ! grep -q "nofile" /etc/security/limits.conf 2>/dev/null; then
                log_info "优化用户资源限制..."
                echo "* soft nofile 65535" | sudo tee -a /etc/security/limits.conf > /dev/null
                echo "* hard nofile 65535" | sudo tee -a /etc/security/limits.conf > /dev/null
                echo "* soft nproc 65535" | sudo tee -a /etc/security/limits.conf > /dev/null
                echo "* hard nproc 65535" | sudo tee -a /etc/security/limits.conf > /dev/null
                log_success "用户资源限制优化完成"
            fi
            ;;
        macos)
            # macOS 优化
            log_info "配置 macOS 优化..."
            # 可以添加 macOS 特定的优化
            ;;
    esac
}

# 配置 GitHub 加速
configure_github_accelerator() {
    log_step "配置网络加速..."
    
    read -p "是否配置 GitHub 加速？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "跳过 GitHub 加速配置"
        return
    fi
    
    local hosts_entries=(
        "199.232.68.133 raw.githubusercontent.com"
        "199.232.68.133 user-images.githubusercontent.com"
        "199.232.68.133 avatars2.githubusercontent.com"
        "199.232.68.133 avatars1.githubusercontent.com"
        "199.232.68.133 avatars0.githubusercontent.com"
        "199.232.68.133 avatars.githubusercontent.com"
        "199.232.68.133 github.githubassets.com"
    )
    
    local added=false
    for entry in "${hosts_entries[@]}"; do
        if ! grep -q "$(echo "$entry" | cut -d' ' -f2)" /etc/hosts 2>/dev/null; then
            echo "$entry" | sudo tee -a /etc/hosts > /dev/null
            added=true
        fi
    done
    
    if $added; then
        log_success "GitHub 加速已配置"
    else
        log_info "GitHub 加速配置已存在"
    fi
    
    # 测试连接
    log_info "测试 GitHub 连接..."
    if curl -s --connect-timeout 5 https://raw.githubusercontent.com > /dev/null; then
        log_success "GitHub 连接正常"
    else
        log_warning "GitHub 连接测试失败"
    fi
}

# 显示系统信息
show_system_info() {
    log_step "系统信息汇总"
    echo "========================================"
    echo "系统: $(uname -srm)"
    echo "主机: $(hostname)"
    echo "用户: $(whoami)"
    echo "目录: $(pwd)"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "----------------------------------------"
    
    # 软件版本
    local tools=("python3" "node" "npm" "git" "docker")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            version=$("$tool" --version 2>/dev/null | head -n1)
            echo "$tool: $version"
        else
            echo "$tool: 未安装"
        fi
    done
    
    echo "========================================"
}

# 备份现有项目
backup_existing_project() {
    log_step "检查现有项目备份..."
    
    local backup_dir="$HOME/gensyn_backup_$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$backup_dir"
    
    # 检查可能存在的项目目录
    local possible_dirs=(
        "$HOME/rl-swarm"
        "$HOME/rl-swarm-0.5"
        "$HOME/rl-swarm-0.5.3"
        "$HOME/ego_gensyn"
        "$HOME/gensyn"
    )
    
    local backed_up=false
    for dir in "${possible_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "发现现有目录: $dir"
            read -p "是否备份此目录？(y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                local dir_name=$(basename "$dir")
                cp -r "$dir" "$backup_dir/$dir_name"
                log_success "已备份 $dir 到 $backup_dir/$dir_name"
                backed_up=true
            fi
        fi
    done
    
    if $backed_up; then
        log_info "备份目录: $backup_dir"
        echo "备份文件列表:"
        ls -la "$backup_dir"
    else
        rmdir "$backup_dir" 2>/dev/null || true
    fi
}

# 克隆项目
clone_project() {
    log_step "部署 RL-Swarm 项目..."
    
    PROJECT_DIR="$HOME/ego_gensyn"
    
    # 检查是否已存在
    if [[ -d "$PROJECT_DIR" ]]; then
        log_warning "发现已存在的项目目录: $PROJECT_DIR"
        read -p "如何处理？(u-更新/c-清除并重新克隆/s-跳过): " -n 1 -r
        echo
        
        case $REPLY in
            [Uu])
                log_info "更新现有项目..."
                cd "$PROJECT_DIR"
                if [[ -d "rl-swarm" ]]; then
                    cd rl-swarm
                    git pull origin 0.7.0 || {
                        log_error "更新失败"
                        exit 1
                    }
                    log_success "项目更新成功"
                else
                    log_error "未找到 rl-swarm 目录"
                    exit 1
                fi
                return 0
                ;;
            [Cc])
                log_info "清除并重新克隆..."
                rm -rf "$PROJECT_DIR"
                ;;
            [Ss])
                log_info "跳过克隆，使用现有目录"
                return 0
                ;;
            *)
                log_error "无效的选择"
                exit 1
                ;;
        esac
    fi
    
    # 创建项目目录
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # 克隆项目
    log_info "克隆 rl-swarm 仓库 (0.7.0 分支)..."
    if git clone -b 0.7.0 https://github.com/readyName/rl-swarm.git; then
        log_success "项目克隆成功"
    else
        log_error "克隆失败，请检查网络连接"
        log_info "尝试使用备用源..."
        git clone -b 0.7.0 https://gitee.com/mirrors_rl-swarm/rl-swarm.git || {
            log_error "备用源也失败"
            exit 1
        }
    fi
    
    # 进入项目目录
    cd rl-swarm || {
        log_error "无法进入项目目录"
        exit 1
    }
    
    # 设置执行权限
    chmod +x *.sh 2>/dev/null || true
    log_success "项目部署完成"
}

# 创建桌面快捷方式 (macOS)
create_desktop_shortcuts() {
    if [[ "$OS_TYPE" != "macos" ]]; then
        return
    fi
    
    log_step "创建桌面快捷方式..."
    
    DESKTOP_DIR="$HOME/Desktop"
    mkdir -p "$DESKTOP_DIR"
    
    # 创建启动脚本
    cat > "$DESKTOP_DIR/ego_gensyn.command" << 'EOF'
#!/bin/bash
clear

echo "╔══════════════════════════════════════════╗"
echo "║      ego520 Gensyn 启动器               ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

cd ~/ego_gensyn/rl-swarm || {
    echo "❌ 无法进入项目目录"
    echo "请检查 ~/ego_gensyn/rl-swarm 是否存在"
    read -n 1 -s -p "按任意键退出..."
    exit 1
}

echo "✅ 进入项目目录"
echo "正在启动 gensyn.sh..."
echo "========================================"

./gensyn.sh

echo ""
echo "========================================"
echo "脚本执行完成"
read -n 1 -s -p "按任意键退出..."
EOF
    
    chmod +x "$DESKTOP_DIR/ego_gensyn.command"
    log_success "桌面快捷方式创建成功: $DESKTOP_DIR/ego_gensyn.command"
    
    # 创建管理脚本
    cat > "$DESKTOP_DIR/ego_gensyn_manage.command" << 'EOF'
#!/bin/bash
clear

echo "╔══════════════════════════════════════════╗"
echo "║      ego520 Gensyn 管理工具             ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "请选择操作："
echo "1. 查看状态"
echo "2. 重启服务"
echo "3. 查看日志"
echo "4. 更新脚本"
echo "5. 重置认证"
echo "6. 退出"
echo ""

read -p "请输入选择 (1-6): " choice

case $choice in
    1)
        echo ""
        echo "🔍 系统状态："
        echo "----------------------------------------"
        echo "CPU 使用率: $(top -l 1 | grep -E "^CPU" | cut -d',' -f1)"
        echo "内存使用: $(top -l 1 | grep -E "^PhysMem")"
        echo "网络连接: $(netstat -an | grep ESTABLISHED | wc -l) 个已建立连接"
        echo "磁盘空间:"
        df -h | grep -E "^/dev/"
        echo "----------------------------------------"
        ;;
    2)
        echo ""
        echo "🔄 重启服务..."
        pkill -f gensyn 2>/dev/null || true
        sleep 2
        cd ~/ego_gensyn/rl-swarm && ./gensyn.sh &
        echo "✅ 服务已重启"
        ;;
    3)
        echo ""
        echo "📋 最近日志："
        echo "----------------------------------------"
        ls -lt ~/ego_gensyn/rl-swarm/*.log 2>/dev/null | head -5
        echo "----------------------------------------"
        read -p "查看哪个日志文件？: " logfile
        if [[ -f "$logfile" ]]; then
            tail -50 "$logfile"
        fi
        ;;
    4)
        echo ""
        echo "📥 更新部署脚本..."
        curl -fsSL https://raw.githubusercontent.com/ego520/auto_gensyn/main/install_gensyn.sh -o /tmp/update.sh
        bash /tmp/update.sh
        ;;
    5)
        echo ""
        echo "🔄 重置认证信息..."
        rm -f ~/.ego_gensyn_auth ~/.ego_gensyn_permission
        echo "✅ 认证信息已重置"
        echo "下次运行需要重新输入密码"
        ;;
    6)
        echo "👋 再见！"
        exit 0
        ;;
    *)
        echo "❌ 无效选择"
        ;;
esac

echo ""
read -n 1 -s -p "按任意键返回主菜单..."
bash "$0"
EOF
    
    chmod +x "$DESKTOP_DIR/ego_gensyn_manage.command"
    log_success "管理工具创建成功: $DESKTOP_DIR/ego_gensyn_manage.command"
}

# 完成部署
complete_deployment() {
    log_step "部署完成！"
    
    PROJECT_DIR="$HOME/ego_gensyn"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    🎉 部署成功！                          ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║                                                            ║"
    echo "║  项目目录: $PROJECT_DIR                                   ║"
    echo "║  主程序:   $PROJECT_DIR/rl-swarm/gensyn.sh                ║"
    echo "║  认证文件: ~/.ego_gensyn_auth                             ║"
    echo "║                                                            ║"
    echo "║  常用命令:                                                 ║"
    echo "║    cd $PROJECT_DIR/rl-swarm                               ║"
    echo "║    ./gensyn.sh                                            ║"
    echo "║    ./startAll.sh                                          ║"
    echo "║                                                            ║"
    
    if [[ "$OS_TYPE" == "macos" ]]; then
        echo "║  macOS 快捷方式:                                        ║"
        echo "║    • 双击桌面 ego_gensyn.command 启动                   ║"
        echo "║    • 双击桌面 ego_gensyn_manage.command 管理            ║"
        echo "║                                                            ║"
    fi
    
    echo "║  下次部署无需密码验证                                      ║"
    echo "║                                                            ║"
    echo "║  问题反馈: https://github.com/ego520/auto_gensyn/issues    ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # 询问是否立即启动
    read -p "是否立即启动 gensyn？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "启动 gensyn..."
        cd "$PROJECT_DIR/rl-swarm" && ./gensyn.sh
    else
        log_info "您可以稍后手动启动："
        echo "cd $PROJECT_DIR/rl-swarm && ./gensyn.sh"
    fi
}

# 主函数
main() {
    # 清屏
    clear
    
    # 1. 密码验证
    verify_password
    
    # 2. 检测操作系统
    detect_os
    
    # 3. 安装系统依赖
    install_dependencies
    
    # 4. 配置系统优化
    configure_system
    
    # 5. 配置 GitHub 加速
    configure_github_accelerator
    
    # 6. 显示系统信息
    show_system_info
    
    # 7. 备份现有项目
    backup_existing_project
    
    # 8. 克隆项目
    clone_project
    
    # 9. 创建桌面快捷方式 (macOS)
    create_desktop_shortcuts
    
    # 10. 完成部署
    complete_deployment
}

# 异常处理
trap 'log_error "脚本被中断"; exit 1' INT TERM

# 显示脚本信息
echo "========================================"
echo "脚本: ego520 自定义 Gensyn 部署脚本"
echo "版本: 1.0.0"
echo "仓库: https://github.com/ego520/auto_gensyn"
echo "========================================"
echo ""

# 检查是否以 root 运行
if [[ $EUID -eq 0 ]]; then
    log_warning "不建议以 root 用户运行此脚本"
    read -p "是否继续？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 启动主函数
main "$@"

# 脚本结束
log_success "脚本执行完成！"
