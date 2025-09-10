#!/bin/sh
# Исправленная полная версия скрипта для OpenWrt (ash/BusyBox)
# Заменены все read -p -> echo + read, убраны bash-only конструкции,
# добавлен wget-помощник и очистка временных файлов.

set -u

TMP_DIR="/tmp/zaprets_script"
AWG_DIR="$TMP_DIR/amneziawg"
YOUTUBE_DIR="$TMP_DIR/youtubeunblock"
SINGBOX_DIR="$TMP_DIR/singbox"
TMP_WARP="$TMP_DIR/warp_config.tmp"
mkdir -p "$TMP_DIR" "$AWG_DIR" "$YOUTUBE_DIR" "$SINGBOX_DIR"

# Источники конфигов (исправлены URL)
CONFIG_URL="https://raw.githubusercontent.com/basek-diell/xia3000t./refs/heads/main"
PODKOP_URL="https://raw.githubusercontent.com/basek-diell/xia3000t./refs/heads/main"

# Функция очистки
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Функция скачивания с проверкой
download_file() {
    url="$1"
    dest="$2"
    tries=3
    i=0
    while [ $i -lt $tries ]; do
        i=$((i + 1))
        wget --tries=2 --timeout=30 -O "$dest" "$url" >/dev/null 2>&1
        if [ $? -eq 0 ] && [ -s "$dest" ]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Определение PKGARCH с наибольшим приоритетом
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} { if ($3+0 > max+0) { max=$3+0; arch=$2 }} END { print arch }')

# Чтение target/version
TARGET=$(ubus call system board | jsonfilter -e '@.release.target' 2>/dev/null | cut -d '/' -f1 || echo "")
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' 2>/dev/null | cut -d '/' -f2 || echo "")
VERSION=$(ubus call system board | jsonfilter -e '@.release.version' 2>/dev/null || echo "")

########### install_awg_packages (исправлено)
install_awg_packages() {
    echo "Install AmneziaWG packages..."
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"
    PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"

    mkdir -p "$AWG_DIR"

    # kmod-amneziawg
    if opkg list-installed | grep -q "^kmod-amneziawg"; then
        echo "kmod-amneziawg already installed"
    else
        KMOD_AMNEZIAWG_FILENAME="kmod-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${KMOD_AMNEZIAWG_FILENAME}"
        echo "Downloading $KMOD_AMNEZIAWG_FILENAME ..."
        if download_file "$DOWNLOAD_URL" "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME"; then
            opkg install "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME" || { echo "Error installing kmod-amneziawg"; exit 1; }
        else
            echo "Error downloading kmod-amneziawg. Please install it manually."
            exit 1
        fi
    fi

    # amneziawg-tools
    if opkg list-installed | grep -q "^amneziawg-tools"; then
        echo "amneziawg-tools already installed"
    else
        AMNEZIAWG_TOOLS_FILENAME="amneziawg-tools${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${AMNEZIAWG_TOOLS_FILENAME}"
        echo "Downloading $AMNEZIAWG_TOOLS_FILENAME ..."
        if download_file "$DOWNLOAD_URL" "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME"; then
            opkg install "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME" || { echo "Error installing amneziawg-tools"; exit 1; }
        else
            echo "Error downloading amneziawg-tools. Please install it manually."
            exit 1
        fi
    fi

    # luci-app-amneziawg
    if opkg list-installed | grep -q "^luci-app-amneziawg"; then
        echo "luci-app-amneziawg already installed"
    else
        LUCI_APP_AMNEZIAWG_FILENAME="luci-app-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${LUCI_APP_AMNEZIAWG_FILENAME}"
        echo "Downloading $LUCI_APP_AMNEZIAWG_FILENAME ..."
        if download_file "$DOWNLOAD_URL" "$AWG_DIR/$LUCI_APP_AMNEZIAWG_FILENAME"; then
            opkg install "$AWG_DIR/$LUCI_APP_AMNEZIAWG_FILENAME" || { echo "Error installing luci-app-amneziawg"; exit 1; }
        else
            echo "Error downloading luci-app-amneziawg. Please install it manually."
            exit 1
        fi
    fi

    rm -rf "$AWG_DIR"
}

# manage_package (как в оригинале)
manage_package() {
    name="$1"
    autostart="$2"
    process="$3"

    if opkg list-installed | grep -q "^$name"; then
        # автозапуск
        if [ -x "/etc/init.d/$name" ]; then
            if /etc/init.d/$name enabled >/dev/null 2>&1; then
                if [ "$autostart" = "disable" ]; then
                    /etc/init.d/$name disable >/dev/null 2>&1 || true
                fi
            else
                if [ "$autostart" = "enable" ]; then
                    /etc/init.d/$name enable >/dev/null 2>&1 || true
                fi
            fi
        fi

        # процесс (pidof)
        if pidof "$name" >/dev/null 2>&1; then
            if [ "$process" = "stop" ]; then
                /etc/init.d/$name stop >/dev/null 2>&1 || true
            fi
        else
            if [ "$process" = "start" ]; then
                /etc/init.d/$name start >/dev/null 2>&1 || true
            fi
        fi
    fi
}

# checkPackageAndInstall
checkPackageAndInstall() {
    name="$1"
    isRequired="$2"
    alt=""

    if [ "$name" = "https-dns-proxy" ]; then
        alt="luci-app-doh-proxy"
    fi

    if [ -n "$alt" ]; then
        if opkg list-installed | grep -qE "^($name|$alt) "; then
            echo "$name or $alt already installed..."
            return 0
        fi
    else
        if opkg list-installed | grep -q "^$name "; then
            echo "$name already installed..."
            return 0
        fi
    fi

    echo "$name not installed. Installing $name..."
    opkg install "$name"
    res=$?
    if [ "$isRequired" = "1" ]; then
        if [ $res -eq 0 ]; then
            echo "$name installed successfully"
        else
            echo "Error installing $name. Please install $name manually$( [ -n "$alt" ] && echo " or $alt")."
            exit 1
        fi
    fi
}

# WARP запросы (как в оригинале)
requestConfWARP1() {
    curl --connect-timeout 20 --max-time 60 -w "%{http_code}" 'https://warp.llimonix.pw/api/warp' \
      -H 'Accept: */*' \
      -H 'Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7' \
      -H 'Connection: keep-alive' \
      -H 'Content-Type: application/json' \
      -H 'Origin: https://warp.llimonix.pw' \
      -H 'Referer: https://warp.llimonix.pw/' \
      -H 'Sec-Fetch-Dest: empty' \
      -H 'Sec-Fetch-Mode: cors' \
      -H 'Sec-Fetch-Site: same-origin' \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36' \
      --data-raw '{"selectedServices":[],"siteMode":"all","deviceType":"computer"}' 2>/dev/null || echo ""
}

requestConfWARP2() {
    curl --connect-timeout 20 --max-time 60 -w "%{http_code}" 'https://topor-warp.vercel.app/generate' \
      -H 'Accept: */*' \
      -H 'Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7' \
      -H 'Connection: keep-alive' \
      -H 'Content-Type: application/json' \
      -H 'Origin: https://topor-warp.vercel.app' \
      -H 'Referer: https://topor-warp.vercel.app/' \
      -H 'Sec-Fetch-Dest: empty' \
      -H 'Sec-Fetch-Mode: cors' \
      -H 'Sec-Fetch-Site: same-origin' \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36' \
      --data-raw '{"platform":"all"}' 2>/dev/null || echo ""
}

requestConfWARP3() {
    curl --connect-timeout 20 --max-time 60 -w "%{http_code}" 'https://warp-gen.vercel.app/generate-config' \
      -H 'Accept: */*' \
      -H 'Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7' \
      -H 'Connection: keep-alive' \
      -H 'Referer: https://warp-gen.vercel.app/' \
      -H 'Sec-Fetch-Dest: empty' \
      -H 'Sec-Fetch-Mode: cors' \
      -H 'Sec-Fetch-Site: same-origin' \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36' 2>/dev/null || echo ""
}

requestConfWARP4() {
    curl --connect-timeout 20 --max-time 60 -w "%{http_code}" 'https://config-generator-warp.vercel.app/warp' \
      -H 'Accept: */*' \
      -H 'Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7' \
      -H 'Connection: keep-alive' \
      -H 'Referer: https://config-generator-warp.vercel.app/' \
      -H 'Sec-Fetch-Dest: empty' \
      -H 'Sec-Fetch-Mode: cors' \
      -H 'Sec-Fetch-Site: same-origin' \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36' 2>/dev/null || echo ""
}

# Обработка ответа (extract body and HTTP code)
check_request() {
    response="$1"
    choice="$2"

    # извлекаем код ответа — последние 3 символа (если есть)
    response_code=$(printf "%s" "$response" | sed -n 's/.*\([0-9]\{3\}\)$/\1/p' || echo "")
    response_body=$(printf "%s" "$response" | sed 's/[0-9]\{3\}$//g' || echo "")

    if [ "$response_code" = "200" ]; then
        case "$choice" in
            1)
                status=$(printf "%s" "$response_body" | jq -r '.success' 2>/dev/null || echo "false")
                if [ "$status" = "true" ]; then
                    content=$(printf "%s" "$response_body" | jq -r '.content' 2>/dev/null || echo "")
                    configBase64=$(printf "%s" "$content" | jq -r '.configBase64' 2>/dev/null || echo "")
                    warpGen=$(printf "%s" "$configBase64" | base64 -d 2>/dev/null || echo "")
                    printf "%s" "$warpGen"
                else
                    echo "Error"
                fi
                ;;
            2)
                printf "%s" "$response_body"
                ;;
            3)
                content=$(printf "%s" "$response_body" | jq -r '.config' 2>/dev/null || echo "")
                printf "%s" "$content"
                ;;
            4)
                content=$(printf "%s" "$response_body" | jq -r '.content' 2>/dev/null || echo "")
                warp_config=$(printf "%s" "$content" | base64 -d 2>/dev/null || echo "")
                printf "%s" "$warp_config"
                ;;
            *)
                echo "Error"
                ;;
        esac
    else
        echo "Error"
    fi
}

checkAndAddDomainPermanentName() {
    nameRule="option name '$1'"
    str=$(grep -i "$nameRule" /etc/config/dhcp 2>/dev/null || true)
    if [ -z "$str" ]; then
        uci add dhcp domain
        uci set dhcp.@domain[-1].name="$1"
        uci set dhcp.@domain[-1].ip="$2"
        uci commit dhcp
    fi
}

install_youtubeunblock_packages() {
    echo "Install youtubeUnblock packages..."
    PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3+0 > max+0){max=$3+0; arch=$2}} END {print arch}')
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version' 2>/dev/null || echo "")
    BASE_URL="https://github.com/Waujito/youtubeUnblock/releases/download/v1.1.0/"
    PACK_NAME="youtubeUnblock"
    AWG_DIR="/tmp/$PACK_NAME"
    mkdir -p "$AWG_DIR"

    if opkg list-installed | grep -q "^$PACK_NAME"; then
        echo "$PACK_NAME already installed"
    else
        PACKAGES="kmod-nfnetlink-queue kmod-nft-queue kmod-nf-conntrack"
        for pkg in $PACKAGES; do
            if opkg list-installed | grep -q "^$pkg "; then
                echo "$pkg already installed"
            else
                echo "Installing $pkg ..."
                opkg install "$pkg" || { echo "Error installing $pkg. Please install it manually."; exit 1; }
            fi
        done

        YOUTUBEUNBLOCK_FILENAME="youtubeUnblock-1.0.0-10-f37c3dd-${PKGARCH}-openwrt-23.05.ipk"
        DOWNLOAD_URL="${BASE_URL}${YOUTUBEUNBLOCK_FILENAME}"
        echo "Downloading $YOUTUBEUNBLOCK_FILENAME ..."
        if download_file "$DOWNLOAD_URL" "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME"; then
            opkg install "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME" || { echo "Error installing youtubeUnblock"; exit 1; }
        else
            echo "Error downloading youtubeUnblock. Please install it manually."
            exit 1
        fi
    fi

    PACK_NAME="luci-app-youtubeUnblock"
    if opkg list-installed | grep -q "^$PACK_NAME"; then
        echo "$PACK_NAME already installed"
    else
        YOUTUBEUNBLOCK_FILENAME="luci-app-youtubeUnblock-1.0.0-10-f37c3dd.ipk"
        DOWNLOAD_URL="${BASE_URL}${YOUTUBEUNBLOCK_FILENAME}"
        echo "Downloading luci-app-youtubeUnblock ..."
        if download_file "$DOWNLOAD_URL" "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME"; then
            opkg install "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME" || { echo "Error installing luci-app-youtubeUnblock"; exit 1; }
        else
            echo "Error downloading luci-app-youtubeUnblock. Please install it manually."
            exit 1
        fi
    fi

    rm -rf "$AWG_DIR"
}

echo "Update list packages..."
opkg update >/dev/null 2>&1 || true

checkPackageAndInstall "coreutils-base64" "1"

# Установка AmneziaWG (kmod/tools/luci)
install_awg_packages

checkPackageAndInstall "jq" "1"
checkPackageAndInstall "curl" "1"
checkPackageAndInstall "unzip" "1"

###########
# manage podkop
manage_package "podkop" "enable" "stop"

# sing-box (версия фиксированная)
PACKAGE="sing-box"
REQUIRED_VERSION="1.11.15"

INSTALLED_VERSION=$(opkg list-installed | grep "^$PACKAGE" | cut -d ' ' -f 3 || true)
if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "$REQUIRED_VERSION" ]; then
    echo "Version package $PACKAGE not equal $REQUIRED_VERSION. Removing..."
    opkg remove --force-removal-of-dependent-packages "$PACKAGE" || true
fi

INSTALLED_VERSION=$(opkg list-installed | grep "^$PACKAGE" || true)
if [ -z "$INSTALLED_VERSION" ]; then
    PACK_NAME="sing-box"
    AWG_DIR="/tmp/$PACK_NAME"
    SINGBOX_FILENAME="sing-box_1.11.15_openwrt_aarch64_cortex-a53.ipk"
    BASE_URL="https://github.com/SagerNet/sing-box/releases/download/v1.11.15/"
    DOWNLOAD_URL="${BASE_URL}${SINGBOX_FILENAME}"
    mkdir -p "$AWG_DIR"
    echo "Downloading sing-box (note: filename is aarch64_cortex-a53) ..."
    if download_file "$DOWNLOAD_URL" "$AWG_DIR/$SINGBOX_FILENAME"; then
        opkg install "$AWG_DIR/$SINGBOX_FILENAME" || { echo "Error installing sing-box"; exit 1; }
    else
        echo "Error downloading sing-box. Please install it manually."
        exit 1
    fi
fi
###########

# dnsmasq-full
if opkg list-installed | grep -q "^dnsmasq-full"; then
    echo "dnsmasq-full already installed..."
else
    echo "Install dnsmasq-full..."
    cd /tmp/ || true
    opkg download dnsmasq-full || true
    opkg remove dnsmasq || true
    opkg install dnsmasq-full --cache /tmp/ || true

    [ -f /etc/config/dhcp-opkg ] && cp -f /etc/config/dhcp /etc/config/dhcp-old && mv -f /etc/config/dhcp-opkg /etc/config/dhcp
fi

printf "Setting confdir dnsmasq\n"
uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d' 2>/dev/null || true
uci commit dhcp 2>/dev/null || true

DIR="/etc/config"
DIR_BACKUP="/root/backup3"
config_files="network
firewall
https-dns-proxy
youtubeUnblock
dhcp"

checkPackageAndInstall "https-dns-proxy" "0"

if [ ! -d "$DIR_BACKUP" ]; then
    echo "Backup files..."
    mkdir -p "$DIR_BACKUP"
    for file in $config_files; do
        if [ -f "$DIR/$file" ]; then
            cp -f "$DIR/$file" "$DIR_BACKUP/$file"
        fi
    done
    echo "Replace configs..."
    for file in $config_files; do
        if [ "$file" = "https-dns-proxy" ]; then
            download_file "$CONFIG_URL/config_files/$file" "$DIR/$file" || true
        fi
    done
fi

echo "Configure dhcp..."
uci set dhcp.cfg01411c.strictorder='1' 2>/dev/null || true
uci set dhcp.cfg01411c.filter_aaaa='1' 2>/dev/null || true
uci commit dhcp 2>/dev/null || true

echo "Install opera-proxy client..."
/etc/init.d/vpn stop >/dev/null 2>&1 || true
rm -f /usr/bin/vpns /etc/init.d/vpn >/dev/null 2>&1 || true

OPERA_URL="https://github.com/NitroOxid/openwrt-opera-proxy-bin/releases/download/1.8.0/opera-proxy_1.8.0-1_aarch64_cortex-a53.ipk"
destination_file="/tmp/opera-proxy.ipk"
echo "Downloading opera-proxy..."
if download_file "$OPERA_URL" "$destination_file"; then
    echo "Installing opera-proxy..."
    opkg install "$destination_file" || true
else
    echo "Failed to download opera-proxy (file may be arch-specific)."
fi

# sing-box config
cat <<'EOF' > /etc/sing-box/config.json
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

echo "Setting sing-box..."
uci set sing-box.main.enabled='1' 2>/dev/null || true
uci set sing-box.main.user='root' 2>/dev/null || true
uci commit sing-box 2>/dev/null || true

# Добавление правил блокировки QUIC (если нет)
nameRule="option name 'Block_UDP_443'"
str=$(grep -i "$nameRule" /etc/config/firewall 2>/dev/null || true)
if [ -z "$str" ]; then
  echo "Add block QUIC..."
  uci add firewall rule
  uci set firewall.@rule[-1].name='Block_UDP_80'
  uci add_list firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].dest_port='80'
  uci set firewall.@rule[-1].target='REJECT'

  uci add firewall rule
  uci set firewall.@rule[-1].name='Block_UDP_443'
  uci add_list firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].dest_port='443'
  uci set firewall.@rule[-1].target='REJECT'
  uci commit firewall
fi

# --- Блок генерации/подключения AWG WARP ---
printf "\033[32;1mAutomatic generate config AmneziaWG WARP (n) or manual input parameters for AmneziaWG (y)...\033[0m\n"
countRepeatAWGGen=2
echo -n "Input manual parameters AmneziaWG? (y/n): "
read is_manual_input_parameters || is_manual_input_parameters="n"
currIter=0
isExit=0

while [ $currIter -lt $countRepeatAWGGen ] && [ "$isExit" = "0" ]; do
    currIter=$((currIter + 1))
    printf "\033[32;1mCreate and Check AWG WARP... Attempt #$currIter... Please wait...\033[0m\n"
    if [ "$is_manual_input_parameters" = "y" ] || [ "$is_manual_input_parameters" = "Y" ]; then
        echo -n "Enter the private key (from [Interface]): "
        read PrivateKey
        echo -n "Enter S1 value (from [Interface]): "
        read S1
        echo -n "Enter S2 value (from [Interface]): "
        read S2
        echo -n "Enter Jc value (from [Interface]): "
        read Jc
        echo -n "Enter Jmin value (from [Interface]): "
        read Jmin
        echo -n "Enter Jmax value (from [Interface]): "
        read Jmax
        echo -n "Enter H1 value (from [Interface]): "
        read H1
        echo -n "Enter H2 value (from [Interface]): "
        read H2
        echo -n "Enter H3 value (from [Interface]): "
        read H3
        echo -n "Enter H4 value (from [Interface]): "
        read H4

        while true; do
            echo -n "Enter the internal IP address with subnet, example 192.168.100.5/24 (from [Interface]): "
            read Address
            if echo "$Address" | egrep -oq '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$'; then
                break
            else
                echo "This IP is not valid. Please repeat"
            fi
        done

        echo -n "Enter the public key (from [Peer]): "
        read PublicKey
        echo -n "Enter Endpoint host without port (Domain or IP) (from [Peer]): "
        read EndpointIP
        echo -n "Enter Endpoint host port (from [Peer]) [51820]: "
        read EndpointPort

        DNS="1.1.1.1"
        MTU=1280
        AllowedIPs="0.0.0.0/0"
        isExit=1
    else
        warp_config="Error"
        printf "\033[32;1mRequest WARP config... Attempt #1\033[0m\n"
        result=$(requestConfWARP1)
        warpGen=$(check_request "$result" 1)
        if [ "$warpGen" = "Error" ]; then
            printf "\033[32;1mRequest WARP config... Attempt #2\033[0m\n"
            result=$(requestConfWARP2)
            warpGen=$(check_request "$result" 2)
            if [ "$warpGen" = "Error" ]; then
                printf "\033[32;1mRequest WARP config... Attempt #3\033[0m\n"
                result=$(requestConfWARP3)
                warpGen=$(check_request "$result" 3)
                if [ "$warpGen" = "Error" ]; then
                    printf "\033[32;1mRequest WARP config... Attempt #4\033[0m\n"
                    result=$(requestConfWARP4)
                    warpGen=$(check_request "$result" 4)
                    if [ "$warpGen" = "Error" ]; then
                        warp_config="Error"
                    else
                        warp_config="$warpGen"
                    fi
                else
                    warp_config="$warpGen"
                fi
            else
                warp_config="$warpGen"
            fi
        else
            warp_config="$warpGen"
        fi

        if [ "$warp_config" = "Error" ]; then
            printf "\033[32;1mGenerate config AWG WARP failed...Try again later...\033[0m\n"
            isExit=2
        else
            # Записываем warp_config во временный файл и парсим построчно
            printf "%s\n" "$warp_config" > "$TMP_WARP"
            while IFS= read -r line; do
                if echo "$line" | grep -q "="; then
                    key=$(echo "$line" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    # безопасно задать переменную (как в оригинале — eval)
                    eval "$key=\"\$value\""
                fi
            done < "$TMP_WARP"

            # Вытаскиваем нужные значения (как в оригинале)
            Address=$(printf "%s" "${Address:-}" | cut -d',' -f1)
            DNS=$(printf "%s" "${DNS:-}" | cut -d',' -f1)
            AllowedIPs=$(printf "%s" "${AllowedIPs:-}" | cut -d',' -f1)
            EndpointIP=$(printf "%s" "${Endpoint:-}" | cut -d':' -f1)
            EndpointPort=$(printf "%s" "${Endpoint:-}" | cut -d':' -f2)
        fi
    fi

    if [ "$isExit" = "2" ]; then
        isExit=0
    else
        printf "\033[32;1mCreate and configure tunnel AmneziaWG WARP...\033[0m\n"

        INTERFACE_NAME="awg10"
        CONFIG_NAME="amneziawg_awg10"
        PROTO="amneziawg"
        ZONE_NAME="awg"

        # Создание сетевого интерфейса
        uci set network."${INTERFACE_NAME}"=interface 2>/dev/null || true
        uci set network."${INTERFACE_NAME}".proto="$PROTO" 2>/dev/null || true

        # Если нет секции конфига peer'а — добавляем (оригинальная логика)
        if ! uci show network | grep -q "${CONFIG_NAME}"; then
            # добавляем произвольную секцию (оставляем поведение близким к оригиналу)
            uci add network "$CONFIG_NAME" 2>/dev/null || true
        fi

        [ -n "${PrivateKey:-}" ] && uci set network."${INTERFACE_NAME}".private_key="$PrivateKey" 2>/dev/null || true
        uci del_list network."${INTERFACE_NAME}".addresses >/dev/null 2>&1 || true
        [ -n "${Address:-}" ] && uci add_list network."${INTERFACE_NAME}".addresses="$Address" 2>/dev/null || true
        [ -n "${MTU:-}" ] && uci set network."${INTERFACE_NAME}".mtu="$MTU" 2>/dev/null || true
        [ -n "${Jc:-}" ] && uci set network."${INTERFACE_NAME}".awg_jc="$Jc" 2>/dev/null || true
        [ -n "${Jmin:-}" ] && uci set network."${INTERFACE_NAME}".awg_jmin="$Jmin" 2>/dev/null || true
        [ -n "${Jmax:-}" ] && uci set network."${INTERFACE_NAME}".awg_jmax="$Jmax" 2>/dev/null || true
        [ -n "${S1:-}" ] && uci set network."${INTERFACE_NAME}".awg_s1="$S1" 2>/dev/null || true
        [ -n "${S2:-}" ] && uci set network."${INTERFACE_NAME}".awg_s2="$S2" 2>/dev/null || true
        [ -n "${H1:-}" ] && uci set network."${INTERFACE_NAME}".awg_h1="$H1" 2>/dev/null || true
        [ -n "${H2:-}" ] && uci set network."${INTERFACE_NAME}".awg_h2="$H2" 2>/dev/null || true
        [ -n "${H3:-}" ] && uci set network."${INTERFACE_NAME}".awg_h3="$H3" 2>/dev/null || true
        [ -n "${H4:-}" ] && uci set network."${INTERFACE_NAME}".awg_h4="$H4" 2>/dev/null || true
        uci set network."${INTERFACE_NAME}".nohostroute='1' 2>/dev/null || true

        # Добавляем peer (как в оригинале — сохраняем стиль)
        uci set network.@${CONFIG_NAME}[-1].description="${INTERFACE_NAME}_peer" 2>/dev/null || true
        [ -n "${PublicKey:-}" ] && uci set network.@${CONFIG_NAME}[-1].public_key="$PublicKey" 2>/dev/null || true
        [ -n "${EndpointIP:-}" ] && uci set network.@${CONFIG_NAME}[-1].endpoint_host="$EndpointIP" 2>/dev/null || true
        [ -n "${EndpointPort:-}" ] && uci set network.@${CONFIG_NAME}[-1].endpoint_port="$EndpointPort" 2>/dev/null || true
        uci set network.@${CONFIG_NAME}[-1].persistent_keepalive='25' 2>/dev/null || true
        uci set network.@${CONFIG_NAME}[-1].allowed_ips='0.0.0.0/0' 2>/dev/null || true
        uci set network.@${CONFIG_NAME}[-1].route_allowed_ips='0' 2>/dev/null || true
        uci commit network 2>/dev/null || true

        # Создаем зону fw если нужно
        if ! uci show firewall | grep -q "@zone.*name='${ZONE_NAME}'"; then
            printf "\033[32;1mZone Create\033[0m\n"
            uci add firewall zone
            uci set firewall.@zone[-1].name="$ZONE_NAME"
            uci set firewall.@zone[-1].network="$INTERFACE_NAME"
            uci set firewall.@zone[-1].forward='REJECT'
            uci set firewall.@zone[-1].output='ACCEPT'
            uci set firewall.@zone[-1].input='REJECT'
            uci set firewall.@zone[-1].masq='1'
            uci set firewall.@zone[-1].mtu_fix='1'
            uci set firewall.@zone[-1].family='ipv4'
            uci commit firewall
        fi

        # forwarding
        if ! uci show firewall | grep -q "@forwarding.*name='${ZONE_NAME}'"; then
            printf "\033[32;1mConfigured forwarding\033[0m\n"
            uci add firewall forwarding
            uci set firewall.@forwarding[-1]=forwarding
            uci set firewall.@forwarding[-1].name="${ZONE_NAME}"
            uci set firewall.@forwarding[-1].dest=${ZONE_NAME}
            uci set firewall.@forwarding[-1].src='lan'
            uci set firewall.@forwarding[-1].family='ipv4'
            uci commit firewall
        fi

        # Добавляем интерфейс в зону, если отсутствует
        ZONES=$(uci show firewall | grep "zone$" | cut -d'=' -f1 || true)
        for zone in $ZONES; do
            CURR_ZONE_NAME=$(uci get $zone.name 2>/dev/null || true)
            if [ "$CURR_ZONE_NAME" = "$ZONE_NAME" ]; then
                if ! uci get $zone.network 2>/dev/null | grep -q "$INTERFACE_NAME"; then
                    uci add_list $zone.network="$INTERFACE_NAME" 2>/dev/null || true
                    uci commit firewall 2>/dev/null || true
                fi
            fi
        done

        if [ "$currIter" = "1" ]; then
            /etc/init.d/firewall restart >/dev/null 2>&1 || true
        fi

        # Включаем/выключаем интерфейс
        ifdown "$INTERFACE_NAME" >/dev/null 2>&1 || true
        ifup "$INTERFACE_NAME" >/dev/null 2>&1 || true

        printf "\033[32;1mWait up AWG WARP 10 second...\033[0m\n"
        sleep 10

        pingAddress="8.8.8.8"
        if ping -c 1 -I "$INTERFACE_NAME" "$pingAddress" >/dev/null 2>&1; then
            isExit=1
        else
            isExit=0
        fi
    fi
done

varByPass=0
if [ "$isExit" = "1" ]; then
    printf "\033[32;1mAWG WARP well work...\033[0m\n"
    varByPass=1
else
    printf "\033[32;1mAWG WARP not work...Try work youtubeunblock...Please wait...\033[0m\n"
    install_youtubeunblock_packages
    opkg upgrade youtubeUnblock || true
    opkg upgrade luci-app-youtubeUnblock || true
    manage_package "youtubeUnblock" "enable" "start"
    download_file "$CONFIG_URL/config_files/youtubeUnblockSecond" "/etc/config/youtubeUnblock" || true
    /etc/init.d/youtubeUnblock restart >/dev/null 2>&1 || true

    curl -f -o /dev/null -k --connect-to ::google.com -L -H "Host: mirror.gcr.io" --max-time 360 https://test.googlevideo.com/v2/cimg/android/blobs/sha256:6fd8bdac3da660bde7bd0b6f2b6a46e1b686afb74b9a4614def32532b73f5eaa >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        printf "\033[32;1myoutubeUnblock well work...\033[0m\n"
        varByPass=2
    else
        manage_package "youtubeUnblock" "disable" "stop"
        printf "\033[32;1myoutubeUnblock not work...Try opera proxy...\033[0m\n"
        /etc/init.d/sing-box restart >/dev/null 2>&1 || true
        sing-box tools fetch ifconfig.co -D /etc/sing-box/ >/dev/null 2>&1 || true
        if [ $? -eq 0 ]; then
            printf "\033[32;1mOpera proxy well work...\033[0m\n"
            varByPass=3
        else
            printf "\033[32;1mOpera proxy not work...Try custom settings router to bypass the locks... Recommendation: buy 'VPS' and set up 'vless'\033[0m\n"
            exit 1
        fi
    fi
fi

printf  "\033[32;1mRestart service dnsmasq, odhcpd...\033[0m\n"
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/odhcpd restart >/dev/null 2>&1 || true

path_podkop_config="/etc/config/podkop"
path_podkop_config_backup="/root/podkop"
URL_PODKOP="$PODKOP_URL"

case $varByPass in
1)
    nameFileReplacePodkop="podkop"
    printf  "\033[32;1mStop and disabled service 'youtubeUnblock' and 'ruantiblock'...\033[0m\n"
    manage_package "youtubeUnblock" "disable" "stop"
    manage_package "ruantiblock" "disable" "stop"
    ;;
2)
    nameFileReplacePodkop="podkopSecond"
    printf  "\033[32;1mStop and disabled service 'ruantiblock'...\033[0m\n"
    manage_package "ruantiblock" "disable" "stop"
    ;;
3)
    nameFileReplacePodkop="podkopSecondYoutube"
    printf  "\033[32;1mStop and disabled service 'youtubeUnblock' and 'ruantiblock'...\033[0m\n"
    manage_package "youtubeUnblock" "disable" "stop"
    manage_package "ruantiblock" "disable" "stop"
    ;;
*)
    nameFileReplacePodkop="podkop"
    ;;
esac

PACKAGE="podkop"
REQUIRED_VERSION="0.2.5-1"

INSTALLED_VERSION=$(opkg list-installed | grep "^$PACKAGE" | cut -d ' ' -f 3 || true)
if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "$REQUIRED_VERSION" ]; then
    echo "Version package $PACKAGE not equal $REQUIRED_VERSION. Removed packages..."
    opkg remove --force-removal-of-dependent-packages "$PACKAGE" || true
fi

if [ -f "/etc/init.d/podkop" ]; then
    printf "Podkop installed. Reconfigured on AWG WARP and Opera Proxy? (y/n): \n"
    echo -n ""
    read is_reconfig_podkop || is_reconfig_podkop="y"
    if [ "$is_reconfig_podkop" = "y" ] || [ "$is_reconfig_podkop" = "Y" ]; then
        cp -f "$path_podkop_config" "$path_podkop_config_backup" || true
        download_file "$URL_PODKOP/config_files/$nameFileReplacePodkop" "$path_podkop_config" || true
        echo "Backup of your config in path '$path_podkop_config_backup'"
        echo "Podkop reconfigured..."
    fi
else
    printf "\033[32;1mInstall and configure PODKOP (a tool for point routing of traffic)?? (y/n): \033[0m\n"
    echo -n ""
    read is_install_podkop || is_install_podkop="y"
    if [ "$is_install_podkop" = "y" ] || [ "$is_install_podkop" = "Y" ]; then
        DOWNLOAD_DIR="/tmp/podkop"
        mkdir -p "$DOWNLOAD_DIR"
        podkop_files="podkop_0.2.5-1_all.ipk
            luci-app-podkop_0.2.5_all.ipk
            luci-i18n-podkop-ru_0.2.5.ipk"
        for file in $podkop_files; do
            echo "Download $file..."
            download_file "$URL_PODKOP/podkop_packets/$file" "$DOWNLOAD_DIR/$file" || true
        done
        opkg install $DOWNLOAD_DIR/podkop*.ipk || true
        opkg install $DOWNLOAD_DIR/luci-app-podkop*.ipk || true
        opkg install $DOWNLOAD_DIR/luci-i18n-podkop-ru*.ipk || true
        rm -f $DOWNLOAD_DIR/podkop*.ipk $DOWNLOAD_DIR/luci-app-podkop*.ipk $DOWNLOAD_DIR/luci-i18n-podkop-ru*.ipk >/dev/null 2>&1 || true
        download_file "$URL_PODKOP/config_files/$nameFileReplacePodkop" "$path_podkop_config" || true
        echo "Podkop installed.."
    fi
fi

printf  "\033[32;1mStart and enable service 'https-dns-proxy'...\033[0m\n"
manage_package "https-dns-proxy" "enable" "start"

# Удаляем строку cron если есть
str=$(grep -i "0 4 \* \* \* wget -O - $CONFIG_URL/configure_zaprets.sh | sh" /etc/crontabs/root 2>/dev/null || true)
if [ -n "$str" ]; then
    grep -v "0 4 \* \* \* wget -O - $CONFIG_URL/configure_zaprets.sh | sh" /etc/crontabs/root > /etc/crontabs/temp 2>/dev/null || true
    cp -f "/etc/crontabs/temp" "/etc/crontabs/root" || true
    rm -f "/etc/crontabs/temp" >/dev/null 2>&1 || true
fi

printf  "\033[32;1mService Podkop and Sing-Box restart...\033[0m\n"
# enable/restart sing-box & podkop
[ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box enable >/dev/null 2>&1 || true
[ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box restart >/dev/null 2>&1 || true
[ -x /etc/init.d/podkop ] && /etc/init.d/podkop enable >/dev/null 2>&1 || true
[ -x /etc/init.d/podkop ] && /etc/init.d/podkop restart >/dev/null 2>&1 || true

printf  "\033[32;1mConfigured completed...\033[0m\n"
