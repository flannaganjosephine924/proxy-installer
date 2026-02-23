# Proxy Installer

Установщик прокси IPv4/IPv6 для Ubuntu 20.04 / 22.04 / 24.04

## Быстрая установка

```bash
curl -fsSL https://raw.githubusercontent.com/flannaganjosephine924/proxy-installer/main/install.sh -o /tmp/pi.sh && sed -i 's/\r$//' /tmp/pi.sh && bash /tmp/pi.sh
```

Альтернатива (wget):
```bash
wget -qO /tmp/pi.sh https://raw.githubusercontent.com/flannaganjosephine924/proxy-installer/main/install.sh && sed -i 's/\r$//' /tmp/pi.sh && bash /tmp/pi.sh
```

## Возможности

- **IPv4** - одна прокси с выходом через IPv4 сервера
- **IPv6** - до 1000 прокси, каждая с уникальным IPv6 адресом
- **Протокол** - SOCKS5 или HTTP
- **Веб-панель** - опционально: `http://IP/panel`
- **Форматы вывода:**
  - `IP:PORT:LOGIN:PASS`
  - `IP:PORT@LOGIN:PASS`
  - `LOGIN:PASS@IP:PORT`
  - `LOGIN:PASS:IP:PORT`

## Требования

- Ubuntu 20.04 / 22.04 / 24.04 LTS
- Доступ root
- Для IPv6: включённый IPv6 и подсеть /48 или /64 от провайдера

## После установки

```bash
cat /root/proxy_list.txt        # список прокси
systemctl status 3proxy         # статус
systemctl restart 3proxy        # перезапуск
```

## Быстрый ремонт (если панель белая или прокси не работают)

```bash
sudo systemctl stop 3proxy 2>/dev/null; sleep 1
sudo cp -f /tmp/3proxy-build/3proxy-*/bin/3proxy /etc/3proxy/3proxy 2>/dev/null || sudo cp -f /tmp/3proxy-build/3proxy-*/src/3proxy /etc/3proxy/3proxy 2>/dev/null
sudo cp /root/proxy_list.txt /var/www/html/panel/proxies.txt
sudo chown -R www-data:www-data /var/www/html/panel 2>/dev/null || sudo chown -R nginx:nginx /var/www/html/panel
sudo systemctl restart 3proxy nginx
```

### Проверка IPv6 "выхода"

IPv6-прокси покажут IPv6 только на IPv6-ресурсах. Самый правильный тест:

SOCKS5:
```bash
curl -s --socks5-hostname "LOGIN:PASS@IP:PORT" https://api64.ipify.org
```

HTTP:
```bash
curl -s -x "http://LOGIN:PASS@IP:PORT" https://api64.ipify.org
```


