#!/bin/bash
# ==============================================================
#  PROXY SERVER INSTALLER
#  IPv4 (single) / IPv6 (up to 1000 unique exit IPs)
#  Optional web panel: http://IP/panel
#  Backend: 3proxy + nginx | OS: Ubuntu 20.04 / 22.04 / 24.04
# ==============================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';  CYAN='\033[0;36m';  MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; NC='\033[0m';       BOLD='\033[1m'

# ── Paths ─────────────────────────────────────────────────────
INSTALL_DIR="/etc/3proxy"
CONFIG_FILE="/etc/3proxy/3proxy.cfg"
LOG_DIR="/var/log/3proxy"
PROXY_LIST="/root/proxy_list.txt"
IPV6_SCRIPT="/usr/local/bin/add-proxy-ipv6.sh"
PANEL_DIR="/var/www/html/panel"
PANEL_CREDS="/root/panel_credentials.txt"
UPDATE_PANEL_CMD="/usr/local/bin/proxy-panel-update"

# ── Global vars ───────────────────────────────────────────────
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

# ══════════════════════════════════════════════════════════════
# UTILITY
# ══════════════════════════════════════════════════════════════

print_line() { echo -e "${CYAN}  ══════════════════════════════════════════════════${NC}"; }
success()    { echo -e "${GREEN}  ✓  $1${NC}"; }
err()        { echo -e "${RED}  ✗  $1${NC}"; }
info()       { echo -e "${BLUE}  ℹ  $1${NC}"; }
warn()       { echo -e "${YELLOW}  ⚠  $1${NC}"; }
step()       { echo -e "\n${WHITE}${BOLD}  ›  $1${NC}"; }

gen_random() { cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "${1:-12}" | head -n 1; }

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "\n${RED}${BOLD}  Требуется root: sudo bash install.sh${NC}\n"; exit 1; }
}

check_os() {
    local ver
    ver=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release 2>/dev/null | head -1 || echo "")
    if ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
        warn "Скрипт оптимизирован для Ubuntu. Продолжить на другой ОС?"
        echo -ne "  (yes/no): "; read -r ans
        [[ "${ans,,}" =~ ^(yes|y|да)$ ]] || exit 0
    elif [[ "$ver" != "20" && "$ver" != "22" && "$ver" != "24" ]]; then
        warn "Протестировано на Ubuntu 20/22/24. Текущая: $ver. Продолжить?"
        echo -ne "  (yes/no): "; read -r ans
        [[ "${ans,,}" =~ ^(yes|y|да)$ ]] || exit 0
    fi
}

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║                                                  ║"
    echo "  ║        P R O X Y   I N S T A L L E R            ║"
    echo "  ║        IPv4 / IPv6  •  Ubuntu 20/22/24           ║"
    echo "  ║                                                  ║"
    echo "  ╚══════════════════════════════════════════════════╝"
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

# ══════════════════════════════════════════════════════════════
# WIZARD — STEP 1: PROXY TYPE
# ══════════════════════════════════════════════════════════════

step_proxy_type() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 1 из 6 — Тип прокси${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}[1]${NC}  ${WHITE}${BOLD}IPv4${NC}  — одна прокси, выход через IPv4 сервера"
    echo -e "       ${YELLOW}172.233.96.133:10000:login:password${NC}\n"
    echo -e "  ${GREEN}[2]${NC}  ${WHITE}${BOLD}IPv6${NC}  — много прокси, каждая с уникальным IPv6"
    echo -e "       ${YELLOW}172.233.96.133:10001:login1:pass1  ← разные выходные IP${NC}"
    echo -e "       ${YELLOW}172.233.96.133:10002:login2:pass2${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Ваш выбор (1 или 2): ${NC}"; read -r ch
        case $ch in
            1) PROXY_TYPE="ipv4"; break ;;
            2) PROXY_TYPE="ipv6"; break ;;
            *) err "Введите 1 или 2" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
# WIZARD — STEP 2: COUNT (IPv6 only)
# ══════════════════════════════════════════════════════════════

step_proxy_count() {
    [[ "$PROXY_TYPE" == "ipv4" ]] && { PROXY_COUNT=1; return; }
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 2 из 6 — Количество прокси${NC}\n"
    print_line; echo ""
    echo -e "  Каждая прокси получит:"
    echo -e "  ${WHITE}• Уникальный IPv6 выходной адрес${NC}"
    echo -e "  ${WHITE}• Свой порт (${START_PORT}, $((START_PORT+1)), $((START_PORT+2)), ...)${NC}"
    echo -e "  ${WHITE}• Свой логин и пароль${NC}"
    echo ""; echo -e "  ${YELLOW}Диапазон: 1 – 1000${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Количество прокси: ${NC}"; read -r cnt
        if [[ "$cnt" =~ ^[0-9]+$ ]] && (( cnt >= 1 && cnt <= 1000 )); then
            PROXY_COUNT=$cnt; break
        else
            err "Введите число от 1 до 1000"
        fi
    done
}

# ══════════════════════════════════════════════════════════════
# WIZARD — STEP 3: PROTOCOL
# ══════════════════════════════════════════════════════════════

step_protocol() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 3 из 6 — Протокол прокси${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}[1]${NC}  ${WHITE}${BOLD}SOCKS5${NC}  — универсальный, поддерживает TCP и UDP"
    echo -e "       ${YELLOW}Подходит для браузеров, ботов, парсеров, игр${NC}\n"
    echo -e "  ${GREEN}[2]${NC}  ${WHITE}${BOLD}HTTP${NC}    — только HTTP/HTTPS трафик"
    echo -e "       ${YELLOW}Подходит для браузеров и большинства программ${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Ваш выбор (1 или 2): ${NC}"; read -r ch
        case $ch in
            1) PROXY_PROTOCOL="socks5"; break ;;
            2) PROXY_PROTOCOL="http";   break ;;
            *) err "Введите 1 или 2" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
# WIZARD — STEP 4: FORMAT
# ══════════════════════════════════════════════════════════════

step_format() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 4 из 6 — Формат вывода${NC}\n"
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
        echo -ne "  ${WHITE}Ваш выбор (1/2/3/4): ${NC}"; read -r ch
        case $ch in 1|2|3|4) OUTPUT_FORMAT=$ch; break ;; *) err "Введите от 1 до 4" ;; esac
    done
}

# ══════════════════════════════════════════════════════════════
# WIZARD — STEP 5: WEB PANEL
# ══════════════════════════════════════════════════════════════

step_panel() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 5 из 6 — Веб-панель${NC}\n"
    print_line; echo ""
    echo -e "  Установить веб-панель для просмотра прокси?"
    echo ""
    echo -e "  ${CYAN}URL:${NC}   ${WHITE}http://ВАШ_IP/panel${NC}"
    echo -e "  ${CYAN}Вход:${NC}  логин + пароль (защита)"
    echo ""
    echo -e "  Возможности панели:"
    echo -e "  ${WHITE}• Список всех прокси${NC}"
    echo -e "  ${WHITE}• Поиск и фильтр${NC}"
    echo -e "  ${WHITE}• Кнопка «Скопировать всё»${NC}"
    echo -e "  ${WHITE}• Кнопка «Скачать .txt»${NC}"
    echo -e "  ${WHITE}• Инфо о сервере (IP, тип, количество)${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Установить панель? (yes / no): ${NC}"; read -r ans
        case "${ans,,}" in
            yes|y|да)  WANT_PANEL="yes"; break ;;
            no|n|нет)  WANT_PANEL="no";  break ;;
            *) err "Введите yes или no" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
# WIZARD — STEP 6: CONFIRM
# ══════════════════════════════════════════════════════════════

step_confirm() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 6 из 6 — Проверьте перед установкой${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}${BOLD}✓  ТРЕБОВАНИЯ:${NC}"
    echo -e "  ${WHITE}   • Ubuntu 20.04 / 22.04 / 24.04 LTS${NC}"
    echo -e "  ${WHITE}   • Минимум 512 MB RAM${NC}"
    echo -e "  ${WHITE}   • root доступ${NC}"
    echo -e "  ${WHITE}   • Порты не заблокированы провайдером${NC}"
    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        echo ""
        echo -e "  ${GREEN}${BOLD}✓  ДЛЯ IPv6 ДОПОЛНИТЕЛЬНО:${NC}"
        echo -e "  ${WHITE}   • IPv6 включён в панели управления VPS${NC}"
        echo -e "  ${WHITE}   • Провайдер выдал /48 или /64 подсеть${NC}"
        echo -e "  ${WHITE}   • Разрешено добавлять доп. IPv6 адреса${NC}"
        echo -e "  ${YELLOW}   ⚠  Рекомендовано: Hetzner, Vultr, DigitalOcean, Aeza${NC}"
    fi
    echo ""
    echo -e "  ${CYAN}${BOLD}⚙  БУДЕТ УСТАНОВЛЕНО:${NC}"
    echo -e "  ${WHITE}   • 3proxy (SOCKS5, из исходников)${NC}"
    echo -e "  ${WHITE}   • UFW firewall${NC}"
    echo -e "  ${WHITE}   • Systemd сервис автозапуска${NC}"
    [[ "$PROXY_TYPE" == "ipv6" ]] && echo -e "  ${WHITE}   • IPv6 адреса + sysctl forwarding${NC}"
    [[ "$WANT_PANEL" == "yes" ]] && echo -e "  ${WHITE}   • Nginx + веб-панель (защищена паролем)${NC}"
    echo ""
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}Итого:${NC}"
    echo -e "  ${CYAN}  Тип:        ${WHITE}$PROXY_TYPE${NC}"
    echo -e "  ${CYAN}  Протокол:   ${WHITE}${PROXY_PROTOCOL^^}${NC}"
    echo -e "  ${CYAN}  Количество: ${WHITE}$PROXY_COUNT${NC}"
    echo -e "  ${CYAN}  Формат:     ${WHITE}$(format_name)${NC}"
    echo -e "  ${CYAN}  Порты:      ${WHITE}${START_PORT} – $((START_PORT + PROXY_COUNT - 1))${NC}"
    echo -e "  ${CYAN}  Панель:     ${WHITE}$WANT_PANEL${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Начать установку? (yes / no): ${NC}"; read -r ans
        case "${ans,,}" in
            yes|y|да) break ;;
            no|n|нет) echo "  Отмена."; exit 0 ;;
            *) warn "Введите yes или no" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
# INSTALL DEPS + 3PROXY
# ══════════════════════════════════════════════════════════════

install_dependencies() {
    step "Обновление пакетов..."
    apt-get update -qq
    local pkgs="build-essential curl wget tar iproute2 ufw python3 net-tools"
    [[ "$WANT_PANEL" == "yes" ]] && pkgs="$pkgs nginx apache2-utils"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs > /dev/null 2>&1
    success "Зависимости установлены"
}

install_3proxy() {
    step "Загрузка 3proxy..."
    local ver
    ver=$(curl -s --max-time 10 https://api.github.com/repos/3proxy/3proxy/releases/latest \
          | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v' || true)
    [[ -z "$ver" || "$ver" == "null" ]] && ver="0.9.4"
    info "Версия: $ver"

    cd /tmp
    rm -rf 3proxy-build && mkdir 3proxy-build && cd 3proxy-build
    wget -q "https://github.com/3proxy/3proxy/archive/refs/tags/${ver}.tar.gz" -O src.tar.gz \
        || { err "Ошибка загрузки 3proxy"; exit 1; }
    tar -xzf src.tar.gz
    cd "3proxy-${ver}"

    step "Компиляция..."
    make -f Makefile.Linux > /dev/null 2>&1
    mkdir -p "$INSTALL_DIR"
    cp src/3proxy "$INSTALL_DIR/3proxy"
    chmod +x "$INSTALL_DIR/3proxy"
    mkdir -p "$LOG_DIR"
    success "3proxy v${ver} установлен"
}

# ══════════════════════════════════════════════════════════════
# NETWORK DETECTION
# ══════════════════════════════════════════════════════════════

detect_network() {
    step "Определение сетевых параметров..."
    SERVER_IPV4=$(curl -s -4 --max-time 8 ifconfig.me \
                  || ip -4 addr show | grep 'global' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    info "IPv4: $SERVER_IPV4"

    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        local ipv6_line
        ipv6_line=$(ip -6 addr show | grep 'scope global' | grep -v 'temporary' | head -1)
        if [[ -z "$ipv6_line" ]]; then
            err "Глобальный IPv6 не найден. Включите IPv6 в панели VPS."
            echo -e "\n  Проверьте: ${WHITE}ip -6 addr show${NC}\n"; exit 1
        fi
        local ipv6_cidr
        ipv6_cidr=$(echo "$ipv6_line" | awk '{print $2}')
        IPV6_ADDR=$(echo "$ipv6_cidr" | cut -d'/' -f1)
        IPV6_PREFIX_LEN=$(echo "$ipv6_cidr" | cut -d'/' -f2)
        NET_INTERFACE=$(ip -6 route show default | awk '{print $5}' | head -1)
        [[ -z "$NET_INTERFACE" ]] && \
            NET_INTERFACE=$(ip link show | grep -v 'lo' | grep 'state UP' \
                            | awk -F': ' '{print $2}' | head -1)
        info "Интерфейс: $NET_INTERFACE"
        info "IPv6: ${IPV6_ADDR}/${IPV6_PREFIX_LEN}"
    fi
    success "Сетевые параметры определены"
}

# ══════════════════════════════════════════════════════════════
# IPv6 GENERATION
# ══════════════════════════════════════════════════════════════

generate_ipv6() {
    step "Генерация $PROXY_COUNT IPv6 адресов..."
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
    [[ -z "$prefix64" ]] && { err "Не удалось определить /64 из ${IPV6_ADDR}"; exit 1; }
    info "Подсеть /64: ${prefix64}/64"

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
    success "Сгенерировано ${#IPV6_ADDRESSES[@]} адресов"
}

add_ipv6_addresses() {
    step "Добавление IPv6 адресов на $NET_INTERFACE..."
    cat > "$IPV6_SCRIPT" <<'SCRIPT'
#!/bin/bash
# Auto-generated by proxy-installer
SCRIPT
    local count=0
    for addr in "${IPV6_ADDRESSES[@]}"; do
        echo "ip -6 addr add ${addr}/64 dev $NET_INTERFACE 2>/dev/null || true" >> "$IPV6_SCRIPT"
        ip -6 addr add "${addr}/64" dev "$NET_INTERFACE" 2>/dev/null || true
        (( count++ ))
        (( count % 100 == 0 )) && info "Добавлено $count / $PROXY_COUNT..."
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
    success "IPv6 адреса добавлены (автозагрузка включена)"
}

configure_ipv6_kernel() {
    step "Включение IPv6 forwarding..."
    sysctl -w net.ipv6.conf.all.forwarding=1     > /dev/null 2>&1
    sysctl -w net.ipv6.conf.all.proxy_ndp=1      > /dev/null 2>&1
    sysctl -w net.ipv6.conf.default.forwarding=1 > /dev/null 2>&1
    grep -q "net.ipv6.conf.all.forwarding" /etc/sysctl.conf || \
    cat >> /etc/sysctl.conf <<'EOF'

# IPv6 proxy
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.proxy_ndp=1
EOF
    sysctl -p > /dev/null 2>&1 || true
    success "IPv6 forwarding включён"
}

# ══════════════════════════════════════════════════════════════
# 3PROXY CONFIG
# ══════════════════════════════════════════════════════════════

configure_3proxy() {
    step "Генерация конфигурации ($PROXY_COUNT прокси)..."

    cat > "$CONFIG_FILE" <<EOF
# Generated by proxy-installer — $(date)
# Type: $PROXY_TYPE | Count: $PROXY_COUNT

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
        [[ "$PROXY_TYPE" == "ipv6" ]] && echo "external ${IPV6_ADDRESSES[$i]}" >> "$CONFIG_FILE"
        if [[ "$PROXY_PROTOCOL" == "http" ]]; then
            echo "proxy -i0.0.0.0 -p${port}" >> "$CONFIG_FILE"
        else
            echo "socks -i0.0.0.0 -p${port}" >> "$CONFIG_FILE"
        fi
        echo "flush" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
    done

    success "Конфигурация записана"

    step "Сохранение списка прокси..."
    > "$PROXY_LIST"
    for (( i=0; i<PROXY_COUNT; i++ )); do
        format_proxy "$SERVER_IPV4" "$((START_PORT+i))" "${PROXY_LOGINS[$i]}" "${PROXY_PASSES[$i]}" >> "$PROXY_LIST"
    done
    success "Список: $PROXY_LIST"
}

# ══════════════════════════════════════════════════════════════
# 3PROXY SYSTEMD
# ══════════════════════════════════════════════════════════════

setup_3proxy_service() {
    step "Systemd сервис 3proxy..."
    local after="network-online.target"
    local wants="network-online.target"
    [[ "$PROXY_TYPE" == "ipv6" ]] && after="$after add-proxy-ipv6.service" && wants="$wants add-proxy-ipv6.service"

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
        success "3proxy запущен"
    else
        warn "3proxy не запустился. Проверьте: journalctl -u 3proxy -n 30"
    fi
}

# ══════════════════════════════════════════════════════════════
# FIREWALL
# ══════════════════════════════════════════════════════════════

setup_firewall() {
    step "Настройка UFW..."
    sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw 2>/dev/null || true
    ufw --force enable > /dev/null 2>&1
    ufw allow OpenSSH  > /dev/null 2>&1
    [[ "$WANT_PANEL" == "yes" ]] && ufw allow 80/tcp > /dev/null 2>&1

    local end_port=$((START_PORT + PROXY_COUNT - 1))
    if (( PROXY_COUNT == 1 )); then
        ufw allow "${START_PORT}/tcp" > /dev/null 2>&1
    else
        ufw allow "${START_PORT}:${end_port}/tcp" > /dev/null 2>&1
    fi
    ufw reload > /dev/null 2>&1
    success "Firewall: SSH + порты прокси открыты$( [[ "$WANT_PANEL" == "yes" ]] && echo " + 80/tcp" )"
}

# ══════════════════════════════════════════════════════════════
# WEB PANEL
# ══════════════════════════════════════════════════════════════

generate_panel_html() {
    local ip=$1 ptype=$2 pproto=$3 pcount=$4 fmt=$5

    mkdir -p "$PANEL_DIR"

    # Build JS proxy array
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
  ::-webkit-scrollbar{width:6px;height:6px}
  ::-webkit-scrollbar-track{background:#1e293b}
  ::-webkit-scrollbar-thumb{background:#475569;border-radius:3px}
  .proxy-line{font-family:'Courier New',monospace;font-size:13px}
  .fade-in{animation:fadeIn .3s ease}
  @keyframes fadeIn{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:translateY(0)}}
  .copy-flash{animation:flash .4s ease}
  @keyframes flash{0%,100%{background-color:transparent}50%{background-color:rgba(34,197,94,.15)}}
</style>
</head>
<body class="bg-slate-900 text-slate-100 min-h-screen">

<!-- Header -->
<div class="bg-slate-800 border-b border-slate-700 px-6 py-4 flex items-center justify-between">
  <div class="flex items-center gap-3">
    <div class="w-8 h-8 bg-cyan-500 rounded-lg flex items-center justify-center text-slate-900 font-bold text-sm">P</div>
    <div>
      <div class="font-semibold text-white">Proxy Panel</div>
      <div class="text-xs text-slate-400">${ip}</div>
    </div>
  </div>
  <div class="flex items-center gap-2">
    <span class="px-2 py-1 rounded text-xs font-medium $( [[ "$ptype" == "ipv6" ]] && echo "bg-purple-500/20 text-purple-300" || echo "bg-blue-500/20 text-blue-300" )">${ptype^^}</span>
    <span class="px-2 py-1 bg-slate-700 rounded text-xs text-slate-300">${pcount} прокси</span>
  </div>
</div>

<!-- Stats -->
<div class="px-6 py-5 grid grid-cols-2 md:grid-cols-4 gap-4">
  <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
    <div class="text-xs text-slate-400 mb-1">Сервер</div>
    <div class="font-mono text-sm text-cyan-400">${ip}</div>
  </div>
  <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
    <div class="text-xs text-slate-400 mb-1">Тип</div>
    <div class="font-semibold text-white">${ptype^^} ${pproto^^}</div>
  </div>
  <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
    <div class="text-xs text-slate-400 mb-1">Количество</div>
    <div class="font-semibold text-white" id="totalCount">${pcount}</div>
  </div>
  <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
    <div class="text-xs text-slate-400 mb-1">Формат</div>
    <div class="text-xs font-mono text-slate-300">${fmt}</div>
  </div>
</div>

<!-- Controls -->
<div class="px-6 pb-4 flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between">
  <div class="relative flex-1 max-w-md">
    <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
    </svg>
    <input id="searchInput" type="text" placeholder="Поиск по IP, порту, логину..."
      class="w-full bg-slate-800 border border-slate-600 rounded-lg pl-10 pr-4 py-2 text-sm text-slate-100 placeholder-slate-500 focus:outline-none focus:border-cyan-500 transition-colors"
      oninput="filterProxies()">
  </div>
  <div class="flex gap-2">
    <button onclick="copyAll()"
      class="flex items-center gap-2 px-4 py-2 bg-cyan-600 hover:bg-cyan-500 text-white text-sm font-medium rounded-lg transition-colors">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
      </svg>
      <span id="copyBtnText">Скопировать всё</span>
    </button>
    <button onclick="downloadTxt()"
      class="flex items-center gap-2 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white text-sm font-medium rounded-lg transition-colors">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/>
      </svg>
      Скачать .txt
    </button>
  </div>
</div>

<!-- Proxy list -->
<div class="px-6 pb-8">
  <div class="bg-slate-800 border border-slate-700 rounded-xl overflow-hidden">
    <div class="px-4 py-2 bg-slate-750 border-b border-slate-700 flex items-center justify-between">
      <span class="text-xs text-slate-400">Список прокси</span>
      <span id="visibleCount" class="text-xs text-slate-500">${pcount} записей</span>
    </div>
    <div id="proxyList" class="divide-y divide-slate-700/50 max-h-[60vh] overflow-y-auto">
    </div>
  </div>
</div>

<script>
const proxies = [
${js_list}
];

const filtered = { list: [...proxies] };

function renderList(list) {
  const container = document.getElementById('proxyList');
  if (list.length === 0) {
    container.innerHTML = '<div class="px-4 py-8 text-center text-slate-500 text-sm">Ничего не найдено</div>';
    return;
  }
  container.innerHTML = list.map((p, i) =>
    '<div class="flex items-center gap-3 px-4 py-2 hover:bg-slate-700/40 transition-colors group fade-in" data-proxy="' + p.replace(/"/g,'&quot;') + '">' +
    '<span class="text-xs text-slate-600 w-6 text-right select-none">' + (i+1) + '</span>' +
    '<span class="proxy-line flex-1 text-slate-200 break-all">' + p + '</span>' +
    '<button onclick="copySingle(this)" data-val="' + p.replace(/"/g,'&quot;') + '"' +
    ' class="opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded text-slate-400 hover:text-cyan-400" title="Скопировать">' +
    '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/></svg>' +
    '</button></div>'
  ).join('');
}

function filterProxies() {
  const q = document.getElementById('searchInput').value.toLowerCase();
  const list = q ? proxies.filter(p => p.toLowerCase().includes(q)) : proxies;
  filtered.list = list;
  document.getElementById('visibleCount').textContent = list.length + ' записей';
  renderList(list);
}

function copyAll() {
  const text = filtered.list.join('\n');
  navigator.clipboard.writeText(text).then(() => {
    const btn = document.getElementById('copyBtnText');
    btn.textContent = '✓ Скопировано!';
    setTimeout(() => btn.textContent = 'Скопировать всё', 2000);
  });
}

function copySingle(btn) {
  navigator.clipboard.writeText(btn.dataset.val).then(() => {
    btn.innerHTML = '<svg class="w-4 h-4 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>';
    setTimeout(() => {
      btn.innerHTML = '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/></svg>';
    }, 2000);
  });
}

function downloadTxt() {
  const text = filtered.list.join('\n');
  const a = document.createElement('a');
  a.href = 'data:text/plain;charset=utf-8,' + encodeURIComponent(text);
  a.download = 'proxies_${ip}.txt';
  a.click();
}

renderList(proxies);
</script>
</body>
</html>
HTMLEOF
}

setup_web_panel() {
    step "Настройка веб-панели..."
    PANEL_PASS=$(gen_random 16)

    generate_panel_html "$SERVER_IPV4" "$PROXY_TYPE" "$PROXY_PROTOCOL" "$PROXY_COUNT" "$(format_name)"

    # Nginx config
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
        try_files $uri $uri/ =404;
    }

    location /panel {
        return 301 /panel/;
    }

    location / {
        return 301 /panel/;
    }
}
EOF

    # Remove default site, enable ours
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/proxy-panel /etc/nginx/sites-enabled/proxy-panel

    # Create htpasswd
    htpasswd -bc /etc/nginx/.htpasswd-panel "$PANEL_USER" "$PANEL_PASS" > /dev/null 2>&1

    # Save credentials
    cat > "$PANEL_CREDS" <<EOF
# Веб-панель прокси
URL:      http://${SERVER_IPV4}/panel
Логин:    ${PANEL_USER}
Пароль:   ${PANEL_PASS}
EOF
    chmod 600 "$PANEL_CREDS"

    # Create update command
    cat > "$UPDATE_PANEL_CMD" <<'UPDATEEOF'
#!/bin/bash
# Regenerates panel HTML from current proxy_list.txt
source /etc/3proxy/panel_vars
UPDATEEOF

    # Store vars for regeneration
    cat > /etc/3proxy/panel_vars <<EOF
SERVER_IPV4="$SERVER_IPV4"
PROXY_TYPE="$PROXY_TYPE"
PROXY_PROTOCOL="$PROXY_PROTOCOL"
PROXY_COUNT="$PROXY_COUNT"
OUTPUT_FORMAT="$OUTPUT_FORMAT"
EOF

    nginx -t > /dev/null 2>&1 && systemctl restart nginx || {
        warn "Nginx не запустился. Проверьте: nginx -t"
    }

    systemctl enable nginx > /dev/null 2>&1
    success "Веб-панель: http://${SERVER_IPV4}/panel"
}

# ══════════════════════════════════════════════════════════════
# RESULTS
# ══════════════════════════════════════════════════════════════

print_results() {
    clear
    echo -e "${GREEN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║                                                  ║"
    echo "  ║       ✓   УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!           ║"
    echo "  ║                                                  ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}Параметры:${NC}"
    echo -e "  ${CYAN}  Тип:        ${WHITE}$PROXY_TYPE${NC}"
    echo -e "  ${CYAN}  Протокол:   ${WHITE}${PROXY_PROTOCOL^^}${NC}"
    echo -e "  ${CYAN}  Количество: ${WHITE}$PROXY_COUNT${NC}"
    echo -e "  ${CYAN}  Формат:     ${WHITE}$(format_name)${NC}"
    echo -e "  ${CYAN}  Порты:      ${WHITE}${START_PORT} – $((START_PORT + PROXY_COUNT - 1))${NC}"
    echo ""

    if [[ "$WANT_PANEL" == "yes" ]]; then
        echo -e "  ${CYAN}${BOLD}  Веб-панель:${NC}"
        echo -e "  ${WHITE}  URL:     ${GREEN}http://${SERVER_IPV4}/panel${NC}"
        echo -e "  ${WHITE}  Логин:   ${GREEN}${PANEL_USER}${NC}"
        echo -e "  ${WHITE}  Пароль:  ${GREEN}${PANEL_PASS}${NC}"
        echo -e "  ${YELLOW}  Сохранено в: $PANEL_CREDS${NC}"
        echo ""
    fi

    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}Первые прокси:${NC}"; echo ""
    local shown=0
    while IFS= read -r line && (( shown < 10 )); do
        echo -e "  ${GREEN}$line${NC}"; (( shown++ ))
    done < "$PROXY_LIST"
    (( PROXY_COUNT > 10 )) && echo -e "\n  ${YELLOW}  ... и ещё $((PROXY_COUNT - 10)) в файле${NC}"
    echo ""
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}Полный список:${NC}"
    echo -e "  ${CYAN}  cat $PROXY_LIST${NC}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Управление:${NC}"
    echo -e "  ${CYAN}  systemctl status  3proxy${NC}  — статус"
    echo -e "  ${CYAN}  systemctl restart 3proxy${NC}  — перезапуск"
    echo -e "  ${CYAN}  systemctl stop    3proxy${NC}  — остановить"
    echo ""; print_line; echo ""
}

# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════

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
    echo -e "  ${WHITE}${BOLD}Установка...${NC}\n"

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
    [[ "$WANT_PANEL" == "yes" ]] && setup_web_panel

    print_results
}

main "$@"
