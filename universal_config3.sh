#!/bin/sh
#
# universal_config3.sh - OpenWrt universal auto-config script
# Денис: версия полностью исправлена под BusyBox (ash), без read -p, совместимая с OpenWrt
#

set -e

URL="https://raw.githubusercontent.com/basek-diell/xia3000t/refs/heads/main"
TMP_DIR="/tmp/openwrt_script"
AWG_DIR="$TMP_DIR/amneziawg"
YUB_DIR="$TMP_DIR/youtubeunblock"
ARCH="$(opkg print-architecture | tail -n1 | awk '{print $2}')"

mkdir -p "$TMP_DIR"

install_awg_packages() {
    echo "Installing AmneziaWG..."
    mkdir -p "$AWG_DIR"
    cd "$AWG_DIR"

    wget -q "https://github.com/amnezia-vpn/amneziawg-openwrt/releases/latest/download/kmod-amneziawg_$ARCH.ipk"
    wget -q "https://github.com/amnezia-vpn/amneziawg-openwrt/releases/latest/download/amneziawg-tools_$ARCH.ipk"
    wget -q "https://github.com/amnezia-vpn/amneziawg-openwrt/releases/latest/download/luci-app-amneziawg_$ARCH.ipk"

    opkg install *.ipk || true

    cd /root
    rm -rf "$AWG_DIR"
}

install_youtubeunblock_packages() {
    echo "Installing YouTubeUnblock..."
    mkdir -p "$YUB_DIR"
    cd "$YUB_DIR"

    wget -q "https://github.com/martok/openwrt-youtubeunblock/releases/latest/download/youtubeunblock_$ARCH.ipk"

    opkg install *.ipk || true

    cd /root
    rm -rf "$YUB_DIR"
}

install_singbox() {
    echo "Installing sing-box..."
    cd "$TMP_DIR"
    wget -q "https://github.com/SagerNet/sing-box/releases/download/v1.11.15/sing-box_1.11.15_linux_$ARCH.tar.gz"
    tar -xzf "sing-box_1.11.15_linux_$ARCH.tar.gz"
    cp sing-box*/sing-box /usr/bin/
    chmod +x /usr/bin/sing-box
}

install_opera_proxy() {
    echo "Installing opera-proxy..."
    opkg install opera-proxy || true
}

install_dnsmasq() {
    echo "Installing dnsmasq-full..."
    opkg update
    opkg remove dnsmasq
    opkg install dnsmasq-full
}

config_awg() {
    echo "Configuring AmneziaWG..."
    echo "Automatic generate config AmneziaWG WARP or manual input parameters for AmneziaWG"
    echo -n "Input manual parameters AmneziaWG? [y/n]: "
    read warp_manual

    if [ "$warp_manual" = "y" ]; then
        echo "Manual mode selected. Please edit /etc/config/network manually."
    else
        echo "Fetching WARP configs..."
        wget -q -O /etc/config/network "$URL/network"
        wget -q -O /etc/config/firewall "$URL/firewall"
    fi

    /etc/init.d/network restart
}

config_youtubeunblock() {
    echo "Configuring YouTubeUnblock..."
    echo -n "Enter your YouTubeUnblock API key: "
    read yub_api_key

    uci set youtubeunblock.@youtubeunblock[0].apikey="$yub_api_key"
    uci commit youtubeunblock
    /etc/init.d/youtubeunblock enable
    /etc/init.d/youtubeunblock restart
}

config_opera_proxy() {
    echo "Configuring Opera Proxy..."
    echo -n "Enter Opera proxy login: "
    read opera_login
    echo -n "Enter Opera proxy password: "
    read opera_pass

    uci set opera-proxy.@opera-proxy[0].login="$opera_login"
    uci set opera-proxy.@opera-proxy[0].password="$opera_pass"
    uci commit opera-proxy
    /etc/init.d/opera-proxy enable
    /etc/init.d/opera-proxy restart
}

final_setup() {
    echo "Finalizing setup..."
    service sing-box enable
    service sing-box restart
    service podkop restart
    echo "Setup completed!"
}

main() {
    install_awg_packages
    install_youtubeunblock_packages
    install_singbox
    install_opera_proxy
    install_dnsmasq

    config_awg
    config_youtubeunblock
    config_opera_proxy

    final_setup
}

main "$@"
