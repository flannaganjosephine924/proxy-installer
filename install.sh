#!/bin/bash
# PROXY SERVER INSTALLER
# IPv4 / IPv6 | Ubuntu 20/22/24

echo ""
echo "  Установщик прокси: запуск..."
echo ""

set -uo pipefail

# Фикс для корректного отображения кириллицы на минимальных Ubuntu.
# (Не влияет на систему, только на текущий процесс скрипта.)
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'
NC='\033[0m'; BOLD='\033[1m'

INSTALL_DIR="/etc/3proxy"
CONFIG_FILE="/etc/3proxy/3proxy.cfg"
LOG_DIR="/var/log/3proxy"
PROXY_LIST="/root/proxy_list.txt"
IPV6_SCRIPT="/usr/local/bin/add-proxy-ipv6.sh"
PANEL_DIR="/var/www/html/panel"
PANEL_CREDS="/root/panel_credentials.txt"

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

print_line() { echo -e "${CYAN}  ==================================================${NC}"; }
success()    { echo -e "${GREEN}  [OK] $1${NC}"; }
err()        { echo -e "${RED}  [X] $1${NC}"; }
info()       { echo -e "${BLUE}  [i] $1${NC}"; }
warn()       { echo -e "${YELLOW}  [!] $1${NC}"; }
step()       { echo -e "\n${WHITE}${BOLD}  > $1${NC}"; }

gen_random() { cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "${1:-12}" | head -n 1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "\n${RED}${BOLD}  Требуется root: sudo bash install.sh${NC}\n"
        exit 1
    fi
}

check_os() {
    local ver
    ver=$(grep VERSION_ID /etc/os-release 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "")
    if ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
        warn "Скрипт оптимизирован для Ubuntu. Продолжить на другой ОС?"
        echo -ne "  (yes/no, да/нет): "; read -r ans
        if [[ ! "${ans,,}" =~ ^(yes|y|да)$ ]]; then exit 0; fi
    elif [[ "$ver" != "20" && "$ver" != "22" && "$ver" != "24" ]]; then
        warn "Протестировано на Ubuntu 20/22/24. Текущая: $ver. Продолжить?"
        echo -ne "  (yes/no, да/нет): "; read -r ans
        if [[ ! "${ans,,}" =~ ^(yes|y|да)$ ]]; then exit 0; fi
    fi
}

print_banner() {
    command -v clear >/dev/null 2>&1 && clear || true
    echo -e "${CYAN}"
    echo "  +--------------------------------------------------+"
    echo "  |                                                  |"
    echo "  |             У С Т А Н О В Щ И К  П Р О К С И     |"
    echo "  |                 IPv4 / IPv6  -  Ubuntu 20/22/24  |"
    echo "  |                                                  |"
    echo "  +--------------------------------------------------+"
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

step_proxy_type() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 1 из 6 - Тип прокси${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}[1]${NC}  ${WHITE}${BOLD}IPv4${NC}  - одна прокси, выход через IPv4 сервера"
    echo -e "       ${YELLOW}172.233.96.133:10000:login:password${NC}\n"
    echo -e "  ${GREEN}[2]${NC}  ${WHITE}${BOLD}IPv6${NC}  - много прокси, каждая с уникальным IPv6"
    echo -e "       ${YELLOW}172.233.96.133:10001:login1:pass1  <- разные IP${NC}"
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

step_proxy_count() {
    if [[ "$PROXY_TYPE" == "ipv4" ]]; then PROXY_COUNT=1; return; fi
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 2 из 6 - Количество прокси${NC}\n"
    print_line; echo ""
    echo -e "  Каждая прокси получит:"
    echo -e "  ${WHITE}- Уникальный IPv6 адрес${NC}"
    echo -e "  ${WHITE}- Свой порт (${START_PORT}, $((START_PORT+1)), ...)${NC}"
    echo -e "  ${WHITE}- Свой логин и пароль${NC}"
    echo ""; echo -e "  ${YELLOW}Диапазон: 1 - 1000${NC}"
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

step_protocol() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 3 из 6 - Протокол прокси${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}[1]${NC}  ${WHITE}${BOLD}SOCKS5${NC}  - универсальный, TCP и UDP"
    echo -e "       ${YELLOW}Подходит для браузеров, ботов, парсеров, игр${NC}\n"
    echo -e "  ${GREEN}[2]${NC}  ${WHITE}${BOLD}HTTP${NC}    - только HTTP/HTTPS трафик"
    echo -e "       ${YELLOW}Подходит для браузеров и большинства программ${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Ваш выбор (1 или 2): ${NC}"; read -r ch
        case $ch in
            1) PROXY_PROTOCOL="socks5"; break ;;
            2) PROXY_PROTOCOL="http"; break ;;
            *) err "Введите 1 или 2" ;;
        esac
    done
}

step_format() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 4 из 6 - Формат вывода${NC}\n"
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
        case $ch in
            1|2|3|4) OUTPUT_FORMAT=$ch; break ;;
            *) err "Введите от 1 до 4" ;;
        esac
    done
}

step_panel() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 5 из 6 - Веб-панель${NC}\n"
    print_line; echo ""
    echo -e "  Установить веб-панель для просмотра прокси?"
    echo ""
    echo -e "  ${CYAN}URL:${NC}   ${WHITE}http://VASH_IP/panel${NC}"
    echo -e "  ${CYAN}Вход:${NC} логин + пароль"
    echo ""
    echo -e "  Возможности:"
    echo -e "  ${WHITE}- Список всех прокси${NC}"
    echo -e "  ${WHITE}- Поиск и фильтр${NC}"
    echo -e "  ${WHITE}- Копировать / Скачать${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Установить панель? (yes/no, да/нет): ${NC}"; read -r ans
        case "${ans,,}" in
            yes|y)  WANT_PANEL="yes"; break ;;
            no|n)   WANT_PANEL="no";  break ;;
            да) WANT_PANEL="yes"; break ;;
            нет) WANT_PANEL="no"; break ;;
            *) err "Введите yes/no или да/нет" ;;
        esac
    done
}

step_confirm() {
    print_banner
    echo -e "  ${WHITE}${BOLD}Шаг 6 из 6 - Проверка перед установкой${NC}\n"
    print_line; echo ""
    echo -e "  ${GREEN}${BOLD}[OK] ТРЕБОВАНИЯ:${NC}"
    echo -e "  ${WHITE}     - Ubuntu 20.04 / 22.04 / 24.04 LTS${NC}"
    echo -e "  ${WHITE}     - Минимум 512 MB RAM${NC}"
    echo -e "  ${WHITE}     - Доступ root${NC}"
    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        echo ""
        echo -e "  ${GREEN}${BOLD}[OK] ДЛЯ IPv6:${NC}"
        echo -e "  ${WHITE}     - IPv6 включён в панели VPS${NC}"
        echo -e "  ${WHITE}     - Провайдер выдал /48 или /64 подсеть${NC}"
        echo -e "  ${YELLOW}     [!] Рекомендуется: Hetzner, Vultr, DigitalOcean, Aeza${NC}"
    fi
    echo ""
    echo -e "  ${CYAN}${BOLD}[i] БУДЕТ УСТАНОВЛЕНО:${NC}"
    echo -e "  ${WHITE}     - 3proxy (из исходников)${NC}"
    echo -e "  ${WHITE}     - UFW (фаервол)${NC}"
    echo -e "  ${WHITE}     - systemd-сервис${NC}"
    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        echo -e "  ${WHITE}     - IPv6 адреса + forwarding${NC}"
    fi
    if [[ "$WANT_PANEL" == "yes" ]]; then
        echo -e "  ${WHITE}     - Nginx + веб-панель${NC}"
    fi
    echo ""
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}Итого:${NC}"
    echo -e "  ${CYAN}  Тип:        ${WHITE}$PROXY_TYPE${NC}"
    echo -e "  ${CYAN}  Протокол:   ${WHITE}${PROXY_PROTOCOL^^}${NC}"
    echo -e "  ${CYAN}  Количество: ${WHITE}$PROXY_COUNT${NC}"
    echo -e "  ${CYAN}  Формат:     ${WHITE}$(format_name)${NC}"
    echo -e "  ${CYAN}  Порты:      ${WHITE}${START_PORT} - $((START_PORT + PROXY_COUNT - 1))${NC}"
    echo -e "  ${CYAN}  Панель:     ${WHITE}$WANT_PANEL${NC}"
    echo ""; print_line; echo ""
    while true; do
        echo -ne "  ${WHITE}Начать установку? (yes/no, да/нет): ${NC}"; read -r ans
        case "${ans,,}" in
            yes|y|да) break ;;
            no|n|нет) echo "  Отмена."; exit 0 ;;
            *) warn "Введите yes/no или да/нет" ;;
        esac
    done
}

install_dependencies() {
    step "Обновление пакетов..."
    apt-get update -qq
    local pkgs="build-essential curl wget tar iproute2 ufw python3 net-tools"
    if [[ "$WANT_PANEL" == "yes" ]]; then
        pkgs="$pkgs nginx apache2-utils"
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs > /dev/null 2>&1
    success "Зависимости установлены"
}

install_3proxy() {
    step "Загрузка исходников прокси..."
    local ver
    ver=$(curl -s --max-time 10 https://api.github.com/repos/3proxy/3proxy/releases/latest \
          | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v' || true)
    if [[ -z "$ver" || "$ver" == "null" ]]; then ver="0.9.4"; fi
    info "Версия движка: $ver"

    cd /tmp
    rm -rf 3proxy-build && mkdir 3proxy-build && cd 3proxy-build
    wget -q "https://github.com/3proxy/3proxy/archive/refs/tags/${ver}.tar.gz" -O src.tar.gz \
        || { err "Ошибка загрузки исходников"; exit 1; }
    tar -xzf src.tar.gz
    cd "3proxy-${ver}" 2>/dev/null || cd 3proxy-* || { err "Не найден распакованный каталог 3proxy"; exit 1; }

    step "Сборка..."
    local build_log="/tmp/3proxy-build.log"
    if ! make -f Makefile.Linux >"$build_log" 2>&1; then
        err "Ошибка сборки. Лог: $build_log"
        echo ""
        echo "----- последние строки лога -----"
        tail -n 50 "$build_log" 2>/dev/null || true
        echo "--------------------------------"
        exit 1
    fi

    local built_bin=""
    if [[ -f "src/3proxy" ]]; then
        built_bin="src/3proxy"
    elif [[ -f "bin/3proxy" ]]; then
        built_bin="bin/3proxy"
    elif [[ -f "./3proxy" ]]; then
        built_bin="./3proxy"
    fi

    if [[ -z "$built_bin" ]]; then
        err "Сборка завершилась, но бинарник 3proxy не найден (ожидался src/3proxy или bin/3proxy)."
        echo ""
        echo "Подсказка: проверьте содержимое /tmp/3proxy-build и лог компиляции:"
        echo "  ls -la /tmp/3proxy-build && ls -la /tmp/3proxy-build/* && tail -n 50 $build_log"
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"
    cp "$built_bin" "$INSTALL_DIR/3proxy"
    chmod +x "$INSTALL_DIR/3proxy"
    mkdir -p "$LOG_DIR"
    success "Прокси-сервер установлен (сборка: $ver)"
}

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
        info "Интерфейс: $NET_INTERFACE"
        info "IPv6: ${IPV6_ADDR}/${IPV6_PREFIX_LEN}"
    fi
    success "Сетевые параметры определены"
}

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
    if [[ -z "$prefix64" ]]; then
        err "Не удалось определить /64 из ${IPV6_ADDR}"
        exit 1
    fi
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
SCRIPT
    local count=0
    for addr in "${IPV6_ADDRESSES[@]}"; do
        echo "ip -6 addr add ${addr}/64 dev $NET_INTERFACE 2>/dev/null || true" >> "$IPV6_SCRIPT"
        echo "ip -6 neigh add proxy ${addr} dev $NET_INTERFACE 2>/dev/null || ip -6 neigh replace proxy ${addr} dev $NET_INTERFACE 2>/dev/null || true" >> "$IPV6_SCRIPT"
        ip -6 addr add "${addr}/64" dev "$NET_INTERFACE" 2>/dev/null || true
        ip -6 neigh add proxy "${addr}" dev "$NET_INTERFACE" 2>/dev/null || ip -6 neigh replace proxy "${addr}" dev "$NET_INTERFACE" 2>/dev/null || true
        (( count++ ))
        if (( count % 100 == 0 )); then
            info "Добавлено $count / $PROXY_COUNT..."
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
    success "IPv6 адреса добавлены"
}

configure_ipv6_kernel() {
    step "Включение IPv6 forwarding..."
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null 2>&1
    sysctl -w net.ipv6.conf.all.proxy_ndp=1 > /dev/null 2>&1
    if [[ -n "${NET_INTERFACE:-}" ]]; then
        sysctl -w "net.ipv6.conf.${NET_INTERFACE}.proxy_ndp=1" > /dev/null 2>&1 || true
        sysctl -w "net.ipv6.conf.${NET_INTERFACE}.forwarding=1" > /dev/null 2>&1 || true
        # На многих VPS IPv6 маршрут приходит через RA. При forwarding=1 RA может отключиться,
        # поэтому явно разрешаем принимать RA.
        sysctl -w "net.ipv6.conf.${NET_INTERFACE}.accept_ra=2" > /dev/null 2>&1 || true
    fi
    sysctl -w net.ipv6.conf.default.forwarding=1 > /dev/null 2>&1
    sysctl -w net.ipv6.conf.default.accept_ra=2 > /dev/null 2>&1 || true
    grep -q "net.ipv6.conf.all.forwarding" /etc/sysctl.conf || \
    cat >> /etc/sysctl.conf <<'EOF'

net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.proxy_ndp=1
EOF
    if [[ -n "${NET_INTERFACE:-}" ]] && ! grep -q "net.ipv6.conf.${NET_INTERFACE}.proxy_ndp" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf <<EOF
net.ipv6.conf.${NET_INTERFACE}.proxy_ndp=1
net.ipv6.conf.${NET_INTERFACE}.forwarding=1
net.ipv6.conf.${NET_INTERFACE}.accept_ra=2
EOF
    fi
    grep -q "net.ipv6.conf.default.accept_ra" /etc/sysctl.conf || echo "net.ipv6.conf.default.accept_ra=2" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1 || true
    success "IPv6 forwarding включён"
}

configure_3proxy() {
    step "Генерация конфигурации ($PROXY_COUNT прокси)..."

    cat > "$CONFIG_FILE" <<EOF
nscache 65536
nscache6 65536
timeouts 1 5 30 60 180 1800 15 60
daemon
pidfile /var/run/3proxy.pid
log $LOG_DIR/3proxy.log D
logformat "- +_L%t.%.  %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30
maxconn 200

auth strong

EOF
    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        # IPv6 DNS - помогает, чтобы резолвилось в AAAA и "выход" был IPv6
        echo "nserver 2606:4700:4700::1111" >> "$CONFIG_FILE"
        echo "nserver 2606:4700:4700::1001" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
    fi

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
            if [[ "$PROXY_TYPE" == "ipv6" ]]; then
                echo "proxy -6 -i0.0.0.0 -p${port}" >> "$CONFIG_FILE"
            else
                echo "proxy -i0.0.0.0 -p${port}" >> "$CONFIG_FILE"
            fi
        else
            if [[ "$PROXY_TYPE" == "ipv6" ]]; then
                echo "socks -6 -i0.0.0.0 -p${port}" >> "$CONFIG_FILE"
            else
                echo "socks -i0.0.0.0 -p${port}" >> "$CONFIG_FILE"
            fi
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

setup_3proxy_service() {
    step "Запуск прокси-сервиса..."
    local after="network-online.target"
    local wants="network-online.target"
    if [[ "$PROXY_TYPE" == "ipv6" ]]; then
        after="$after add-proxy-ipv6.service"
        wants="$wants add-proxy-ipv6.service"
    fi

    cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server (proxy-installer)
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
        success "Прокси-сервис запущен"
    else
        warn "Прокси-сервис не запустился. Проверьте: journalctl -u 3proxy -n 30"
    fi
}

setup_firewall() {
    step "Настройка UFW..."
    sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw 2>/dev/null || true
    ufw --force enable > /dev/null 2>&1
    ufw allow OpenSSH > /dev/null 2>&1
    if [[ "$WANT_PANEL" == "yes" ]]; then
        ufw allow 80/tcp > /dev/null 2>&1
    fi

    local end_port=$((START_PORT + PROXY_COUNT - 1))
    if (( PROXY_COUNT == 1 )); then
        ufw allow "${START_PORT}/tcp" > /dev/null 2>&1
        if [[ "$PROXY_PROTOCOL" == "socks5" ]]; then ufw allow "${START_PORT}/udp" > /dev/null 2>&1; fi
    else
        ufw allow "${START_PORT}:${end_port}/tcp" > /dev/null 2>&1
        if [[ "$PROXY_PROTOCOL" == "socks5" ]]; then ufw allow "${START_PORT}:${end_port}/udp" > /dev/null 2>&1; fi
    fi
    ufw reload > /dev/null 2>&1
    success "Фаервол настроен"
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
<title>Панель прокси</title>
<style>
  :root{
    --bg:#0b1220; --card:#111a2e; --line:#1f2a44; --text:#e6edf7; --muted:#93a4c7;
    --cyan:#22d3ee; --green:#34d399; --yellow:#fbbf24; --red:#fb7185; --btn:#1d2a46;
  }
  *{box-sizing:border-box}
  body{margin:0;background:linear-gradient(180deg,#070c16, var(--bg));color:var(--text);font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial}
  a{color:var(--cyan);text-decoration:none}
  .wrap{max-width:1100px;margin:0 auto;padding:18px}
  .topbar{display:flex;gap:14px;align-items:center;justify-content:space-between;padding:14px 16px;border:1px solid var(--line);background:rgba(17,26,46,.75);backdrop-filter:blur(8px);border-radius:14px}
  .brand{display:flex;align-items:center;gap:12px}
  .logo{width:36px;height:36px;border-radius:10px;background:linear-gradient(135deg,var(--cyan),#8b5cf6);display:flex;align-items:center;justify-content:center;color:#08101f;font-weight:800}
  .title{font-weight:750;letter-spacing:.2px}
  .sub{font-size:12px;color:var(--muted)}
  .badges{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end}
  .badge{font-size:12px;padding:6px 10px;border-radius:999px;border:1px solid var(--line);background:rgba(29,42,70,.6);color:var(--text)}
  .badge.cyan{border-color:rgba(34,211,238,.35);color:#a5f3fc;background:rgba(34,211,238,.10)}
  .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-top:14px}
  .card{border:1px solid var(--line);background:rgba(17,26,46,.55);border-radius:14px;padding:12px 14px}
  .card .k{font-size:12px;color:var(--muted);margin-bottom:6px}
  .mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
  .controls{display:flex;gap:10px;align-items:center;justify-content:space-between;margin-top:14px;flex-wrap:wrap}
  .search{flex:1;min-width:240px;display:flex;gap:10px;align-items:center}
  input[type="text"]{width:100%;padding:10px 12px;border-radius:12px;border:1px solid var(--line);background:rgba(11,18,32,.55);color:var(--text);outline:none}
  input[type="text"]:focus{border-color:rgba(34,211,238,.55);box-shadow:0 0 0 3px rgba(34,211,238,.12)}
  .btns{display:flex;gap:10px;flex-wrap:wrap}
  button{cursor:pointer;border:none;border-radius:12px;padding:10px 12px;background:var(--btn);color:var(--text);border:1px solid var(--line);font-weight:650}
  button:hover{filter:brightness(1.08)}
  button.primary{background:linear-gradient(135deg,var(--cyan),#60a5fa);border:0;color:#071220}
  button.ghost{background:transparent}
  .list{margin-top:12px;border-radius:14px;border:1px solid var(--line);overflow:hidden;background:rgba(17,26,46,.45)}
  .listhead{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;border-bottom:1px solid var(--line);color:var(--muted);font-size:12px}
  .rows{max-height:62vh;overflow:auto}
  .row{display:flex;gap:12px;align-items:center;justify-content:space-between;padding:10px 14px;border-bottom:1px solid rgba(31,42,68,.55)}
  .row:last-child{border-bottom:none}
  .row:hover{background:rgba(29,42,70,.35)}
  .copybtn{padding:8px 10px;border-radius:10px;font-size:12px;background:rgba(29,42,70,.8)}
  .hint{margin-top:10px;color:var(--muted);font-size:12px;line-height:1.4}
  .toast{position:fixed;right:16px;bottom:16px;min-width:180px;max-width:320px;padding:10px 12px;border-radius:12px;border:1px solid var(--line);background:rgba(17,26,46,.92);color:var(--text);display:none}
  .toast.ok{border-color:rgba(52,211,153,.35)}
  .toast.bad{border-color:rgba(251,113,133,.35)}
  @media (max-width: 900px){.grid{grid-template-columns:repeat(2,1fr)}}
  @media (max-width: 520px){.grid{grid-template-columns:1fr}.badges{justify-content:flex-start}}
</style>
</head>
<body>
<div class="wrap">
  <div class="topbar">
    <div class="brand">
      <div class="logo">P</div>
      <div>
        <div class="title">Панель прокси</div>
        <div class="sub mono">${ip}</div>
      </div>
    </div>
    <div class="badges">
      <div class="badge cyan">${ptype^^} ${pproto^^}</div>
      <div class="badge">${pcount} шт.</div>
    </div>
  </div>

  <div class="grid">
    <div class="card">
      <div class="k">Сервер</div>
      <div class="mono" style="color:var(--cyan)">${ip}</div>
    </div>
    <div class="card">
      <div class="k">Тип</div>
      <div style="font-weight:750">${ptype^^} ${pproto^^}</div>
    </div>
    <div class="card">
      <div class="k">Количество</div>
      <div style="font-weight:750">${pcount}</div>
    </div>
    <div class="card">
      <div class="k">Формат</div>
      <div class="mono" style="font-size:12px">${fmt}</div>
    </div>
  </div>

  <div class="controls">
    <div class="search">
      <input id="searchInput" type="text" placeholder="Поиск по списку..." oninput="filterProxies()">
    </div>
    <div class="btns">
      <button class="primary" onclick="copyAll()">Копировать всё</button>
      <button onclick="downloadTxt()">Скачать .txt</button>
      <button class="ghost" onclick="clearSearch()">Сброс</button>
    </div>
  </div>

  <div class="list">
    <div class="listhead">
      <span>Список прокси</span>
      <span>Показано: <span id="visibleCount">${pcount}</span></span>
    </div>
    <div id="proxyList" class="rows"></div>
  </div>

  <div class="hint">
    Если вы проверяете "выходной IP" для IPv6-прокси - используйте IPv6-доступные сайты (например, <span class="mono">api64.ipify.org</span>).
    На обычных IPv4-only сайтах всегда будет показываться IPv4.
  </div>
</div>

<div id="toast" class="toast"></div>
<script>
const proxies = [${js_list}];
let filtered = [...proxies];

function toast(msg, ok=true) {
  const t = document.getElementById('toast');
  t.className = 'toast ' + (ok ? 'ok' : 'bad');
  t.textContent = msg;
  t.style.display = 'block';
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(() => (t.style.display = 'none'), 1600);
}

function copyFallback(text) {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.top = '-1000px';
  document.body.appendChild(ta);
  ta.select();
  ta.setSelectionRange(0, ta.value.length);
  let ok = false;
  try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
  document.body.removeChild(ta);
  return ok;
}

async function copyText(text) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      toast('Скопировано');
      return true;
    }
  } catch (e) {}
  const ok = copyFallback(text);
  toast(ok ? 'Скопировано' : 'Не удалось скопировать', ok);
  return ok;
}

function renderList(list) {
  const c = document.getElementById('proxyList');
  if (!list.length) {
    c.innerHTML = '<div class="row" style="justify-content:center;color:var(--muted)">Пусто</div>';
    return;
  }
  c.innerHTML = list.map((p) => {
    const safe = p.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    return (
      '<div class="row">' +
        '<span class="mono" style="font-size:13px;word-break:break-all">' + safe + '</span>' +
        '<button class="copybtn" onclick="copyText(\\'' + p.replace(/\\/g,'\\\\').replace(/'/g,\"\\\\'\") + '\\')">копировать</button>' +
      '</div>'
    );
  }).join('');
}
function filterProxies() {
  const q = document.getElementById('searchInput').value.toLowerCase();
  filtered = q ? proxies.filter(p => p.toLowerCase().includes(q)) : [...proxies];
  document.getElementById('visibleCount').textContent = filtered.length;
  renderList(filtered);
}
function clearSearch() { document.getElementById('searchInput').value=''; filterProxies(); }
function copyAll() { copyText(filtered.join('\\n')); }
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
    step "Настройка веб-панели..."
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
        auth_basic "Панель прокси";
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
Логин:    ${PANEL_USER}
Пароль:   ${PANEL_PASS}
EOF
    chmod 600 "$PANEL_CREDS"

    nginx -t > /dev/null 2>&1 && systemctl restart nginx
    systemctl enable nginx > /dev/null 2>&1
    success "Веб-панель: http://${SERVER_IPV4}/panel"
}

print_results() {
    command -v clear >/dev/null 2>&1 && clear || true
    echo -e "${GREEN}"
    echo "  +--------------------------------------------------+"
    echo "  |                                                  |"
    echo "  |       [OK] УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!          |"
    echo "  |                                                  |"
    echo "  +--------------------------------------------------+"
    echo -e "${NC}"
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}Параметры:${NC}"
    echo -e "  ${CYAN}  Тип:        ${WHITE}$PROXY_TYPE${NC}"
    echo -e "  ${CYAN}  Протокол:   ${WHITE}${PROXY_PROTOCOL^^}${NC}"
    echo -e "  ${CYAN}  Количество: ${WHITE}$PROXY_COUNT${NC}"
    echo -e "  ${CYAN}  Формат:     ${WHITE}$(format_name)${NC}"
    echo -e "  ${CYAN}  Порты:      ${WHITE}${START_PORT} - $((START_PORT + PROXY_COUNT - 1))${NC}"
    echo ""

    if [[ "$WANT_PANEL" == "yes" ]]; then
        echo -e "  ${CYAN}${BOLD}  Веб-панель:${NC}"
        echo -e "  ${WHITE}  URL:     ${GREEN}http://${SERVER_IPV4}/panel${NC}"
        echo -e "  ${WHITE}  Логин:   ${GREEN}${PANEL_USER}${NC}"
        echo -e "  ${WHITE}  Пароль:  ${GREEN}${PANEL_PASS}${NC}"
        echo ""
    fi

    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}Первые прокси:${NC}"; echo ""
    local shown=0
    while IFS= read -r line && (( shown < 10 )); do
        echo -e "  ${GREEN}$line${NC}"; (( shown++ ))
    done < "$PROXY_LIST"
    if (( PROXY_COUNT > 10 )); then
        echo -e "\n  ${YELLOW}  ... и ещё $((PROXY_COUNT - 10)) в файле${NC}"
    fi
    echo ""
    print_line; echo ""
    echo -e "  ${WHITE}${BOLD}Команды:${NC}"
    echo -e "  ${CYAN}  cat $PROXY_LIST${NC}         - список прокси"
    echo -e "  ${CYAN}  systemctl status 3proxy${NC}  - статус"
    echo -e "  ${CYAN}  systemctl restart 3proxy${NC} - перезапуск"
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

    if [[ "$WANT_PANEL" == "yes" ]]; then
        setup_web_panel
    fi

    print_results
}

main "$@"
