#!/bin/sh

URL="https://raw.githubusercontent.com/basek-diell/xia3000t./refs/heads/main"
DIR="/etc/config"
DIR_BACKUP="/root/backup"
config_files="youtubeUnblock https-dns-proxy"

# ===== НАЧАЛО функций =====

manage_package() {
  local name="$1"
  local autostart="$2"
  local process="$3"

  if opkg list-installed | grep -q "^$name"; then
    if /etc/init.d/$name enabled; then
      [ "$autostart" = "disable" ] && /etc/init.d/$name disable
    else
      [ "$autostart" = "enable" ] && /etc/init.d/$name enable
    fi

    if pidof $name > /dev/null; then
      [ "$process" = "stop" ] && /etc/init.d/$name stop
    else
      [ "$process" = "start" ] && /etc/init.d/$name start
    fi
  fi
}

install_youtubeunblock_packages() {
  PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
  BASE_URL="https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/"
  AWG_DIR="/tmp/youtubeUnblock"
  mkdir -p "$AWG_DIR"

  if ! opkg list-installed | grep -q youtubeUnblock; then
    PACKAGES="kmod-nfnetlink-queue kmod-nft-queue kmod-nf-conntrack"
    for pkg in $PACKAGES; do
      opkg list-installed | grep -q "^$pkg " || opkg install $pkg || exit 1
    done

    YOUTUBEUNBLOCK_FILENAME="youtubeUnblock-1.0.0-10-f37c3dd-${PKGARCH}-openwrt-23.05.ipk"
    wget -O "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME" "$BASE_URL$YOUTUBEUNBLOCK_FILENAME" || exit 1
    opkg install "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME" || exit 1
  fi

  if ! opkg list-installed | grep -q luci-app-youtubeUnblock; then
    YOUTUBEUNBLOCK_GUI="luci-app-youtubeUnblock-1.0.0-10-f37c3dd.ipk"
    wget -O "$AWG_DIR/$YOUTUBEUNBLOCK_GUI" "$BASE_URL$YOUTUBEUNBLOCK_GUI" || exit 1
    opkg install "$AWG_DIR/$YOUTUBEUNBLOCK_GUI" || exit 1
  fi

  rm -rf "$AWG_DIR"
}

checkPackageAndInstall() {
  local name="$1"
  local isRequired="$2"

  if ! opkg list-installed | grep -q "$name"; then
    opkg install "$name"
    [ "$isRequired" = "1" ] && [ $? -ne 0 ] && exit 1
  fi
}

# ===== КОНЕЦ функций =====

# Основной код

echo "Update list packages..."
opkg update

checkPackageAndInstall "https-dns-proxy" "1"
checkPackageAndInstall "luci-app-https-dns-proxy" "0"
checkPackageAndInstall "luci-i18n-https-dns-proxy-ru" "0"

install_youtubeunblock_packages

opkg upgrade youtubeUnblock
opkg upgrade luci-app-youtubeUnblock

if [ ! -d "$DIR_BACKUP" ]; then
  echo "Backup files..."
  mkdir -p "$DIR_BACKUP"
  for file in $config_files; do
    cp -f "$DIR/$file" "$DIR_BACKUP/$file"
  done

  echo "Replace configs..."
  for file in $config_files; do
    wget -O "$DIR/$file" "$URL/config_files/1/$file"
  done
fi

if ! grep -q "option name 'Block_UDP_443'" /etc/config/firewall; then
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
  service firewall restart
fi

cronTask="0 4 * * * wget -O - $URL/configure_zaprets.sh | sh"
if ! grep -q "$cronTask" /etc/crontabs/root; then
  echo "Add cron task auto run configure_zapret..."
  echo "$cronTask" >> /etc/crontabs/root
fi

manage_package "podkop" "disable" "stop"
manage_package "ruantiblock" "disable" "stop"
manage_package "https-dns-proxy" "enable" "start"
manage_package "youtubeUnblock" "enable" "start"

echo "Restart services..."
service youtubeUnblock restart
service https-dns-proxy restart
service dnsmasq restart
service odhcpd restart

echo "\033[32;1mConfigured completed...\033[0m"
