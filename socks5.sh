#!/bin/bash
# ============================================================
# One-Click SOCKS5 Proxy Setup Script (sing-box)
# Supports: Debian/Ubuntu, Alpine, CentOS/RHEL/Fedora
# ============================================================
set -e

# ==================== Color Definitions =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==================== Global Variables ======================
SOCKS_USER=""
SOCKS_PASS=""
SOCKS_PORT=""
IPV4_ADDR=""
IPV6_ADDR=""
COUNTRY=""
ASN=""
ORG=""
RESULT_FILE=""
SINGBOX_BIN="/usr/local/bin/sing-box"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="/etc/sing-box/config.json"
SERVICE_NAME="sing-box"

# ==================== Helper Functions ======================

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     One-Click SOCKS5 Proxy (sing-box)   ║"
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

# Generate random string: 6 chars (A-Z, a-z, 0-9)
gen_random_6() {
    local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    local result=""
    local len=${#chars}
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

    case "$OS_ID" in
        debian|ubuntu|raspbian) PKG_MGR="apt-get" ;;
        alpine) PKG_MGR="apk" ;;
        centos|rhel|fedora|rocky|almalinux|ol|amzn)
            PKG_MGR="yum"
            command -v dnf &>/dev/null && PKG_MGR="dnf"
            ;;
        *) log_error "不支持的操作系统: $OS_ID"; exit 1 ;;
    esac

    echo -e "  操作系统: ${CYAN}$OS_ID${NC} ${OS_VERSION}"
    echo -e "  包管理器: ${CYAN}$PKG_MGR${NC}"
}

# ==================== Detect Architecture ===================

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l)  ARCH="armv7" ;;
        *) log_error "不支持的架构: $arch"; exit 1 ;;
    esac
    echo -e "  架构: ${CYAN}$ARCH${NC}"
}

# ==================== Cleanup Old Config =====================

cleanup_old() {
    log_info "清理旧脚本残留..."

    # Stop old services
    if command -v systemctl &>/dev/null; then
        systemctl stop sing-box 2>/dev/null || true
        systemctl stop danted 2>/dev/null || true
        systemctl stop sockd 2>/dev/null || true
        systemctl disable sing-box 2>/dev/null || true
    fi

    if command -v rc-service &>/dev/null; then
        rc-service sing-box stop 2>/dev/null || true
        rc-service sockd stop 2>/dev/null || true
    fi
    if command -v rc-update &>/dev/null; then
        rc-update del sing-box 2>/dev/null || true
        rc-update del sockd 2>/dev/null || true
    fi

    # Kill lingering processes
    pkill -9 sing-box 2>/dev/null || true
    pkill -9 sockd 2>/dev/null || true
    pkill -9 danted 2>/dev/null || true

    # Remove old configs
    rm -rf /etc/sing-box 2>/dev/null || true
    rm -f /etc/danted.conf /etc/sockd.conf /etc/dante/sockd.conf 2>/dev/null || true
    rm -f /etc/danted.passwd /etc/sockd.passwd 2>/dev/null || true
    rm -f /etc/systemd/system/sing-box.service 2>/dev/null || true
    rm -f /etc/init.d/sing-box 2>/dev/null || true

    # Clean up old result files
    rm -f ./*_*_*.txt 2>/dev/null || true

    log_info "旧配置已清除"
}

# ==================== Install Dependencies ==================

install_deps() {
    log_info "安装依赖 (curl)..."

    case "$PKG_MGR" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq 2>&1 || log_warn "部分源更新失败，继续安装..."
            dpkg --configure -a 2>/dev/null || true
            apt-get install -y -qq curl 2>&1 | tail -3
            ;;
        apk)
            apk add --no-cache curl 2>&1 | tail -3
            ;;
        yum|dnf)
            $PKG_MGR install -y curl 2>&1 | tail -3
            ;;
    esac

    log_info "依赖安装完成"
}

# ==================== Download sing-box =====================

install_singbox() {
    log_info "下载并安装 sing-box..."

    # Get latest version tag from GitHub API
    local latest_version
    latest_version=$(curl -s --max-time 15 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
    if [ -z "$latest_version" ]; then
        latest_version="v1.10.7"
        log_warn "无法获取最新版本，使用 $latest_version"
    fi
    echo -e "  版本: ${CYAN}${latest_version}${NC}"

    # Download URL
    local dl_url="https://github.com/SagerNet/sing-box/releases/download/${latest_version}/sing-box-${latest_version#v}-linux-${ARCH}.tar.gz"
    if [ "$ARCH" = "armv7" ]; then
        dl_url="https://github.com/SagerNet/sing-box/releases/download/${latest_version}/sing-box-${latest_version#v}-linux-armv7.tar.gz"
    fi

    echo -e "  下载: ${CYAN}$dl_url${NC}"

    # Download and extract
    local tmp_dir
    tmp_dir=$(mktemp -d)
    curl -sSL --max-time 120 -o "$tmp_dir/sing-box.tar.gz" "$dl_url" || {
        log_error "下载失败"
        exit 1
    }

    tar -xzf "$tmp_dir/sing-box.tar.gz" -C "$tmp_dir"

    # Find and install the binary
    local extracted_bin
    extracted_bin=$(find "$tmp_dir" -name "sing-box" -type f | head -1)
    if [ -z "$extracted_bin" ]; then
        extracted_bin=$(find "$tmp_dir" -name "sing-box*" -type f -executable | head -1)
    fi
    if [ -z "$extracted_bin" ]; then
        log_error "未在压缩包中找到 sing-box 二进制文件"
        exit 1
    fi

    install -m 755 "$extracted_bin" "$SINGBOX_BIN"
    rm -rf "$tmp_dir"

    log_info "sing-box 安装完成"
    echo -e "  路径: ${CYAN}$SINGBOX_BIN${NC}"
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

# ==================== Configure sing-box ====================

config_singbox() {
    log_info "配置 sing-box..."

    mkdir -p "$CONFIG_DIR"

    cat > "$CONFIG_FILE" << EOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "0.0.0.0",
      "listen_port": ${SOCKS_PORT},
      "users": [
        {
          "username": "${SOCKS_USER}",
          "password": "${SOCKS_PASS}"
        }
      ]
    }
  ]
}
EOF

    chmod 644 "$CONFIG_FILE"
    log_info "sing-box 配置完成"
    echo -e "  配置: ${CYAN}$CONFIG_FILE${NC}"
}

# ==================== Configure Firewall ====================

config_firewall() {
    log_info "配置防火墙..."

    # iptables (works everywhere)
    if command -v iptables &>/dev/null; then
        if ! iptables -L INPUT -n 2>/dev/null | grep -q "$SOCKS_PORT"; then
            iptables -I INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null || true
            echo -e "  iptables: ${GREEN}已开放 $SOCKS_PORT/tcp${NC}"
        else
            echo -e "  iptables: ${GREEN}规则已存在${NC}"
        fi
    fi

    # UFW
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "$SOCKS_PORT"/tcp &>/dev/null || true
        echo -e "  UFW: ${GREEN}已开放 $SOCKS_PORT/tcp${NC}"
    fi

    # firewalld
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="$SOCKS_PORT"/tcp &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
        echo -e "  firewalld: ${GREEN}已开放 $SOCKS_PORT/tcp${NC}"
    fi
}

# ==================== Start Service =========================

start_service() {
    log_info "启动 sing-box 服务..."

    # Create systemd service
    if command -v systemctl &>/dev/null; then
        mkdir -p /etc/systemd/system
        cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=sing-box SOCKS5 Proxy
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=${SINGBOX_BIN} run -c ${CONFIG_FILE}
Restart=always
RestartSec=5
LimitNOFILE=infinity
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "$SERVICE_NAME"
        systemctl start "$SERVICE_NAME"

        sleep 2
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "  状态: ${GREEN}运行中 (systemd)${NC}"
        else
            log_warn "systemd 启动失败，尝试直接启动..."
            nohup "$SINGBOX_BIN" run -c "$CONFIG_FILE" > /dev/null 2>&1 &
            sleep 2
            echo -e "  状态: ${YELLOW}已手动启动${NC}"
        fi

    # OpenRC (Alpine)
    elif command -v rc-update &>/dev/null; then
        cat > /etc/init.d/${SERVICE_NAME} << EOF
#!/sbin/openrc-run
name="sing-box SOCKS5 Proxy"
command="${SINGBOX_BIN}"
command_args="run -c ${CONFIG_FILE}"
command_background=true
pidfile="/var/run/${SERVICE_NAME}.pid"
depend() {
    need net
}
EOF
        chmod +x /etc/init.d/${SERVICE_NAME}
        rc-update add "$SERVICE_NAME" default
        rc-service "$SERVICE_NAME" start

        sleep 2
        if rc-service "$SERVICE_NAME" status 2>/dev/null | grep -q "started"; then
            echo -e "  状态: ${GREEN}运行中 (OpenRC)${NC}"
        else
            log_warn "OpenRC 启动失败，尝试直接启动..."
            nohup "$SINGBOX_BIN" run -c "$CONFIG_FILE" > /dev/null 2>&1 &
            sleep 2
            echo -e "  状态: ${YELLOW}已手动启动${NC}"
        fi
    else
        # Direct start
        nohup "$SINGBOX_BIN" run -c "$CONFIG_FILE" > /dev/null 2>&1 &
        sleep 2
        echo -e "  状态: ${YELLOW}已直接启动${NC}"
    fi

    # Verify port is listening
    sleep 1
    if ss -tlnp 2>/dev/null | grep -q ":$SOCKS_PORT " || netstat -tlnp 2>/dev/null | grep -q ":$SOCKS_PORT "; then
        echo -e "  端口: ${GREEN}$SOCKS_PORT 正在监听${NC}"
    else
        log_warn "端口 $SOCKS_PORT 未检测到监听"
        log_info "排查命令: journalctl -u ${SERVICE_NAME} --no-pager -n 20"
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

    ip=$(ip -4 addr show scope global 2>/dev/null | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}' | grep -v '^10\.\|^172\.1[6-9]\|^172\.2[0-9]\|^172\.3[0-1]\|^192\.168\.\|^127\.' | head -1)
    [[ -n "$ip" ]] && echo "$ip" && return 0
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

    ip=$(ip -6 addr show scope global 2>/dev/null | grep -oE 'inet6 [0-9a-fA-F:]+' | awk '{print $2}' | grep -v '^fe80:' | head -1)
    [[ -n "$ip" ]] && echo "$ip" && return 0
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

    if [ -z "$IPV4_ADDR" ] && [ -z "$IPV6_ADDR" ]; then
        log_error "未检测到任何公网 IP 地址"
        exit 1
    fi
}

# ==================== ip-api.com Query ======================

query_ipapi() {
    local query_ip

    if [ -n "$IPV4_ADDR" ]; then
        query_ip="$IPV4_ADDR"
    elif [ -n "$IPV6_ADDR" ]; then
        query_ip="$IPV6_ADDR"
    else
        COUNTRY="Unknown"; ASN="Unknown"; ORG="Unknown"
        return
    fi

    log_info "查询 ip-api.com 信息..."
    echo -ne "  查询 IP: ${CYAN}$query_ip${NC} ... "

    local data
    data=$(curl -s --max-time 10 "http://ip-api.com/json/${query_ip}?fields=country,as,org" 2>/dev/null)

    if [ -z "$data" ]; then
        echo -e "${RED}失败${NC}"
        COUNTRY="Unknown"; ASN="Unknown"; ORG="Unknown"
        return
    fi

    echo -e "${GREEN}成功${NC}"

    COUNTRY=$(echo "$data" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
    ASN=$(echo "$data" | sed -n 's/.*"as":"\([^"]*\)".*/\1/p')
    ORG=$(echo "$data" | sed -n 's/.*"org":"\([^"]*\)".*/\1/p')

    COUNTRY="${COUNTRY:-Unknown}"
    ASN="${ASN:-Unknown}"
    ORG="${ORG:-Unknown}"

    echo -e "  国家: ${CYAN}$COUNTRY${NC}"
    echo -e "  ASN:  ${CYAN}$ASN${NC}"
    echo -e "  组织: ${CYAN}$ORG${NC}"
}

# ==================== Output Results ========================

sanitize_filename() {
    echo "$1" | sed 's/ /_/g' | tr -cd '[:alnum:]_.-'
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

    local result_content=""
    result_content+="========================================\n"
    result_content+="  SOCKS5 Proxy Setup Complete (sing-box)\n"
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
    result_content+="Generated by socks5.sh (sing-box)\n"
    result_content+="========================================\n"

    echo -e "$result_content" > "$RESULT_FILE"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${BOLD}信息已保存到:${NC} ${GREEN}$RESULT_FILE${NC}"
    echo ""
    echo -e "${BOLD}文件内容:${NC}"
    echo -e "$result_content"
}

# ==================== Main ==================================

main() {
    print_banner

    # 1. Check root
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        log_info "用法: sudo bash socks5.sh"
        exit 1
    fi

    # 2. Clean up old config
    cleanup_old

    # 3. Detect OS
    detect_os

    # 4. Detect architecture
    detect_arch

    # 5. Install dependencies (curl)
    install_deps

    # 6. Download and install sing-box
    install_singbox

    # 7. Generate credentials
    gen_creds

    # 8. Configure sing-box
    config_singbox

    # 9. Configure firewall
    config_firewall

    # 10. Start service
    start_service

    # 11. Detect IPs
    detect_ips

    # 12. Query ip-api.com
    query_ipapi

    # 13. Output results
    output_results

    echo ""
    log_info "全部完成！SOCKS5 代理已就绪 (sing-box)。"
}

main "$@"