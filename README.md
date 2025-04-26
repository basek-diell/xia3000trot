# X3000_configs

СКРИПТЫ ДЛЯ ВВОДА В ТЕРМИНЕЛА OPENWRT XIAOMI 3000T НА ДРУГИХ НЕ ПРОВЕРЯЛОСЬ

### Разблокировка сайтов с помощью youtubeUnblock + https-dns-proxy
Разблокировка сайтов с помощью подмены **Hello пакетов DPI** (приложение **youtubeUnblock**) + точечное перенаправление доменов, которые находятся в **геоблоке на ComssDNS** (через перенаправление dnsmasq и пакет **https-dns-proxy**) + добавление правил для **блокировки протокола QUIC** на уровне роутера

1. скрипт для автоматической настройки httрs-dns-рrоxy, youtubeunblock, dhcp пакетов для обхода блокировок без использования VPN сервисов и поломки остальных сервисов.


wget -O - https://raw.githubusercontent.com/basek-diell/xia3000t./refs/heads/main/configure_zaprets.sh | sh


для возврата как было


      wget -O - https://raw.githubusercontent.com/basek-diell/xia3000t./refs/heads/main/off_configure_zaprets.sh | sh
      
      
2. 

