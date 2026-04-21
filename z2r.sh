#!/bin/sh

clear

echo "███████╗██████╗ ██████╗ "
echo "╚══███╔╝╚════██╗██╔══██╗"
echo "  ███╔╝  █████╔╝██████╔╝"
echo " ███╔╝  ██╔═══╝ ██╔══██╗"
echo "███████╗███████╗██║  ██║"
echo "╚══════╝╚══════╝╚═╝  ╚═╝"

BASE_HTML="https://github.com/routerich/packages.routerich/tree/24.10.6/routerich"
RAW_BASE="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.6/routerich"
TMP="/tmp/z2r"; GREEN="\033[1;32m"; RED="\033[1;31m"; NC="\033[0m"

[ "$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)" = "aarch64_cortex-a53" ] || { echo -e "\n${RED}Неподдерживаемая архитектура!${NC}\n${GREEN}Только для ${NC}aarch64_cortex-a53\n"; exit 1; }

if opkg list-installed | grep -q "^zapret2 "; then
    echo -e "${RED}Удаляем...${NC}"
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zapret2 zapret2 >/dev/null 2>&1
    rm -f /etc/config/zapret2; rm -rf /opt/zapret2; rm -rf "$TMP"
    echo -e "${GREEN}Удалено!${NC}\n"
    exit 0
fi

find_latest() { wget -qO- "$BASE_HTML" | grep -oE "$1[^\"']+\.ipk" | sort -u | head -n1; }

install_pkg() {
    PKG="$(find_latest "$1")" || { echo -e "\n${RED}Файл не найден!${NC}\n"; exit 1; }
    wget "$RAW_BASE/$PKG" -O "$TMP/$PKG" >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при скачивании!${NC}\n"; exit 1; }
    opkg install "$TMP/$PKG" >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при установке!${NC}\n"; exit 1; }
}

echo -e "${GREEN}Обновляем список пакетов...${NC}"; opkg update >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}\n"; exit 1; }

mkdir -p "$TMP"
echo -e "${GREEN}Скачиваем и устанавливаем...${NC}"; install_pkg "zapret2_"
echo -e "${GREEN}Ещё чуть-чуть...${NC}"; install_pkg "luci-app-zapret2_"
rm -rf "$TMP"

echo -e "${GREEN}Настраиваем...${NC}"
wget -qO /opt/zapret2/ipset/zapret_hosts_user_exclude.txt https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt
sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2
/etc/init.d/zapret2 restart >/dev/null 2>&1

echo -e "${GREEN}Готово!${NC}\n"
