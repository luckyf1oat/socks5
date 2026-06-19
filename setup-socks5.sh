#!/bin/bash
# ============================================================
# One-Click SOCKS5 Proxy Setup Script (Dante)
# Supports: Debian/Ubuntu, Alpine, CentOS/RHEL/Fedora
# ============================================================
set -e

# ==================== Color Definitions =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ==================== Global Variables ======================
SOCKS_USER=""
SOCKS_PASS=""
SOCKS_PORT=""
MAIN_IF=""
CONFIG_FILE=""
SERVICE_NAME=""
HAS_IPV6=false
IPV4_ADDR=""
IPV6_ADDR=""
COUNTRY=""
ASN=""
ORG=""
RESULT_FILE=""

# ==================== Helper Functions ======================

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     One-Click SOCKS5 Proxy (Dante)      ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Generate random string: 6 chars (A-Z, a-z, 0-9, symbols)
gen_random_6() {
    local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*_'
    local result=""
    local len=${#chars}
    # Use /dev/urandom with a deterministic approach that works across all Linux
    for i in {1..6}; do
        local idx
        idx=$(od -An -N2 -i /dev/urandom | awk '{print $1}')
        idx=$(( idx % len ))
        if [ $idx -lt 0 ]; then idx=$(( -idx )); fi
        result="${result}${chars:idx:1}"
    done
    echo "$result"
}

# ==================== OS Detection ==========================

detect_os() {
    log_info "检测操作系统..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    elif [ -f /etc/alpine-release ]; then
        OS_ID="alpine"
        OS_VERSION=$(cat /etc/alpine-release)
    elif [ -f /etc/centos-release ]; then
        OS_ID="centos"
        OS_VERSION=$(rpm -q --qf "%{VERSION}" centos-release 2>/dev/null || echo "7")
    elif [ -f /etc/redhat-release ]; then
        OS_ID="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    else
        log_error "无法识别的操作系统"
        exit 1
    fi
    
    # Normalize OS ID
    case "$OS_ID" in
        debian|ubuntu|raspbian)
            PKG_MGR="apt-get"
            PACKAGE_NAME="dante-server"
            CONFIG_FILE="/etc/danted.conf"
            SERVICE_NAME="danted"
            PASSWD_FILE="/etc/danted.passwd"
            ;;
        alpine)
            PKG_MGR="apk"
            PACKAGE_NAME="dante-server"
            CONFIG_FILE="/etc/dante/sockd.conf"
            SERVICE_NAME="sockd"
            PASSWD_FILE="/etc/danted.passwd"
            ;;
        centos|rhel|fedora|rocky|almalinux|ol|amzn)
            PKG_MGR="yum"
            PACKAGE_NAME="dante-server"
            CONFIG_FILE="/etc/sockd.conf"
            SERVICE_NAME="sockd"
            PASSWD_FILE="/etc/sockd.passwd"
            # Use dnf for newer systems
            if command -v dnf &>/dev/null; then
                PKG_MGR="dnf"
            fi
            ;;
        *)
            log_error "不支持的操作系统: $OS_ID"
            exit 1
            ;;
    esac
    
    echo -e "  操作系统: ${CYAN}$OS_ID${NC} ${OS_VERSION}"
    echo -e "  包管理器: ${CYAN}$PKG_MGR${NC}"
    echo -e "  服务名称: ${CYAN}$SERVICE_NAME${NC}"
    echo -e "  配置文件: ${CYAN}$CONFIG_FILE${NC}"
}

# ==================== Install Dependencies ==================

install_deps() {
    log_info "安装依赖..."
    
    case "$PKG_MGR" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq curl dante-server 2>&1 | tail -5
            ;;
        apk)
            # Enable community repo if needed
            if ! grep -q 'community' /etc/apk/repositories 2>/dev/null; then
                echo "http://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/community" >> /etc/apk/repositories
            fi
            apk update -q
            apk add --no-cache curl dante-server 2>&1 | tail -5
            ;;
        yum|dnf)
            # Install EPEL for CentOS/RHEL
            if [[ "$OS_ID" =~ ^(centos|rhel|rocky|almalinux|ol)$ ]]; then
                if ! rpm -q epel-release &>/dev/null; then
                    $PKG_MGR install -y epel-release 2>&1 | tail -3
                fi
            fi
            $PKG_MGR install -y curl dante-server 2>&1 | tail -5
            ;;
    esac
    
    # Verify dante-server installed
    if ! command -v sockd &>/dev/null && ! command -v danted &>/dev/null; then
        log_error "Dante 安装失败"
        exit 1
    fi
    
    log_info "依赖安装完成"
}

# ==================== Generate Credentials ==================

gen_creds() {
    log_info "生成随机凭证..."
    
    SOCKS_USER=$(gen_random_6)
    SOCKS_PASS=$(gen_random_6)
    SOCKS_PORT=$(( RANDOM % 55536 + 10000 ))  # 10000-65535
    
    echo -e "  用户名: ${CYAN}$SOCKS_USER${NC}"
    echo -e "  密码:   ${CYAN}$SOCKS_PASS${NC}"
    echo -e "  端口:   ${CYAN}$SOCKS_PORT${NC}"
}

# ==================== Network Detection =====================

detect_network() {
    log_info "检测网络接口..."
    
    # Detect main network interface
    MAIN_IF=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
    if [ -z "$MAIN_IF" ]; then
        MAIN_IF=$(ip -o link show 2>/dev/null | grep -v "lo:" | awk -F': ' '{print $2}' | head -1)
    fi
    if [ -z "$MAIN_IF" ]; then
        MAIN_IF="eth0"
        log_warn "无法检测网卡，使用默认: eth0"
    fi
    
    echo -e "  主网卡: ${CYAN}$MAIN_IF${NC}"
    
    # Check IPv6 availability
    if ip -6 addr show scope global 2>/dev/null | grep -q inet6; then
        HAS_IPV6=true
        echo -e "  IPv6:   ${GREEN}可用${NC}"
    else
        HAS_IPV6=false
        echo -e "  IPv6:   ${YELLOW}不可用${NC}"
    fi
}

# ==================== Configure Dante =======================

config_dante() {
    log_info "配置 Dante..."
    
    # Create config directory for Alpine
    if [ "$OS_ID" = "alpine" ]; then
        mkdir -p /etc/dante
    fi
    
    # Write Dante configuration
    if [ "$HAS_IPV6" = true ]; then
        cat > "$CONFIG_FILE" << EOF
# Dante SOCKS5 Proxy Configuration
# Generated by setup-socks5.sh

logoutput: syslog

internal: 0.0.0.0 port = $SOCKS_PORT
internal: :: port = $SOCKS_PORT

external: $MAIN_IF

socksmethod: username
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

client pass {
    from: ::/0 to: ::/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
    socksmethod: username
}

socks pass {
    from: ::/0 to: ::/0
    log: error
    socksmethod: username
}
EOF
    else
        cat > "$CONFIG_FILE" << EOF
# Dante SOCKS5 Proxy Configuration
# Generated by setup-socks5.sh

logoutput: syslog

internal: 0.0.0.0 port = $SOCKS_PORT
external: $MAIN_IF

socksmethod: username
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
    socksmethod: username
}
EOF
    fi
    
    chmod 644 "$CONFIG_FILE"
    
    # Create passwd file
    echo "${SOCKS_USER}:${SOCKS_PASS}" > "$PASSWD_FILE"
    chmod 600 "$PASSWD_FILE"
    
    log_info "Dante 配置完成"
    echo -e "  配置: ${CYAN}$CONFIG_FILE${NC}"
    echo -e "  密码文件: ${CYAN}$PASSWD_FILE${NC}"
}

# ==================== Configure Firewall ====================

config_firewall() {
    log_info "配置防火墙..."
    
    # UFW
    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            ufw allow "$SOCKS_PORT"/tcp &>/dev/null || true
            echo -e "  UFW: ${GREEN}已开放 $SOCKS_PORT/tcp${NC}"
        else
            echo -e "  UFW: ${YELLOW}未启用，跳过${NC}"
        fi
    fi
    
    # firewalld
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="$SOCKS_PORT"/tcp &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
        echo -e "  firewalld: ${GREEN}已开放 $SOCKS_PORT/tcp${NC}"
    fi
    
    # iptables (fallback for any system)
    if command -v iptables &>/dev/null; then
        if ! iptables -L INPUT -n 2>/dev/null | grep -q "$SOCKS_PORT"; then
            iptables -I INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null || true
            echo -e "  iptables: ${GREEN}已开放 $SOCKS_PORT/tcp${NC}"
        else
            echo -e "  iptables: ${GREEN}规则已存在${NC}"
        fi
    fi
}

# ==================== Start Service =========================

start_service() {
    log_info "启动 Dante 服务..."
    
    # Stop any existing instance first
    if command -v systemctl &>/dev/null && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    
    if command -v rc-service &>/dev/null && rc-service "$SERVICE_NAME" status 2>/dev/null | grep -q "started"; then
        rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    fi
    
    # Enable and start (systemd)
    if command -v systemctl &>/dev/null; then
        systemctl enable "$SERVICE_NAME" 2>/dev/null || true
        systemctl restart "$SERVICE_NAME" 2>/dev/null || {
            # If service fail, try direct start
            log_warn "systemctl 启动失败，尝试直接启动..."
            sockd -f "$CONFIG_FILE" -p "$PASSWD_FILE" -D &
            sleep 2
        }
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "  状态: ${GREEN}运行中 (systemd)${NC}"
        else
            echo -e "  状态: ${YELLOW}已手动启动${NC}"
        fi
    # OpenRC (Alpine)
    elif command -v rc-update &>/dev/null; then
        rc-update add "$SERVICE_NAME" default 2>/dev/null || true
        rc-service "$SERVICE_NAME" restart 2>/dev/null || {
            log_warn "rc-service 启动失败，尝试直接启动..."
            sockd -f "$CONFIG_FILE" -p "$PASSWD_FILE" -D &
            sleep 2
        }
        if rc-service "$SERVICE_NAME" status 2>/dev/null | grep -q "started"; then
            echo -e "  状态: ${GREEN}运行中 (OpenRC)${NC}"
        else
            echo -e "  状态: ${YELLOW}已手动启动${NC}"
        fi
    else
        # Direct start
        sockd -f "$CONFIG_FILE" -p "$PASSWD_FILE" -D &
        sleep 2
        echo -e "  状态: ${YELLOW}已直接启动${NC}"
    fi
    
    # Verify port is listening
    sleep 1
    if ss -tlnp 2>/dev/null | grep -q ":$SOCKS_PORT " || netstat -tlnp 2>/dev/null | grep -q ":$SOCKS_PORT "; then
        echo -e "  端口: ${GREEN}$SOCKS_PORT 正在监听${NC}"
    else
        log_warn "端口 $SOCKS_PORT 未检测到监听，请检查 Dante 日志"
    fi
}

# ==================== IP Detection ==========================

get_ipv4() {
    local ip=""
    local sources=(
        "https://ifconfig.me"
        "https://ip.sb"
        "https://icanhazip.com"
        "https://api.ipify.org"
        "https://checkip.amazonaws.com"
    )
    
    for src in "${sources[@]}"; do
        ip=$(curl -4 -s --max-time 8 "$src" 2>/dev/null)
        if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    # Fallback: try to detect from ip command
    ip=$(ip -4 addr show scope global 2>/dev/null | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}' | grep -v '^10\.\|^172\.1[6-9]\|^172\.2[0-9]\|^172\.3[0-1]\|^192\.168\.\|^127\.' | head -1)
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

get_ipv6() {
    local ip=""
    local sources=(
        "https://ifconfig.me"
        "https://ip.sb"
        "https://icanhazip.com"
        "https://api6.ipify.org"
    )
    
    for src in "${sources[@]}"; do
        ip=$(curl -6 -s --max-time 8 "$src" 2>/dev/null)
        if [[ -n "$ip" && "$ip" =~ : ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    # Fallback: try to detect from ip command (non-link-local, non-ULA global address)
    ip=$(ip -6 addr show scope global 2>/dev/null | grep -oE 'inet6 [0-9a-fA-F:]+' | awk '{print $2}' | grep -v '^fe80:' | head -1)
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

detect_ips() {
    log_info "检测公网 IP 地址..."
    
    echo -n "  IPv4: "
    IPV4_ADDR=$(get_ipv4 || true)
    if [ -n "$IPV4_ADDR" ]; then
        echo -e "${GREEN}$IPV4_ADDR${NC}"
    else
        echo -e "${RED}未检测到${NC}"
    fi
    
    echo -n "  IPv6: "
    IPV6_ADDR=$(get_ipv6 || true)
    if [ -n "$IPV6_ADDR" ]; then
        echo -e "${GREEN}$IPV6_ADDR${NC}"
    else
        echo -e "${YELLOW}未检测到${NC}"
    fi
    
    # If neither IPv4 nor IPv6 found, error
    if [ -z "$IPV4_ADDR" ] && [ -z "$IPV6_ADDR" ]; then
        log_error "未检测到任何公网 IP 地址"
        exit 1
    fi
}

# ==================== ip-api.com Query ======================

query_ipapi() {
    local query_ip
    
    # Prefer IPv4 for geo-location query
    if [ -n "$IPV4_ADDR" ]; then
        query_ip="$IPV4_ADDR"
    elif [ -n "$IPV6_ADDR" ]; then
        query_ip="$IPV6_ADDR"
    else
        log_warn "没有 IP 地址可用于查询 ip-api.com"
        COUNTRY="Unknown"
        ASN="Unknown"
        ORG="Unknown"
        return
    fi
    
    log_info "查询 ip-api.com 信息..."
    echo -ne "  查询 IP: ${CYAN}$query_ip${NC} ... "
    
    local data
    data=$(curl -s --max-time 10 "http://ip-api.com/json/${query_ip}?fields=country,as,org" 2>/dev/null)
    
    if [ -z "$data" ]; then
        echo -e "${RED}失败${NC}"
        log_warn "ip-api.com 查询失败，使用默认命名"
        COUNTRY="Unknown"
        ASN="Unknown"
        ORG="Unknown"
        return
    fi
    
    echo -e "${GREEN}成功${NC}"
    
    # Parse JSON with grep/sed (no jq dependency)
    COUNTRY=$(echo "$data" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
    ASN=$(echo "$data" | sed -n 's/.*"as":"\([^"]*\)".*/\1/p')
    ORG=$(echo "$data" | sed -n 's/.*"org":"\([^"]*\)".*/\1/p')
    
    # Cleanup: replace spaces with underscores, remove special chars unsafe for filename
    COUNTRY="${COUNTRY:-Unknown}"
    ASN="${ASN:-Unknown}"
    ORG="${ORG:-Unknown}"
    
    echo -e "  国家: ${CYAN}$COUNTRY${NC}"
    echo -e "  ASN:  ${CYAN}$ASN${NC}"
    echo -e "  组织: ${CYAN}$ORG${NC}"
}

# ==================== Output Results ========================

sanitize_filename() {
    local str="$1"
    # Replace spaces with underscores, remove characters unsafe for filenames
    echo "$str" | sed 's/ /_/g' | tr -cd '[:alnum:]_.-'
}

output_results() {
    local country_safe asn_safe org_safe
    
    country_safe=$(sanitize_filename "$COUNTRY")
    asn_safe=$(sanitize_filename "$ASN")
    org_safe=$(sanitize_filename "$ORG")
    
    RESULT_FILE="${country_safe}_${asn_safe}_${org_safe}.txt"
    
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}${BOLD}    SOCKS5 代理搭建完成！${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # Build the result content
    local result_content=""
    result_content+="========================================\n"
    result_content+="  SOCKS5 Proxy Setup Complete\n"
    result_content+="========================================\n"
    result_content+="Server Info: ${COUNTRY} | ${ASN} | ${ORG}\n"
    result_content+="========================================\n\n"
    result_content+="[Credentials]\n"
    result_content+="  Username: ${SOCKS_USER}\n"
    result_content+="  Password: ${SOCKS_PASS}\n"
    result_content+="  Port:     ${SOCKS_PORT}\n\n"
    
    # Output IPv4
    if [ -n "$IPV4_ADDR" ]; then
        local url_v4="socks5://${SOCKS_USER}:${SOCKS_PASS}@${IPV4_ADDR}:${SOCKS_PORT}"
        local v2ray_v4="socks://${SOCKS_USER}:${SOCKS_PASS}@${IPV4_ADDR}:${SOCKS_PORT}#${country_safe}_${asn_safe}_${org_safe}_IPv4"
        
        echo -e "${GREEN}━━━ IPv4 ━━━${NC}"
        echo -e "  ${BOLD}代理地址:${NC}"
        echo -e "  ${CYAN}${url_v4}${NC}"
        echo ""
        echo -e "  ${BOLD}v2rayN 导入格式:${NC}"
        echo -e "  ${CYAN}${v2ray_v4}${NC}"
        echo ""
        
        result_content+="[IPv4]\n"
        result_content+="  Proxy URL:  ${url_v4}\n"
        result_content+="  v2rayN:     ${v2ray_v4}\n\n"
    fi
    
    # Output IPv6
    if [ -n "$IPV6_ADDR" ]; then
        local url_v6="socks5://${SOCKS_USER}:${SOCKS_PASS}@[${IPV6_ADDR}]:${SOCKS_PORT}"
        local v2ray_v6="socks://${SOCKS_USER}:${SOCKS_PASS}@[${IPV6_ADDR}]:${SOCKS_PORT}#${country_safe}_${asn_safe}_${org_safe}_IPv6"
        
        echo -e "${GREEN}━━━ IPv6 ━━━${NC}"
        echo -e "  ${BOLD}代理地址:${NC}"
        echo -e "  ${CYAN}${url_v6}${NC}"
        echo ""
        echo -e "  ${BOLD}v2rayN 导入格式:${NC}"
        echo -e "  ${CYAN}${v2ray_v6}${NC}"
        echo ""
        
        result_content+="[IPv6]\n"
        result_content+="  Proxy URL:  ${url_v6}\n"
        result_content+="  v2rayN:     ${v2ray_v6}\n\n"
    fi
    
    result_content+="========================================\n"
    result_content+="Generated by setup-socks5.sh\n"
    result_content+="========================================\n"
    
    # Save to file
    echo -e "$result_content" > "$RESULT_FILE"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${BOLD}信息已保存到:${NC} ${GREEN}$RESULT_FILE${NC}"
    echo ""
    
    # Also print the content that was saved
    echo -e "${BOLD}文件内容:${NC}"
    echo -e "$result_content"
}

# ==================== Main ==================================

main() {
    print_banner
    
    # 1. Check root
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        log_info "用法: sudo bash setup-socks5.sh"
        exit 1
    fi
    
    # 2. Detect OS
    detect_os
    
    # 3. Install dependencies
    install_deps
    
    # 4. Generate credentials
    gen_creds
    
    # 5. Detect network
    detect_network
    
    # 6. Configure Dante
    config_dante
    
    # 7. Configure firewall
    config_firewall
    
    # 8. Start service
    start_service
    
    # 9. Detect IPs
    detect_ips
    
    # 10. Query ip-api.com
    query_ipapi
    
    # 11. Output results
    output_results
    
    echo ""
    log_info "全部完成！SOCKS5 代理已就绪。"
}

# Run main
main "$@"