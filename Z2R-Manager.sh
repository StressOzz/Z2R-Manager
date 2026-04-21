#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"

BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"
PKG_MANAGER="opkg list-installed 2>/dev/null"

pkg_remove="opkg remove --force-depends $pkg_name"

PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }

ARCH="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"
VER="$(awk -F\' '/DISTRIB_RELEASE/ {print $2}' /etc/openwrt_release | cut -d. -f1)"

[ "$VER" = "24" ] || { echo -e "\n${RED}Неподдерживаемая версия OpenWrt: ${NC}$VER\n"; exit 1; }
[ "$ARCH" = "aarch64_cortex-a53" ] || { echo -e "\n${RED}Неподдерживаемая архитектура: ${NC}$ARCH\n"; exit 1; }

if ! grep -q "routerich/packages.routerich" /etc/opkg/customfeeds.conf 2>/dev/null; then
    echo -e "\n${CYAN}Добавляем пакеты Routerich${NC}"
    sed -i 's/option check_signature/# option check_signature/' /etc/opkg.conf
    echo 'src/gz routerich https://github.com/routerich/packages.routerich/raw/24.10.6/routerich' > /etc/opkg/customfeeds.conf
    opkg update
fi

is_routerich() {
    grep -q "routerich/packages.routerich" /etc/opkg/customfeeds.conf 2>/dev/null
}

routerich_add() {
    sed -i 's/option check_signature/# option check_signature/' /etc/opkg.conf
    echo 'src/gz routerich https://github.com/routerich/packages.routerich/raw/24.10.6/routerich' > /etc/opkg/customfeeds.conf
    opkg update
    echo -e "\n${GREEN}Пакеты ${NC}Routerich${GREEN} добавлены!${NC}"
	PAUSE
}

routerich_remove() {
    rm -f /etc/opkg/customfeeds.conf
    sed -i 's/# option check_signature/option check_signature/' /etc/opkg.conf
    opkg update
    echo -e "\n${GREEN}Пакеты ${NC}Routerich${GREEN} удалены!${NC}"
	PAUSE
}


is_installed() {
    opkg list-installed | grep -q "$1"
}

install_zapret() {
    opkg update
    opkg install zapret2 luci-app-zapret2
wget -qO /opt/zapret2/ipset/zapret_hosts_user_exclude.txt https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt
sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2
/etc/init.d/zapret2 restart >/dev/null 2>&1
    echo -e "\nZapret2 ${GREEN}установлен${NC}"
	PAUSE
}

remove_zapret() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zapret2 zapret2
    rm -f /etc/config/zapret2
    rm -rf /opt/zapret2
    echo -e "\nZapret2 ${GREEN}удалён${NC}"
	PAUSE
}

install_zero() {
    opkg update
    opkg install zeroblock luci-app-zeroblock
	sed -i "/option api /s/'v2'/'v1'/" /etc/config/zeroblock
    echo -e "\nZeroBlock ${GREEN}установлен!${NC}"
	PAUSE
}

remove_zero() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zeroblock zeroblock
    rm -rf /etc/config/zeroblock*
    rm -rf /etc/zeroblock*
    rm -rf /usr/bin/zeroblock*
    echo -e "\n${GREEN}ZeroBlock удалён${NC}"
	PAUSE
}

###################################################################################################################################################
install_AWG() {

echo -e "\n${MAGENTA}Устанавливаем AWG и интерфейс AWG${NC}"

VERSION=$(ubus call system board | jsonfilter -e '@.release.version' | tr -d '\n')
MAJOR_VERSION=$(echo "$VERSION" | cut -d '.' -f1)

if [ -z "$VERSION" ]; then
echo -e "\n${RED}Не удалось определить версию OpenWrt!${NC}"
PAUSE
return
fi

TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)

install_pkg() {
local pkgname=$1
local filename="${pkgname}${PKGPOSTFIX}"
local url="${BASE_URL}v${VERSION}/${filename}"

echo -e "${CYAN}Скачиваем:${NC} $filename"

if wget -O "$tmpDIR/$filename" "$url" >/dev/null 2>&1; then
echo -e "${CYAN}Устанавливаем:${NC} $pkgname"
if ! $INSTALL_CMD "$tmpDIR/$filename" >/dev/null 2>&1; then
echo -e "\n${RED}Ошибка установки $pkgname!${NC}"
PAUSE
return 1
fi
else
echo -e "\n${RED}Ошибка! Не удалось скачать $filename${NC}"
PAUSE
return 1
fi
}

if [ "$MAJOR_VERSION" -ge 25 ] 2>/dev/null; then
PKGARCH=$(cat /etc/apk/arch)
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.apk"
INSTALL_CMD="apk add --allow-untrusted"
else
echo -e "${CYAN}Обновляем список пакетов${NC}"
opkg update >/dev/null 2>&1 || {
echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}"
PAUSE
return
}
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max=$3; arch=$2}} END {print arch}')
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
INSTALL_CMD="opkg install"
fi

install_pkg "kmod-amneziawg"
install_pkg "amneziawg-tools"
install_pkg "luci-proto-amneziawg"
install_pkg "luci-i18n-amneziawg-ru"

echo -e "${CYAN}Создаем интерфейс AWG${NC}"

if uci show network.$IF_NAME >/dev/null 2>&1; then
echo -e "${RED}Интерфейс уже существует!${NC}"
else
uci set network.$IF_NAME=interface
uci set network.$IF_NAME.proto=$PROTO
uci set network.$IF_NAME.device=$DEV_NAME
uci commit network
fi

echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart >/dev/null 2>&1

echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}установлены!${NC}\n"
echo -e "${YELLOW}Необходимо в LuCI в интерфейс AWG загрузить конфиг:${NC}\nNetwork ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration… ${GREEN}→${NC} Save ${GREEN}→${NC} Save&Apply"
PAUSE
}

uninstall_AWG() {
echo -e "\n${MAGENTA}Удаление AWG и интерфейс AWG${NC}"
echo -e "${CYAN}Удаляем ${NC}AWG"
pkg_remove luci-i18n-amneziawg-ru
pkg_remove luci-proto-amneziawg
pkg_remove amneziawg-tools
pkg_remove kmod-amneziawg

uci delete network.AWG >/dev/null 2>&1
uci commit network >/dev/null 2>&1

for peer in $(uci show network | grep "interface='AWG'" | cut -d. -f2); do
    uci delete network.$peer
done
uci commit network >/dev/null 2>&1
echo -e "${CYAN}Удаляем ${NC}интерфейс AWG"
echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart

echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}удалены!${NC}"
PAUSE
}

###################################################################################################################################################

PODPISKA() {
    echo -ne "\n${YELLOW}Введите ссылку на подписку (${CYAN}https://...${YELLOW}): ${NC}"
    read -r SUB_URL
    [ -z "$SUB_URL" ] && echo -e "\n${RED}Ошибка! Ссылка пустая!${NC}" && PAUSE && return
    
cat > /etc/config/zeroblock << EOF
config settings 'settings'
	option log_level 'warn'
	option dns_type 'doh'
	option dns_server '8.8.8.8'
	option bootstrap_dns_server '77.88.8.8'
	option dns_rewrite_ttl '60'
	option dns_strategy 'ipv4_only'
	option clash_api_enabled '1'
	option clash_api_port '9090'
	option tproxy_mark '0x10000'
	option direct_mark '0x20000'
	option bt_mark '0x40000'
	option ctmark_dns '0x10000'
	option ctmark_bt '0x40000'
	option disable_quic '1'
	option desync_mark '0x40000000'
	option update_interval '1d'
	option timeout_dnsmasq_restart '15'
	option dns_hijack '1'
	option auto_fallback_two_stage '1'
	option discord_voice '1'
	option exclude_bittorrent '1'
	option exclude_ntp '1'
	option fakeip_query_type_filter '1'
	option dont_touch_dhcp '0'
	option enable_output_network_interface '0'
	option proxy_router_traffic '0'
	option enable_bad_interface_monitoring '0'
	option download_lists_via_proxy '0'
	option ipv6_enabled '0'
	option singbox_logging '0'
	option xray_logging '0'
	option trusttunnel_logging '0'
	option xray_path '/usr/bin/xray'
	option trusttunnel_path '/usr/bin/trusttunnel_client'
	option custom_config_dir '/etc/zeroblock/sing-box.d'
	option dpi_check_timeout '15'
	option singbox_startup_timeout '30000'
	option xray_startup_timeout '10000'
	option subscription_timeout '30000'
	option subscription_user_agent 'clash-verge/v2.0.0'
	option update_time '09:00'
	option api 'v1'
	option youtube_cdn_url 'https://test.googlevideo.com/v2/cimg/android/blobs/sha256:6fd8bdac3da660bde7bd0b6f2b6a46e1b686afb74b9a4614def32532b73f5eaa'
	option youtube_connect_host 'google.com'
	option youtube_host_header 'mirror.gcr.io'
	option youtube_threshold_mb '5'
	option youtube_timeout '10'
	option subscription_max_proxies '100'
	list source_network_interfaces 'br-lan'
	option testing_url 'http://www.gstatic.com/generate_204'

config section 'StressKVN'
	option connection_type 'proxy'
	option proxy_config_type 'subscription'
	list subscription_url '$SUB_URL'
	option disable_fakeip '0'
	option enabled '1'
	list subscription_ignore_tags '⬇️'
	list subscription_ignore_tags 'Auto'
	list subscription_ignore_tags 'LTE'
	list subscription_ignore_tags 'Авто'
	list community_lists 'block'
	list community_lists 'cloudflare'
	list community_lists 'cloudfront'
	list community_lists 'digitalocean'
	list community_lists 'discord'
	list community_lists 'geoblock'
	list community_lists 'google_ai'
	list community_lists 'google_meet'
	list community_lists 'google_play'
	list community_lists 'hdrezka'
	list community_lists 'hetzner'
	list community_lists 'hodca'
	list community_lists 'meta'
	list community_lists 'news'
	list community_lists 'ovh'
	list community_lists 'porn'
	list community_lists 'roblox'
	list community_lists 'russia_inside'
	list community_lists 'telegram'
	list community_lists 'tiktok'
	list community_lists 'twitter'
	list community_lists 'youtube'
	option urltest_check_interval '3m'
	option urltest_tolerance '150'

config auto_config 'auto_config'
	option monitor_time '03:00'
	option monitor_interval 'daily'
	option enable_monitoring '1'

config dashboard 'dashboard'

config diagnostic 'diagnostic'
EOF

echo -e "${CYAN}Применяем конфигурацию${NC}"
/etc/init.d/zeroblock reload >/dev/null 2>&1
sleep 2
echo -e "${CYAN}Перезапускаем сервис${NC}"
/etc/init.d/zeroblockrestart >/dev/null 2>&1
echo -e "VPN ${GREEN}подписка интегрирована в ${NC}ZeroBlock${GREEN}!${NC}\n"
PAUSE
}
###################################################################################################################################################
AWG_INT() {
echo -e "\n${MAGENTA}Интегрируем AWG в ZeroBlock${NC}"


cat > /etc/config/zeroblock << EOF
config settings 'settings'
	option log_level 'warn'
	option dns_type 'doh'
	option dns_server '8.8.8.8'
	option bootstrap_dns_server '77.88.8.8'
	option dns_rewrite_ttl '60'
	option dns_strategy 'ipv4_only'
	option clash_api_enabled '1'
	option clash_api_port '9090'
	option tproxy_mark '0x10000'
	option direct_mark '0x20000'
	option bt_mark '0x40000'
	option ctmark_dns '0x10000'
	option ctmark_bt '0x40000'
	option disable_quic '1'
	option desync_mark '0x40000000'
	option update_interval '1d'
	option timeout_dnsmasq_restart '15'
	option dns_hijack '1'
	option auto_fallback_two_stage '1'
	option discord_voice '1'
	option exclude_bittorrent '1'
	option exclude_ntp '1'
	option fakeip_query_type_filter '1'
	option dont_touch_dhcp '0'
	option enable_output_network_interface '0'
	option proxy_router_traffic '0'
	option enable_bad_interface_monitoring '0'
	option download_lists_via_proxy '0'
	option ipv6_enabled '0'
	option singbox_logging '0'
	option xray_logging '0'
	option trusttunnel_logging '0'
	option xray_path '/usr/bin/xray'
	option trusttunnel_path '/usr/bin/trusttunnel_client'
	option custom_config_dir '/etc/zeroblock/sing-box.d'
	option dpi_check_timeout '15'
	option singbox_startup_timeout '30000'
	option xray_startup_timeout '10000'
	option subscription_timeout '30000'
	option subscription_user_agent 'clash-verge/v2.0.0'
	option update_time '09:00'
	option api 'v1'
	option youtube_cdn_url 'https://test.googlevideo.com/v2/cimg/android/blobs/sha256:6fd8bdac3da660bde7bd0b6f2b6a46e1b686afb74b9a4614def32532b73f5eaa'
	option youtube_connect_host 'google.com'
	option youtube_host_header 'mirror.gcr.io'
	option youtube_threshold_mb '5'
	option youtube_timeout '10'
	option subscription_max_proxies '100'
	list source_network_interfaces 'br-lan'
	option testing_url 'http://www.gstatic.com/generate_204'

config auto_config 'auto_config'
	option monitor_time '03:00'
	option monitor_interval 'daily'
	option enable_monitoring '1'

config dashboard 'dashboard'

config diagnostic 'diagnostic'

config section 'AWG'
	option connection_type 'vpn'
	option interface 'AWG'
	option disable_fakeip '1'
	list community_lists 'anime'
	list community_lists 'block'
	list community_lists 'cloudflare'
	list community_lists 'cloudfront'
	list community_lists 'digitalocean'
	list community_lists 'discord'
	list community_lists 'geoblock'
	list community_lists 'google_ai'
	list community_lists 'google_meet'
	list community_lists 'google_play'
	list community_lists 'hdrezka'
	list community_lists 'hetzner'
	list community_lists 'hodca'
	list community_lists 'meta'
	list community_lists 'news'
	list community_lists 'ovh'
	list community_lists 'porn'
	list community_lists 'roblox'
	list community_lists 'russia_inside'
	list community_lists 'telegram'
	list community_lists 'tiktok'
	list community_lists 'twitter'
	list community_lists 'youtube'
	option enabled '1'
EOF
echo -e "${CYAN}Применяем конфигурацию${NC}"
/etc/init.d/zeroblock reload >/dev/null 2>&1
sleep 2
echo -e "${CYAN}Перезапускаем сервис${NC}"
/etc/init.d/zeroblockrestart >/dev/null 2>&1
echo -e "AWG ${GREEN}интегрирован в ${NC}ZeroBlock${GREEN}!${NC}\n"
PAUSE
}



###################################################################################################################################################

menu() {
    clear

echo -e "╔══════════════════════════════╗"
echo -e "║   ${BLUE}Z2R Manager by StressOzz${NC}   ║"
echo -e "╚══════════════════════════════╝\n"


if [ -f /etc/config/zapret2 ]; then
echo -e "${YELLOW}Zapret2: ${GREEN}установлен${NC}"
else
echo -e "${YELLOW}Zapret2: ${RED}не установлен${NC}"
fi

echo
if [ -f /etc/config/zeroblock ]; then
echo -e "${YELLOW}ZeroBlock: ${GREEN}установлен${NC}"
else
echo -e "${YELLOW}ZeroBlock: ${RED}не установлен${NC}"
fi

echo
if command -v amneziawg >/dev/null 2>&1 || eval "$PKG_MANAGER" | grep -q "amneziawg-tools"; then
echo -e "${YELLOW}AWG: ${GREEN}установлен${NC}"
else
echo -e "${YELLOW}AWG: ${RED}не установлен${NC}"
fi

if uci -q get network.AWG >/dev/null; then
    echo -e "${YELLOW}Интерфейс AWG: ${GREEN}установлен${NC}"
else
    echo -e "${YELLOW}Интерфейс AWG: ${RED}не установлен${NC}"
fi

    if is_installed zapret2; then
        Z="Удалить"
    else
        Z="Установить"
    fi

    if is_installed zeroblock; then
        ZB="Удалить"
    else
        ZB="Установить"
    fi

    if is_routerich; then
        R_TEXT="Удалить"
    else
        R_TEXT="Добавить"
    fi

    echo -e "\n${CYAN}1) ${GREEN}${Z}${NC} Zapret2"
    echo -e "${CYAN}2) ${GREEN}${ZB}${NC} ZeroBlock"
	echo -e "${CYAN}3) ${GREEN}Интегрировать ${NC}VPN${GREEN} подписку в ${NC}ZeroBlock${NC}"
    echo -e "${CYAN}4) ${GREEN}Установить ${NC}AWG ${GREEN}и${NC} интерфейс AWG"
    echo -e "${CYAN}5) ${GREEN}Удалить ${NC}AWG ${GREEN}и${NC} интерфейс AWG"
	echo -e "${CYAN}6) ${GREEN}Интегрировать ${NC}AWG${GREEN} в ${NC}ZeroBlock${NC}"	
    echo -e "${CYAN}7) ${GREEN}$R_TEXT пакеты${NC} Routerich"
    
echo -ne "\n${YELLOW}Выберите пункт:${NC} "
    read c

    case "$c" in
        1)
            if is_installed zapret2; then remove_zapret; else install_zapret; fi
        ;;
        2)
            if is_installed zeroblock; then remove_zero; else install_zero; fi
        ;;

		3) 
			PODPISKA
		;;

        4) 
            install_AWG
        ;;
        
        5) 
            uninstall_AWG
        ;;

        6) 
            AWG_INT
        ;;

        7)
            if is_routerich; then routerich_remove; else routerich_add; fi
        ;;      
        *)
            exit 0
        ;;
    esac
}

while true; do
    menu
done
