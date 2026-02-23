#!/bin/bash
# ==============================================================
#  PROXY SERVER INSTALLER
#  IPv4 (single) / IPv6 (up to 1000 unique exit IPs)
#  Optional web panel: http://IP/panel
#  Backend: 3proxy + nginx | OS: Ubuntu 20.04 / 22.04 / 24.04
# ==============================================================

echo ""
echo "  Proxy Installer: Р·Р°РїСѓСЃРє..."
echo ""

set -uo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'
NC='\033[0m'; BOLD='\033[1m'

# Paths
INSTALL_DIR="/etc/3proxy"
CONFIG_FILE="/etc/3proxy/3proxy.cfg"
LOG_DIR="/var/log/3proxy"
PROXY_LIST="/root/proxy_list.txt"
IPV6_SCRIPT="/usr/local/bin/add-proxy-ipv6.sh"
PANEL_DIR="/var/www/html/panel"
PANEL_CREDS="/root/panel_credentials.txt"

# Global vars
PROXY_TYPE=""
PROXY_PROTOCOL="socks5"
PROXY_COUNT=1
OUTPUT_FORMAT=1
WANT_PANEL="no"
START_PORT=10000
SERVER_IPV4=""
NET_INTERFACE=""
IPV6_ADDR=""
IPV6_PREFIX_LEN="64"
PANEL_USER="admin"
PANEL_PASS=""
declare -a IPV6_ADDRESSES=()
declare -a PROXY_LOGINS=()
declare -a PROXY_PASSES=()

# Utility
print_line() { echo -e "${CYAN}  в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ${NC}"; }
success()    { echo -e "${GREEN}  вњ“  $1${NC}"; }
err()        { echo -e "${RED}  вњ—  $1${NC}"; }
info()       { echo -e "${BLUE}  в„№  $1${NC}"; }
warn()       { echo -e "${YELLOW}  вљ   $1${NC}"; }
step()       { echo -e "\n${WHITE}${BOLD}  вЂє  $1${NC}"; }

gen_random() { cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "${1:-12}" | head -n 1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "\n${RED}${BOLD}  РўСЂРµР±СѓРµС‚СЃСЏ root: sudo bash install.sh${NC}\n"
        exit 1
    fi
}

check_os() {
    local ver
    ver=$(grep VERSION_ID /etc/os-release 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "")
    if ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
        warn "РЎРєСЂРёРїС‚ РѕРїС‚РёРјРёР·РёСЂРѕРІР°РЅ РґР»СЏ Ubuntu. РџСЂРѕРґРѕР»Р¶РёС‚СЊ РЅР° РґСЂСѓРіРѕР№ РћРЎ?"
        echo -ne "  (yes/no): "; read -r ans
        if [[ ! "${ans,,}" =~ ^(yes|y|РґР°)$ ]]; then exit 0; fi
    elif [[ "$ver" != "20" && "$ver" != "22" && "$ver" != "24" ]]; then
        warn "РџСЂРѕС‚РµСЃС‚РёСЂРѕРІР°РЅРѕ РЅР° Ubuntu 20/22/24. РўРµРєСѓС‰Р°СЏ: $ver. РџСЂРѕРґРѕР»Р¶РёС‚СЊ?"
        echo -ne "  (yes/no): "; read -r ans
        if [[ ! "${ans,,}" =~ ^(yes|y|РґР°)$ ]]; then exit 0; fi
    fi
}

print_banner() {
    command -v clear >/dev/null 2>&1 && clear || true
    echo -e "${CYAN}"
    echo "  в•”в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•—"
    echo "  в•‘                                                  в•‘"
    echo "  в•‘        P R O X Y   I N S T A L L E R            в•‘"
    echo "  в•‘        IPv4 / IPv6  вЂў  Ubuntu 20/22/24           в•‘"
    echo "  в•‘                                                  в•‘"
    echo "  в•љв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ќ"
    echo -e "${NC}"
}

format_name() {
    case $OUTPUT_FORMAT in
        1) echo "IP:PORT:LOGIN:PASS"  ;;
        2) echo "IP:PORT@LOGIN:PASS"  ;;
        3) echo "LOGIN:PASS@IP:PORT"  ;;
        4) echo "LOGIN:PASS:IP:PORT"  ;;
    esac
}

format_proxy() {
    local ip=$1 port=$2 login=$3 pass=$4
    case $OUTPUT_FORMAT in
        1) echo "${ip}:${port}:${login}:${pass}" ;;
        2) echo "${ip}:${port}@${login}:${pass}" ;;
        3) echo "${login}:${pass}@${ip}:${port}" ;;
        4) echo "${login}:${pass}:${ip}:${port}" ;;
    esac
}

# STEP 1: PROXY TYPE
step_proxy_type() {
    print_banner
    echo -e "  ${WHITE}${BOLD}РЁР°Рі 1 РёР· 6 вЂ” РўРёРї РїСЂРѕРєСЃРё${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}[1]${NC}  ${WHITE}${BOLD}IPv4${NC}  вЂ” РѕРґРЅР° РїСЂРѕРєСЃРё, РІС‹С…РѕРґ С‡РµСЂРµР· IPv4 СЃРµСЂРІРµСЂР°"
    echo -e "       ${YELLOW}172.233.96.133:10000:login:password${NC}\n"
    echo -e "  ${GREEN}[2]${NC}  ${WHITE}${BOLD}IPv6${NC}  вЂ” РјРЅРѕРіРѕ РїСЂРѕРєСЃРё, РєР°Р¶РґР°СЏ СЃ СѓРЅРёРєР°Р»СЊРЅС‹Рј IPv6"
    echo -e "       ${YELLOW}172.233.96.133:10001:login1:pass1  в†ђ СЂР°Р·РЅС‹Рµ РІС‹С…РѕРґРЅС‹Рµ IP${NC}"
    echo -e "       ${YELLOW}172.233.96.133:10002:login2:pass2${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Р’Р°С€ РІС‹Р±РѕСЂ (1 РёР»Рё 2): ${NC}"; read -r ch
        case $ch in
            1) PROXY_TYPE="ipv4"; break ;;
            2) PROXY_TYPE="ipv6"; break ;;
            *) err "Р’РІРµРґРёС‚Рµ 1 РёР»Рё 2" ;;
        esac
    done
}

# STEP 2: COUNT
step_proxy_count() {
    if [[ "$PROXY_TYPE" == "ipv4" ]]; then PROXY_COUNT=1; return; fi
    print_banner
    echo -e "  ${WHITE}${BOLD}РЁР°Рі 2 РёР· 6 вЂ” РљРѕР»РёС‡РµСЃС‚РІРѕ РїСЂРѕРєСЃРё${NC}\n"
    print_line; echo ""
    echo -e "  РљР°Р¶РґР°СЏ РїСЂРѕРєСЃРё РїРѕР»СѓС‡РёС‚:"
    echo -e "  ${WHITE}вЂў РЈРЅРёРєР°Р»СЊРЅС‹Р№ IPv6 РІС‹С…РѕРґРЅРѕР№ Р°РґСЂРµСЃ${NC}"
    echo -e "  ${WHITE}вЂў РЎРІРѕР№ РїРѕСЂС‚ (${START_PORT}, $((START_PORT+1)), ...)${NC}"
    echo -e "  ${WHITE}вЂў РЎРІРѕР№ Р»РѕРіРёРЅ Рё РїР°СЂРѕР»СЊ${NC}"
    echo ""; echo -e "  ${YELLOW}Р”РёР°РїР°Р·РѕРЅ: 1 вЂ“ 1000${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}РљРѕР»РёС‡РµСЃС‚РІРѕ РїСЂРѕРєСЃРё: ${NC}"; read -r cnt
        if [[ "$cnt" =~ ^[0-9]+$ ]] && (( cnt >= 1 && cnt <= 1000 )); then
            PROXY_COUNT=$cnt; break
        else
            err "Р’РІРµРґРёС‚Рµ С‡РёСЃР»Рѕ РѕС‚ 1 РґРѕ 1000"
        fi
    done
}

# STEP 3: PROTOCOL
step_protocol() {
    print_banner
    echo -e "  ${WHITE}${BOLD}РЁР°Рі 3 РёР· 6 вЂ” РџСЂРѕС‚РѕРєРѕР» РїСЂРѕРєСЃРё${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}[1]${NC}  ${WHITE}${BOLD}SOCKS5${NC}  вЂ” СѓРЅРёРІРµСЂСЃР°Р»СЊРЅС‹Р№, TCP Рё UDP"
    echo -e "       ${YELLOW}РџРѕРґС…РѕРґРёС‚ РґР»СЏ Р±СЂР°СѓР·РµСЂРѕРІ, Р±РѕС‚РѕРІ, РїР°СЂСЃРµСЂРѕРІ, РёРіСЂ${NC}\n"
    echo -e "  ${GREEN}[2]${NC}  ${WHITE}${BOLD}HTTP${NC}    вЂ” С‚РѕР»СЊРєРѕ HTTP/HTTPS С‚СЂР°С„РёРє"
    echo -e "       ${YELLOW}РџРѕРґС…РѕРґРёС‚ РґР»СЏ Р±СЂР°СѓР·РµСЂРѕРІ Рё Р±РѕР»СЊС€РёРЅСЃС‚РІР° РїСЂРѕРіСЂР°РјРј${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Р’Р°С€ РІС‹Р±РѕСЂ (1 РёР»Рё 2): ${NC}"; read -r ch
        case $ch in
            1) PROXY_PROTOCOL="socks5"; break ;;
            2) PROXY_PROTOCOL="http"; break ;;
            *) err "Р’РІРµРґРёС‚Рµ 1 РёР»Рё 2" ;;
        esac
    done
}

# STEP 4: FORMAT
step_format() {
    print_banner
    echo -e "  ${WHITE}${BOLD}РЁР°Рі 4 РёР· 6 вЂ” Р¤РѕСЂРјР°С‚ РІС‹РІРѕРґР°${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}[1]${NC}  ${WHITE}IP:PORT:LOGIN:PASS${NC}"
    echo -e "       ${YELLOW}172.233.96.133:10001:mylogin:mypassword${NC}\n"
    echo -e "  ${GREEN}[2]${NC}  ${WHITE}IP:PORT@LOGIN:PASS${NC}"
    echo -e "       ${YELLOW}172.233.96.133:10001@mylogin:mypassword${NC}\n"
    echo -e "  ${GREEN}[3]${NC}  ${WHITE}LOGIN:PASS@IP:PORT${NC}"
    echo -e "       ${YELLOW}mylogin:mypassword@172.233.96.133:10001${NC}\n"
    echo -e "  ${GREEN}[4]${NC}  ${WHITE}LOGIN:PASS:IP:PORT${NC}"
    echo -e "       ${YELLOW}mylogin:mypassword:172.233.96.133:10001${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Р’Р°С€ РІС‹Р±РѕСЂ (1/2/3/4): ${NC}"; read -r ch
        case $ch in
            1|2|3|4) OUTPUT_FORMAT=$ch; break ;;
            *) err "Р’РІРµРґРёС‚Рµ РѕС‚ 1 РґРѕ 4" ;;
        esac
    done
}

# STEP 5: PANEL
step_panel() {
    print_banner
    echo -e "  ${WHITE}${BOLD}РЁР°Рі 5 РёР· 6 вЂ” Р’РµР±-РїР°РЅРµР»СЊ${NC}\n"
    print_line; echo ""
    echo -e "  РЈСЃС‚Р°РЅРѕРІРёС‚СЊ РІРµР±-РїР°РЅРµР»СЊ РґР»СЏ РїСЂРѕСЃРјРѕС‚СЂР° РїСЂРѕРєСЃРё?"
    echo ""
    echo -e "  ${CYAN}URL:${NC}   ${WHITE}http://Р’РђРЁ_IP/panel${NC}"
    echo -e "  ${CYAN}Р’С…РѕРґ:${NC}  Р»РѕРіРёРЅ + РїР°СЂРѕР»СЊ"
    echo ""
    echo -e "  Р’РѕР·РјРѕР¶РЅРѕСЃС‚Рё:"
    echo -e "  ${WHITE}вЂў РЎРїРёСЃРѕРє РІСЃРµС… РїСЂРѕРєСЃРё${NC}"
    echo -e "  ${WHITE}вЂў РџРѕРёСЃРє Рё С„РёР»СЊС‚СЂ${NC}"
    echo -e "  ${WHITE}вЂў РЎРєРѕРїРёСЂРѕРІР°С‚СЊ / РЎРєР°С‡Р°С‚СЊ${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}РЈСЃС‚Р°РЅРѕРІРёС‚СЊ РїР°РЅРµР»СЊ? (yes / no): ${NC}"; read -r ans
        case "${ans,,}" in
            yes|y|РґР°)  WANT_PANEL="yes"; break ;;
            no|n|РЅРµС‚)  WANT_PANEL="no";  break ;;
            *) err "Р’РІРµРґРёС‚Рµ yes РёР»Рё no" ;;
        esac
    done
}

# STEP 6: CONFIRM
step_confirm() {
    print_banner
    echo -e "  ${WHITE}${BOLD}РЁР°Рі 6 РёР· 6 вЂ” РџСЂРѕРІРµСЂСЊС‚Рµ РїРµСЂРµРґ СѓСЃС‚Р°РЅРѕРІРєРѕР№${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}${BOLD}вњ“  РўР Р•Р‘РћР’РђРќРРЇ:${NC}"
    echo -e "  ${WHITE}   вЂў Ubuntu 20.04 / 22.04 / 24.04 LTS${NC}"
    echo -e "  ${WHITE}   вЂў РњРёРЅРёРјСѓРј 512 MB RAM${NC}"
    echo -e "  ${WHITE}   вЂў root РґРѕСЃС‚СѓРї${NC}"
    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        echo ""
        echo -e "  ${GREEN}${BOLD}вњ“  Р”Р›РЇ IPv6:${NC}"
        echo -e "  ${WHITE}   вЂў IPv6 РІРєР»СЋС‡С‘РЅ РІ РїР°РЅРµР»Рё VPS${NC}"
        echo -e "  ${WHITE}   вЂў РџСЂРѕРІР°Р№РґРµСЂ РІС‹РґР°Р» /48 РёР»Рё /64 РїРѕРґСЃРµС‚СЊ${NC}"
        echo -e "  ${YELLOW}   вљ   Р РµРєРѕРјРµРЅРґРѕРІР°РЅРѕ: Hetzner, Vultr, DigitalOcean, Aeza${NC}"
    fi
    echo ""
    echo -e "  ${CYAN}${BOLD}вљ™  Р‘РЈР”Р•Рў РЈРЎРўРђРќРћР’Р›Р•РќРћ:${NC}"
    echo -e "  ${WHITE}   вЂў 3proxy (РёР· РёСЃС…РѕРґРЅРёРєРѕРІ)${NC}"
    echo -e "  ${WHITE}   вЂў UFW firewall${NC}"
    echo -e "  ${WHITE}   вЂў Systemd СЃРµСЂРІРёСЃ${NC}"
    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        echo -e "  ${WHITE}   вЂў IPv6 Р°РґСЂРµСЃР° + forwarding${NC}"
    fi
    if [[ "$WANT_PANEL" == "yes" ]]; then
        echo -e "  ${WHITE}   вЂў Nginx + РІРµР±-РїР°РЅРµР»СЊ${NC}"
    fi
    echo ""
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}РС‚РѕРіРѕ:${NC}"
    echo -e "  ${CYAN}  РўРёРї:        ${WHITE}$PROXY_TYPE${NC}"
    echo -e "  ${CYAN}  РџСЂРѕС‚РѕРєРѕР»:   ${WHITE}${PROXY_PROTOCOL^^}${NC}"
    echo -e "  ${CYAN}  РљРѕР»РёС‡РµСЃС‚РІРѕ: ${WHITE}$PROXY_COUNT${NC}"
    echo -e "  ${CYAN}  Р¤РѕСЂРјР°С‚:     ${WHITE}$(format_name)${NC}"
    echo -e "  ${CYAN}  РџРѕСЂС‚С‹:      ${WHITE}${START_PORT} вЂ“ $((START_PORT + PROXY_COUNT - 1))${NC}"
    echo -e "  ${CYAN}  РџР°РЅРµР»СЊ:     ${WHITE}$WANT_PANEL${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}РќР°С‡Р°С‚СЊ СѓСЃС‚Р°РЅРѕРІРєСѓ? (yes / no): ${NC}"; read -r ans
        case "${ans,,}" in
            yes|y|РґР°) break ;;
            no|n|РЅРµС‚) echo "  РћС‚РјРµРЅР°."; exit 0 ;;
            *) warn "Р’РІРµРґРёС‚Рµ yes РёР»Рё no" ;;
        esac
    done
}

# INSTALL
install_dependencies() {
    step "РћР±РЅРѕРІР»РµРЅРёРµ РїР°РєРµС‚РѕРІ..."
    apt-get update -qq
    local pkgs="build-essential curl wget tar iproute2 ufw python3 net-tools"
    if [[ "$WANT_PANEL" == "yes" ]]; then
        pkgs="$pkgs nginx apache2-utils"
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs > /dev/null 2>&1
    success "Р—Р°РІРёСЃРёРјРѕСЃС‚Рё СѓСЃС‚Р°РЅРѕРІР»РµРЅС‹"
}

install_3proxy() {
    step "Р—Р°РіСЂСѓР·РєР° 3proxy..."
    local ver
    ver=$(curl -s --max-time 10 https://api.github.com/repos/3proxy/3proxy/releases/latest \
          | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v' || true)
    if [[ -z "$ver" || "$ver" == "null" ]]; then ver="0.9.4"; fi
    info "Р’РµСЂСЃРёСЏ: $ver"

    cd /tmp
    rm -rf 3proxy-build && mkdir 3proxy-build && cd 3proxy-build
    wget -q "https://github.com/3proxy/3proxy/archive/refs/tags/${ver}.tar.gz" -O src.tar.gz \
        || { err "РћС€РёР±РєР° Р·Р°РіСЂСѓР·РєРё 3proxy"; exit 1; }
    tar -xzf src.tar.gz
    cd "3proxy-${ver}"

    step "РљРѕРјРїРёР»СЏС†РёСЏ..."
    make -f Makefile.Linux > /dev/null 2>&1
    mkdir -p "$INSTALL_DIR"
    cp src/3proxy "$INSTALL_DIR/3proxy"
    chmod +x "$INSTALL_DIR/3proxy"
    mkdir -p "$LOG_DIR"
    success "3proxy v${ver} СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
}

detect_network() {
    step "РћРїСЂРµРґРµР»РµРЅРёРµ СЃРµС‚РµРІС‹С… РїР°СЂР°РјРµС‚СЂРѕРІ..."
    SERVER_IPV4=$(curl -s -4 --max-time 8 ifconfig.me \
                  || ip -4 addr show | grep 'global' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    info "IPv4: $SERVER_IPV4"

    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        local ipv6_line
        ipv6_line=$(ip -6 addr show | grep 'scope global' | grep -v 'temporary' | head -1)
        if [[ -z "$ipv6_line" ]]; then
            err "Р“Р»РѕР±Р°Р»СЊРЅС‹Р№ IPv6 РЅРµ РЅР°Р№РґРµРЅ. Р’РєР»СЋС‡РёС‚Рµ IPv6 РІ РїР°РЅРµР»Рё VPS."
            exit 1
        fi
        local ipv6_cidr
        ipv6_cidr=$(echo "$ipv6_line" | awk '{print $2}')
        IPV6_ADDR=$(echo "$ipv6_cidr" | cut -d'/' -f1)
        IPV6_PREFIX_LEN=$(echo "$ipv6_cidr" | cut -d'/' -f2)
        NET_INTERFACE=$(ip -6 route show default | awk '{print $5}' | head -1)
        if [[ -z "$NET_INTERFACE" ]]; then
            NET_INTERFACE=$(ip link show | grep -v 'lo' | grep 'state UP' | awk -F': ' '{print $2}' | head -1)
        fi
        info "РРЅС‚РµСЂС„РµР№СЃ: $NET_INTERFACE"
        info "IPv6: ${IPV6_ADDR}/${IPV6_PREFIX_LEN}"
    fi
    success "РЎРµС‚РµРІС‹Рµ РїР°СЂР°РјРµС‚СЂС‹ РѕРїСЂРµРґРµР»РµРЅС‹"
}

generate_ipv6() {
    step "Р“РµРЅРµСЂР°С†РёСЏ $PROXY_COUNT IPv6 Р°РґСЂРµСЃРѕРІ..."
    local prefix64
    prefix64=$(python3 - <<PYEOF
import ipaddress, sys
try:
    net = ipaddress.IPv6Network("${IPV6_ADDR}/64", strict=False)
    print(str(net.network_address))
except:
    sys.exit(1)
PYEOF
    )
    if [[ -z "$prefix64" ]]; then
        err "РќРµ СѓРґР°Р»РѕСЃСЊ РѕРїСЂРµРґРµР»РёС‚СЊ /64 РёР· ${IPV6_ADDR}"
        exit 1
    fi
    info "РџРѕРґСЃРµС‚СЊ /64: ${prefix64}/64"

    declare -A seen=()
    local i=0
    while (( i < PROXY_COUNT )); do
        local addr
        addr=$(python3 - <<PYEOF
import ipaddress, random
base = ipaddress.IPv6Network("${prefix64}/64", strict=False)
host_int = random.randint(2, (2**64) - 2)
print(str(base.network_address + host_int))
PYEOF
        )
        if [[ -z "${seen[$addr]:-}" ]]; then
            seen[$addr]=1
            IPV6_ADDRESSES+=("$addr")
            (( i++ ))
        fi
    done
    success "РЎРіРµРЅРµСЂРёСЂРѕРІР°РЅРѕ ${#IPV6_ADDRESSES[@]} Р°РґСЂРµСЃРѕРІ"
}

add_ipv6_addresses() {
    step "Р”РѕР±Р°РІР»РµРЅРёРµ IPv6 Р°РґСЂРµСЃРѕРІ РЅР° $NET_INTERFACE..."
    cat > "$IPV6_SCRIPT" <<'SCRIPT'
#!/bin/bash
SCRIPT
    local count=0
    for addr in "${IPV6_ADDRESSES[@]}"; do
        echo "ip -6 addr add ${addr}/64 dev $NET_INTERFACE 2>/dev/null || true" >> "$IPV6_SCRIPT"
        ip -6 addr add "${addr}/64" dev "$NET_INTERFACE" 2>/dev/null || true
        (( count++ ))
        if (( count % 100 == 0 )); then
            info "Р”РѕР±Р°РІР»РµРЅРѕ $count / $PROXY_COUNT..."
        fi
    done
    chmod +x "$IPV6_SCRIPT"

    cat > /etc/systemd/system/add-proxy-ipv6.service <<EOF
[Unit]
Description=Add IPv6 addresses for proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$IPV6_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable add-proxy-ipv6.service > /dev/null 2>&1
    success "IPv6 Р°РґСЂРµСЃР° РґРѕР±Р°РІР»РµРЅС‹"
}

configure_ipv6_kernel() {
    step "Р’РєР»СЋС‡РµРЅРёРµ IPv6 forwarding..."
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null 2>&1
    sysctl -w net.ipv6.conf.all.proxy_ndp=1 > /dev/null 2>&1
    sysctl -w net.ipv6.conf.default.forwarding=1 > /dev/null 2>&1
    grep -q "net.ipv6.conf.all.forwarding" /etc/sysctl.conf || \
    cat >> /etc/sysctl.conf <<'EOF'

net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.proxy_ndp=1
EOF
    sysctl -p > /dev/null 2>&1 || true
    success "IPv6 forwarding РІРєР»СЋС‡С‘РЅ"
}

configure_3proxy() {
    step "Р“РµРЅРµСЂР°С†РёСЏ РєРѕРЅС„РёРіСѓСЂР°С†РёРё ($PROXY_COUNT РїСЂРѕРєСЃРё)..."

    cat > "$CONFIG_FILE" <<EOF
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
daemon
pidfile /var/run/3proxy.pid
log $LOG_DIR/3proxy.log D
logformat "- +_L%t.%.  %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30
maxconn 200

auth strong

EOF

    PROXY_LOGINS=(); PROXY_PASSES=()
    for (( i=0; i<PROXY_COUNT; i++ )); do
        local login pass
        login="u$(printf '%04d' $((i+1)))_$(gen_random 6)"
        pass=$(gen_random 14)
        PROXY_LOGINS+=("$login")
        PROXY_PASSES+=("$pass")
        echo "users ${login}:CL:${pass}" >> "$CONFIG_FILE"
    done

    echo "" >> "$CONFIG_FILE"
    for (( i=0; i<PROXY_COUNT; i++ )); do
        local port=$((START_PORT + i))
        echo "allow ${PROXY_LOGINS[$i]}" >> "$CONFIG_FILE"
        if [[ "$PROXY_TYPE" == "ipv6" ]]; then
            echo "external ${IPV6_ADDRESSES[$i]}" >> "$CONFIG_FILE"
        fi
        if [[ "$PROXY_PROTOCOL" == "http" ]]; then
            echo "proxy -i0.0.0.0 -p${port}" >> "$CONFIG_FILE"
        else
            echo "socks -i0.0.0.0 -p${port}" >> "$CONFIG_FILE"
        fi
        echo "flush" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
    done

    success "РљРѕРЅС„РёРіСѓСЂР°С†РёСЏ Р·Р°РїРёСЃР°РЅР°"

    step "РЎРѕС…СЂР°РЅРµРЅРёРµ СЃРїРёСЃРєР° РїСЂРѕРєСЃРё..."
    > "$PROXY_LIST"
    for (( i=0; i<PROXY_COUNT; i++ )); do
        format_proxy "$SERVER_IPV4" "$((START_PORT+i))" "${PROXY_LOGINS[$i]}" "${PROXY_PASSES[$i]}" >> "$PROXY_LIST"
    done
    success "РЎРїРёСЃРѕРє: $PROXY_LIST"
}

setup_3proxy_service() {
    step "Systemd СЃРµСЂРІРёСЃ 3proxy..."
    local after="network-online.target"
    local wants="network-online.target"
    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        after="$after add-proxy-ipv6.service"
        wants="$wants add-proxy-ipv6.service"
    fi

    cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=$after
Wants=$wants

[Service]
Type=forking
PIDFile=/var/run/3proxy.pid
ExecStart=$INSTALL_DIR/3proxy $CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable 3proxy > /dev/null 2>&1
    systemctl restart 3proxy || true
    sleep 3
    if systemctl is-active --quiet 3proxy; then
        success "3proxy Р·Р°РїСѓС‰РµРЅ"
    else
        warn "3proxy РЅРµ Р·Р°РїСѓСЃС‚РёР»СЃСЏ. РџСЂРѕРІРµСЂСЊС‚Рµ: journalctl -u 3proxy -n 30"
    fi
}

setup_firewall() {
    step "РќР°СЃС‚СЂРѕР№РєР° UFW..."
    sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw 2>/dev/null || true
    ufw --force enable > /dev/null 2>&1
    ufw allow OpenSSH > /dev/null 2>&1
    if [[ "$WANT_PANEL" == "yes" ]]; then
        ufw allow 80/tcp > /dev/null 2>&1
    fi

    local end_port=$((START_PORT + PROXY_COUNT - 1))
    if (( PROXY_COUNT == 1 )); then
        ufw allow "${START_PORT}/tcp" > /dev/null 2>&1
    else
        ufw allow "${START_PORT}:${end_port}/tcp" > /dev/null 2>&1
    fi
    ufw reload > /dev/null 2>&1
    success "Firewall РЅР°СЃС‚СЂРѕРµРЅ"
}

generate_panel_html() {
    local ip=$1 ptype=$2 pproto=$3 pcount=$4 fmt=$5

    mkdir -p "$PANEL_DIR"

    local js_list=""
    while IFS= read -r line; do
        js_list+="\"$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')\","$'\n'
    done < "$PROXY_LIST"

    cat > "${PANEL_DIR}/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Proxy Panel</title>
<script src="https://cdn.tailwindcss.com"></script>
<style>
::-webkit-scrollbar{width:6px}
::-webkit-scrollbar-track{background:#1e293b}
::-webkit-scrollbar-thumb{background:#475569;border-radius:3px}
.proxy-line{font-family:monospace;font-size:13px}
</style>
</head>
<body class="bg-slate-900 text-slate-100 min-h-screen">
<div class="bg-slate-800 border-b border-slate-700 px-6 py-4 flex items-center justify-between">
  <div class="flex items-center gap-3">
    <div class="w-8 h-8 bg-cyan-500 rounded-lg flex items-center justify-center text-slate-900 font-bold">P</div>
    <div><div class="font-semibold">Proxy Panel</div><div class="text-xs text-slate-400">${ip}</div></div>
  </div>
  <div class="flex items-center gap-2">
    <span class="px-2 py-1 bg-purple-500/20 text-purple-300 rounded text-xs">${ptype^^} ${pproto^^}</span>
    <span class="px-2 py-1 bg-slate-700 rounded text-xs">${pcount} РїСЂРѕРєСЃРё</span>
  </div>
</div>
<div class="px-6 py-5 grid grid-cols-2 md:grid-cols-4 gap-4">
  <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
    <div class="text-xs text-slate-400 mb-1">РЎРµСЂРІРµСЂ</div>
    <div class="font-mono text-sm text-cyan-400">${ip}</div>
  </div>
  <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
    <div class="text-xs text-slate-400 mb-1">РўРёРї</div>
    <div class="font-semibold">${ptype^^} ${pproto^^}</div>
  </div>
  <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
    <div class="text-xs text-slate-400 mb-1">РљРѕР»РёС‡РµСЃС‚РІРѕ</div>
    <div class="font-semibold">${pcount}</div>
  </div>
  <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
    <div class="text-xs text-slate-400 mb-1">Р¤РѕСЂРјР°С‚</div>
    <div class="text-xs font-mono">${fmt}</div>
  </div>
</div>
<div class="px-6 pb-4 flex gap-3">
  <input id="searchInput" type="text" placeholder="РџРѕРёСЃРє..."
    class="flex-1 bg-slate-800 border border-slate-600 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-cyan-500"
    oninput="filterProxies()">
  <button onclick="copyAll()" class="px-4 py-2 bg-cyan-600 hover:bg-cyan-500 rounded-lg text-sm font-medium">РЎРєРѕРїРёСЂРѕРІР°С‚СЊ</button>
  <button onclick="downloadTxt()" class="px-4 py-2 bg-slate-700 hover:bg-slate-600 rounded-lg text-sm font-medium">РЎРєР°С‡Р°С‚СЊ</button>
</div>
<div class="px-6 pb-8">
  <div class="bg-slate-800 border border-slate-700 rounded-xl overflow-hidden">
    <div class="px-4 py-2 border-b border-slate-700 flex justify-between">
      <span class="text-xs text-slate-400">РЎРїРёСЃРѕРє РїСЂРѕРєСЃРё</span>
      <span id="visibleCount" class="text-xs text-slate-500">${pcount}</span>
    </div>
    <div id="proxyList" class="divide-y divide-slate-700/50 max-h-[60vh] overflow-y-auto"></div>
  </div>
</div>
<script>
const proxies = [${js_list}];
let filtered = [...proxies];
function renderList(list) {
  const c = document.getElementById('proxyList');
  if (!list.length) { c.innerHTML = '<div class="px-4 py-8 text-center text-slate-500">РџСѓСЃС‚Рѕ</div>'; return; }
  c.innerHTML = list.map((p,i) => '<div class="px-4 py-2 hover:bg-slate-700/40 flex justify-between"><span class="proxy-line">'+p+'</span><button onclick="navigator.clipboard.writeText(\\''+p.replace(/'/g,"\\'")+'\\')" class="text-slate-400 hover:text-cyan-400 text-xs">copy</button></div>').join('');
}
function filterProxies() {
  const q = document.getElementById('searchInput').value.toLowerCase();
  filtered = q ? proxies.filter(p => p.toLowerCase().includes(q)) : [...proxies];
  document.getElementById('visibleCount').textContent = filtered.length;
  renderList(filtered);
}
function copyAll() { navigator.clipboard.writeText(filtered.join('\\n')); }
function downloadTxt() {
  const a = document.createElement('a');
  a.href = 'data:text/plain;charset=utf-8,' + encodeURIComponent(filtered.join('\\n'));
  a.download = 'proxies.txt'; a.click();
}
renderList(proxies);
</script>
</body>
</html>
HTMLEOF
}

setup_web_panel() {
    step "РќР°СЃС‚СЂРѕР№РєР° РІРµР±-РїР°РЅРµР»Рё..."
    PANEL_PASS=$(gen_random 16)

    generate_panel_html "$SERVER_IPV4" "$PROXY_TYPE" "$PROXY_PROTOCOL" "$PROXY_COUNT" "$(format_name)"

    cat > /etc/nginx/sites-available/proxy-panel <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    location /panel/ {
        alias /var/www/html/panel/;
        index index.html;
        auth_basic "Proxy Panel";
        auth_basic_user_file /etc/nginx/.htpasswd-panel;
    }
    location /panel { return 301 /panel/; }
    location / { return 301 /panel/; }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/proxy-panel /etc/nginx/sites-enabled/proxy-panel
    htpasswd -bc /etc/nginx/.htpasswd-panel "$PANEL_USER" "$PANEL_PASS" > /dev/null 2>&1

    cat > "$PANEL_CREDS" <<EOF
URL:      http://${SERVER_IPV4}/panel
Р›РѕРіРёРЅ:    ${PANEL_USER}
РџР°СЂРѕР»СЊ:   ${PANEL_PASS}
EOF
    chmod 600 "$PANEL_CREDS"

    nginx -t > /dev/null 2>&1 && systemctl restart nginx
    systemctl enable nginx > /dev/null 2>&1
    success "Р’РµР±-РїР°РЅРµР»СЊ: http://${SERVER_IPV4}/panel"
}

print_results() {
    command -v clear >/dev/null 2>&1 && clear || true
    echo -e "${GREEN}"
    echo "  в•”в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•—"
    echo "  в•‘                                                  в•‘"
    echo "  в•‘       вњ“   РЈРЎРўРђРќРћР’РљРђ Р—РђР’Р•Р РЁР•РќРђ РЈРЎРџР•РЁРќРћ!           в•‘"
    echo "  в•‘                                                  в•‘"
    echo "  в•љв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ќ"
    echo -e "${NC}"
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}РџР°СЂР°РјРµС‚СЂС‹:${NC}"
    echo -e "  ${CYAN}  РўРёРї:        ${WHITE}$PROXY_TYPE${NC}"
    echo -e "  ${CYAN}  РџСЂРѕС‚РѕРєРѕР»:   ${WHITE}${PROXY_PROTOCOL^^}${NC}"
    echo -e "  ${CYAN}  РљРѕР»РёС‡РµСЃС‚РІРѕ: ${WHITE}$PROXY_COUNT${NC}"
    echo -e "  ${CYAN}  Р¤РѕСЂРјР°С‚:     ${WHITE}$(format_name)${NC}"
    echo -e "  ${CYAN}  РџРѕСЂС‚С‹:      ${WHITE}${START_PORT} вЂ“ $((START_PORT + PROXY_COUNT - 1))${NC}"
    echo ""

    if [[ "$WANT_PANEL" == "yes" ]]; then
        echo -e "  ${CYAN}${BOLD}  Р’РµР±-РїР°РЅРµР»СЊ:${NC}"
        echo -e "  ${WHITE}  URL:     ${GREEN}http://${SERVER_IPV4}/panel${NC}"
        echo -e "  ${WHITE}  Р›РѕРіРёРЅ:   ${GREEN}${PANEL_USER}${NC}"
        echo -e "  ${WHITE}  РџР°СЂРѕР»СЊ:  ${GREEN}${PANEL_PASS}${NC}"
        echo ""
    fi

    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}РџРµСЂРІС‹Рµ РїСЂРѕРєСЃРё:${NC}"; echo ""
    local shown=0
    while IFS= read -r line && (( shown < 10 )); do
        echo -e "  ${GREEN}$line${NC}"; (( shown++ ))
    done < "$PROXY_LIST"
    if (( PROXY_COUNT > 10 )); then
        echo -e "\n  ${YELLOW}  ... Рё РµС‰С‘ $((PROXY_COUNT - 10)) РІ С„Р°Р№Р»Рµ${NC}"
    fi
    echo ""
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}РљРѕРјР°РЅРґС‹:${NC}"
    echo -e "  ${CYAN}  cat $PROXY_LIST${NC}         вЂ” СЃРїРёСЃРѕРє РїСЂРѕРєСЃРё"
    echo -e "  ${CYAN}  systemctl status 3proxy${NC}  вЂ” СЃС‚Р°С‚СѓСЃ"
    echo -e "  ${CYAN}  systemctl restart 3proxy${NC} вЂ” РїРµСЂРµР·Р°РїСѓСЃРє"
    echo ""; print_line; echo ""
}

main() {
    check_root
    check_os

    step_proxy_type
    step_proxy_count
    step_protocol
    step_format
    step_panel
    step_confirm

    print_banner
    echo -e "  ${WHITE}${BOLD}РЈСЃС‚Р°РЅРѕРІРєР°...${NC}\n"

    install_dependencies
    install_3proxy
    detect_network

    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        generate_ipv6
        add_ipv6_addresses
        configure_ipv6_kernel
    fi

    configure_3proxy
    setup_firewall
    setup_3proxy_service

    if [[ "$WANT_PANEL" == "yes" ]]; then
        setup_web_panel
    fi

    print_results
}

main "$@"
