#!/bin/sh

# Универсальный скрипт установки системы обхода блокировок для OpenWrt
# Автоматически определяет архитектуру и настраивает multiple методы обхода

install_awg_packages() {
    # Получение архитектуры
    PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
    
    # Если не удалось определить архитектуру, используем общие пакеты
    if [ -z "$PKGARCH" ]; then
        echo "Не удалось определить архитектуру, используем общие пакеты..."
        opkg install kmod-amneziawg amneziawg-tools luci-app-amneziawg
        return $?
    fi

    TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
    SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
    PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

    AWG_DIR="/tmp/amneziawg"
    mkdir -p "$AWG_DIR"
    
    # Установка kmod-amneziawg
    if ! opkg list-installed | grep -q kmod-amneziawg; then
        KMOD_AMNEZIAWG_FILENAME="kmod-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${KMOD_AMNEZIAWG_FILENAME}"
        
        if wget -O "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME" "$DOWNLOAD_URL"; then
            opkg install "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME" || {
                echo "Пытаемся установить общий пакет kmod-amneziawg..."
                opkg install kmod-amneziawg
            }
        else
            echo "Скачивание не удалось, пробуем общий пакет..."
            opkg install kmod-amneziawg
        fi
    fi

    # Установка amneziawg-tools
    if ! opkg list-installed | grep -q amneziawg-tools; then
        AMNEZIAWG_TOOLS_FILENAME="amneziawg-tools${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${AMNEZIAWG_TOOLS_FILENAME}"
        
        if wget -O "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME" "$DOWNLOAD_URL"; then
            opkg install "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME" || {
                echo "Пытаемся установить общий пакет amneziawg-tools..."
                opkg install amneziawg-tools
            }
        else
            opkg install amneziawg-tools
        fi
    fi

    # Установка luci-app-amneziawg
    if ! opkg list-installed | grep -q luci-app-amneziawg; then
        LUCI_APP_AMNEZIAWG_FILENAME="luci-app-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${LUCI_APP_AMNEZIAWG_FILENAME}"
        
        if wget -O "$AWG_DIR/$LUCI_APP_AMNEZIAWG_FILENAME" "$DOWNLOAD_URL"; then
            opkg install "$AWG_DIR/$LUCI_APP_AMNEZIAWG_FILENAME" || {
                echo "Пытаемся установить общий пакет luci-app-amneziawg..."
                opkg install luci-app-amneziawg
            }
        else
            opkg install luci-app-amneziawg
        fi
    fi

    rm -rf "$AWG_DIR"
}

check_package() {
    local name="$1"
    local isRequired="$2"
    
    if opkg list-installed | grep -q "^$name "; then
        echo "$name уже установлен"
        return 0
    else
        echo "Установка $name..."
        if opkg install "$name"; then
            echo "$name установлен успешно"
            return 0
        else
            echo "Ошибка установки $name"
            [ "$isRequired" = "1" ] && exit 1
            return 1
        fi
    fi
}

install_sing_box() {
    # Определяем архитектуру для sing-box
    case $(uname -m) in
        aarch64)
            SINGBOX_ARCH="aarch64"
            ;;
        armv7l)
            SINGBOX_ARCH="armv7"
            ;;
        x86_64)
            SINGBOX_ARCH="amd64"
            ;;
        mips)
            SINGBOX_ARCH="mips"
            ;;
        *)
            SINGBOX_ARCH="unknown"
            ;;
    esac
    
    if [ "$SINGBOX_ARCH" != "unknown" ]; then
        echo "Установка sing-box для архитектуры $SINGBOX_ARCH"
        wget -O /tmp/sing-box.ipk "https://github.com/SagerNet/sing-box/releases/download/v1.11.15/sing-box_1.11.15_openwrt_${SINGBOX_ARCH}.ipk"
        opkg install /tmp/sing-box.ipk
    else
        echo "Архитектура не определена, пробуем общую установку sing-box"
        opkg install sing-box
    fi
}

install_opera_proxy() {
    # Универсальная установка opera-proxy
    echo "Установка opera-proxy..."
    if opkg install opera-proxy; then
        echo "opera-proxy установлен из репозитория"
    else
        echo "Ручная установка opera-proxy..."
        # Пробуем разные архитектуры
        for arch in aarch64_cortex-a53 arm_cortex-a15_neon-vfpv4 x86_64 i386_pentium4; do
            wget -O /tmp/opera-proxy.ipk "https://github.com/NitroOxid/openwrt-opera-proxy-bin/releases/download/1.8.0/opera-proxy_1.8.0-1_${arch}.ipk" && {
                opkg install /tmp/opera-proxy.ipk && break
            }
        done
    fi
}

request_warp_config() {
    # Попробуем несколько источников для получения WARP конфигурации
    local sources=(
        "https://warp-config-generator-theta.vercel.app/api/warp"
        "https://generator-warp-config.vercel.app/warp4s"
        "https://valokda-amnezia.vercel.app/api/warp"
    )
    
    for url in "${sources[@]}"; do
        echo "Попытка получения конфигурации с $url"
        local response=$(curl -s --connect-timeout 20 --max-time 60 -w "%{http_code}" "$url" \
            -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
        
        local response_code="${response: -3}"
        local response_body="${response%???}"
        
        if [ "$response_code" -eq 200 ]; then
            echo "$response_body"
            return 0
        fi
    done
    
    echo "Не удалось получить WARP конфигурацию"
    return 1
}

setup_awg_warp() {
    echo "Настройка AWG WARP..."
    
    local warp_config=$(request_warp_config)
    if [ $? -ne 0 ]; then
        echo "Ручной ввод параметров WARP"
        echo "Вы можете получить конфигурацию на https://wgcf.zeroteam.top или аналогичных сервисах"
        read -p "Введите PrivateKey: " PrivateKey
        read -p "Введите Address (например: 172.16.0.2/32): " Address
        read -p "Введите PublicKey: " PublicKey
        read -p "Введите Endpoint (например: engage.cloudflareclient.com:2408): " Endpoint
    else
        # Парсим автоматически полученную конфигурацию
        PrivateKey=$(echo "$warp_config" | jq -r '.private_key')
        Address=$(echo "$warp_config" | jq -r '.interface.addresses.v4')
        PublicKey=$(echo "$warp_config" | jq -r '.peers[0].public_key')
        Endpoint=$(echo "$warp_config" | jq -r '.peers[0].endpoint')
    fi

    # Создаем интерфейс AWG
    uci set network.awg_warp=interface
    uci set network.awg_warp.proto='amneziawg'
    uci set network.awg_warp.private_key="$PrivateKey"
    uci set network.awg_warp.addresses="$Address"
    
    # Добавляем пир
    uci add network amneziawg
    uci set network.@amneziawg[-1].public_key="$PublicKey"
    uci set network.@amneziawg[-1].endpoint_host="${Endpoint%:*}"
    uci set network.@amneziawg[-1].endpoint_port="${Endpoint#*:}"
    uci set network.@amneziawg[-1].allowed_ips='0.0.0.0/0'
    
    uci commit network
    
    # Настройка firewall
    if ! uci get firewall.awg_zone >/dev/null 2>&1; then
        uci add firewall zone
        uci set firewall.@zone[-1].name='awg_zone'
        uci set firewall.@zone[-1].network='awg_warp'
        uci set firewall.@zone[-1].input='REJECT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].forward='REJECT'
        uci set firewall.@zone[-1].masq='1'
        
        uci add firewall forwarding
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].dest='awg_zone'
    fi
    
    uci commit firewall
}

setup_sing_box() {
    echo "Настройка Sing-Box..."
    
    cat << 'EOF' > /etc/sing-box/config.json
{
    "log": {
        "disabled": true,
        "level": "error"
    },
    "inbounds": [
        {
            "type": "tproxy",
            "listen": "::",
            "listen_port": 1100,
            "sniff": false
        }
    ],
    "outbounds": [
        {
            "type": "http",
            "server": "127.0.0.1",
            "server_port": 18080
        }
    ],
    "route": {
        "auto_detect_interface": true
    }
}
EOF

    uci set sing-box.main.enabled='1'
    uci set sing-box.main.user='root'
    uci commit sing-box
}

setup_dns() {
    echo "Настройка DNS..."
    
    # Резервное копирование текущей конфигурации
    cp /etc/config/dhcp /etc/config/dhcp.backup.$(date +%s)
    
    # Настройка dnsmasq
    uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
    uci set dhcp.@dnsmasq[0].strictorder='1'
    uci set dhcp.@dnsmasq[0].filter_aaaa='1'
    
    # Добавляем DNS серверы
    uci delete dhcp.@dnsmasq[0].server
    uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5053'
    uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
    uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
    
    uci commit dhcp
}

setup_firewall_rules() {
    echo "Настройка firewall..."
    
    # Блокировка QUIC
    if ! uci get firewall.block_quic >/dev/null 2>&1; then
        uci add firewall rule
        uci set firewall.@rule[-1].name='Block_QUIC_443'
        uci set firewall.@rule[-1].proto='udp'
        uci set firewall.@rule[-1].dest_port='443'
        uci set firewall.@rule[-1].target='REJECT'
        
        uci add firewall rule
        uci set firewall.@rule[-1].name='Block_QUIC_80'
        uci set firewall.@rule[-1].proto='udp'
        uci set firewall.@rule[-1].dest_port='80'
        uci set firewall.@rule[-1].target='REJECT'
    fi
    
    uci commit firewall
}

install_zapret() {
    echo "Установка Zapret..."
    
    if opkg install zapret luci-app-zapret; then
        # Базовая настройка zapret
        uci set zapret.config.enabled='1'
        uci commit zapret
        /etc/init.d/zapret enable
        /etc/init.d/zapret start
    else
        echo "Zapret не установлен, продолжаем без него"
    fi
}

start_services() {
    echo "Запуск сервисов..."
    
    # Перезапуск сетевых сервисов
    /etc/init.d/network restart
    /etc/init.d/firewall restart
    /etc/init.d/dnsmasq restart
    
    # Запуск основных сервисов
    /etc/init.d/sing-box enable
    /etc/init.d/sing-box restart
    
    if [ -f /etc/init.d/opera-proxy ]; then
        /etc/init.d/opera-proxy enable
        /etc/init.d/opera-proxy restart
    fi
    
    # Включаем AWG интерфейс
    ifup awg_warp
}

print_status() {
    echo ""
    echo "=========================================="
    echo "Установка завершена!"
    echo "=========================================="
    echo "Установленные компоненты:"
    echo "✓ AmneziaWG + WARP"
    echo "✓ Sing-Box"
    echo "✓ Opera Proxy" 
    echo "✓ Настроенный DNS"
    echo "✓ Firewall правила"
    echo ""
    echo "Интерфейсы:"
    ip addr show awg_warp 2>/dev/null && echo "AWG WARP: ✅" || echo "AWG WARP: ❌"
    echo ""
    echo "Проверка подключения:"
    echo "1. ping -I awg_warp 8.8.8.8"
    echo "2. curl --interface awg_warp ifconfig.me"
    echo ""
    echo "Веб-интерфейсы:"
    echo "- LuCI: http://192.168.1.1"
    echo "- AmneziaWG: в разделе Network → Interfaces"
    echo "=========================================="
}

# Главная функция установки
main_install() {
    echo "Начало установки системы обхода блокировок..."
    echo "Архитектура: $(uname -m)"
    echo "Версия OpenWrt: $(cat /etc/openwrt_release 2>/dev/null | grep 'DISTRIB_DESCRIPTION' | cut -d= -f2)"
    
    # Обновление списка пакетов
    echo "Обновление списка пакетов..."
    opkg update
    
    # Установка необходимых утилит
    check_package "wget" "1"
    check_package "curl" "1"
    check_package "jq" "1"
    check_package "unzip" "0"
    
    # Установка основных компонентов
    install_awg_packages
    install_sing_box
    install_opera_proxy
    install_zapret
    
    # Настройка компонентов
    setup_awg_warp
    setup_sing_box
    setup_dns
    setup_firewall_rules
    
    # Запуск сервисов
    start_services
    
    # Статус
    print_status
    
    echo ""
    read -p "Выполнить перезагрузку для применения всех настроек? (y/n): " reboot_choice
    if [ "$reboot_choice" = "y" ] || [ "$reboot_choice" = "Y" ]; then
        echo "Перезагрузка через 5 секунд..."
        sleep 5
        reboot
    fi
}

# Запуск установки
main_install