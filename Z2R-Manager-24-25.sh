#!/bin/sh

### =======================================================================
### АВТООПРЕДЕЛЕНИЕ ТИПА ПАКЕТНОГО МЕНЕДЖЕРА И НАСТРОЙКА РЕПОЗИТОРИЯ
### =======================================================================

GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"; DGRAY="\033[38;5;244m"

# Определяем менеджер
if command -v opkg >/dev/null 2>&1; then
    BASE_URL="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    PKG_EXT="ipk"
    PKG_INSTALL="opkg install"
    PKG_REMOVE="opkg --force-removal-of-dependent-packages --autoremove remove"
    PKG_TYPE="opkg"
    UPDATE="opkg update"
    ARCH_SUFFIX="aarch64_cortex-a53"
    CHECK_INSTALLED() { opkg list-installed 2>/dev/null | grep -q "^$1 -"; }
else
    BASE_URL="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    PKG_EXT="apk"
    PKG_INSTALL="apk add --allow-untrusted"
    PKG_REMOVE="apk del"
    PKG_TYPE="apk"
    ARCH_SUFFIX=""
	UPDATE="apk update"
    CHECK_INSTALLED() { apk list --installed 2>/dev/null | grep -q "^$1"; }
fi

PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }

if ! command -v curl >/dev/null 2>&1; then clear; echo -e "${MAGENTA}Устанавливаем ${NC}curl"
ok=0; echo -e "${CYAN}Устанавливаем ${NC}curl"; for i in 1 2 3; do if $PKG_INSTALL curl >/dev/null 2>&1; then ok=1; break; fi; echo -e "${YELLOW}Устанавливаем ${NC}curl${YELLOW} попытка ${NC}$i${YELLOW} не удалась!${NC}"; done
if [ "$ok" -ne 1 ]; then echo -e "\n${RED}Не удалось установить ${NC}curl${RED} после 5 попыток${NC}"; PAUSE; exit 0; fi; if ! command -v curl >/dev/null 2>&1; then echo -e "\ncurl${RED} не найден после установки${NC}"; PAUSE; exit 0; fi; fi

TMP_DIR="/tmp/routerich"
mkdir -p "$TMP_DIR"
CACHE_FILE="$TMP_DIR/index.html"

# Функция для скачивания (с поддержкой редиректов)
download_file() {
    local url="$1"
    local output="$2"
    curl -L -s --connect-timeout 10 "$url" -o "$output"
}

# Обновление кэша
update_cache() {
    download_file "$BASE_URL" "$CACHE_FILE"
}

log() { echo -e "${YELLOW}[*]${NC} $1"; }

UPDATE_PACK() { log "${CYAN}Обновляем список пакетов${NC}"
for i in 1 2 3; do if $UPDATE >/dev/null 2>&1; then ok=1; break; fi
log "${YELLOW}Обновление пакетов попытка $i не удалась${NC}"; done; }

### =======================================================================
### ФУНКЦИИ ДЛЯ РАБОТЫ С ПАКЕТАМИ
### =======================================================================

# Получение имени удаленного файла пакета (ТОЛЬКО ДЛЯ OPKG)
get_opkg_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    # Ищем файл с правильной архитектурой
    grep -o "${pkg_name}_[0-9][^\"]*_${ARCH_SUFFIX}\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Получение имени luci-файла (ТОЛЬКО ДЛЯ OPKG)
get_opkg_luci_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    # Luci интерфейс всегда с архитектурой _all
    grep -o "luci-app-${pkg_name}_[0-9][^\"]*_all\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Получение имени удаленного файла для APK
get_apk_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    # Ищем основной пакет
    grep -o "${pkg_name}-[0-9][^\"]*\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Получение имени luci-файла для APK
get_apk_luci_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    # Ищем luci пакет для APK
    grep -o "luci-app-${pkg_name}-[0-9][^\"]*\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Извлечение версии из имени файла для OPKG
get_opkg_version() {
    local filename="$1"
    echo "$filename" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+'
}

# Извлечение версии из имени файла для APK
get_apk_version() {
    local filename="$1"
    echo "$filename" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+'
}

# Получение установленной версии
get_local_version() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | grep "^$pkg_name -" | awk '{print $3}'
    else
        apk list --installed 2>/dev/null | grep "^$pkg_name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+' | head -n1
    fi
}

# Проверка установлен ли luci интерфейс
is_luci_installed() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | grep -q "luci-app-$pkg_name"
    else
        apk list --installed 2>/dev/null | grep -q "luci-app-$pkg_name"
    fi
}

# Получение версии установленного luci
get_luci_version() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | grep "luci-app-$pkg_name" | awk '{print $3}'
    else
        apk list --installed 2>/dev/null | grep "luci-app-$pkg_name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+' | head -n1
    fi
}

### =======================================================================
### ОПРЕДЕЛЕНИЕ СОСТОЯНИЯ ПАКЕТА
### =======================================================================

get_package_state() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        local main_file="$(get_opkg_file "$pkg_name")"
        local luci_file="$(get_opkg_luci_file "$pkg_name")"
        
        if [ -n "$main_file" ]; then
            remote_ver="$(get_opkg_version "$main_file")"
        else
            remote_ver=""
        fi
        
        # Для opkg luci версия обычно такая же как у основного пакета
        luci_remote_ver="$remote_ver"
    else
        local main_file="$(get_apk_file "$pkg_name")"
        local luci_file="$(get_apk_luci_file "$pkg_name")"
        
        if [ -n "$main_file" ]; then
            remote_ver="$(get_apk_version "$main_file")"
        else
            remote_ver=""
        fi
        
        if [ -n "$luci_file" ]; then
            luci_remote_ver="$(get_apk_version "$luci_file")"
        else
            luci_remote_ver=""
        fi
    fi
    
    local local_ver="$(get_local_version "$pkg_name")"
    local luci_local_ver="$(get_luci_version "$pkg_name")"
    
    # Сохраняем имена файлов в глобальные переменные для установки
    MAIN_FILE="$main_file"
    LUCI_FILE="$luci_file"
    
    if [ -z "$local_ver" ] && [ -n "$remote_ver" ]; then
        echo "install|$local_ver|$remote_ver|$luci_local_ver|$luci_remote_ver"
    elif [ -n "$local_ver" ] && [ -n "$remote_ver" ] && [ "$local_ver" != "$remote_ver" ]; then
        echo "update|$local_ver|$remote_ver|$luci_local_ver|$luci_remote_ver"
    elif [ -n "$local_ver" ]; then
        echo "remove|$local_ver|$remote_ver|$luci_local_ver|$luci_remote_ver"
    else
        echo "error||||"
    fi
}

### =======================================================================
### УСТАНОВКА И УДАЛЕНИЕ
### =======================================================================

install_package() {

    local pkg_name="$1"
    
    # Очищаем временную директорию перед установкой
    rm -f "$TMP_DIR"/*.${PKG_EXT}

    echo
    
    log "${MAGENTA}=== Установка $pkg_name ===${NC}"

    UPDATE_PACK

    # Получаем состояние (это заполнит MAIN_FILE и LUCI_FILE)
    get_package_state "$pkg_name" > /dev/null
    
    if [ -z "$MAIN_FILE" ]; then
        log "${RED}ОШИБКА: Не найден пакет${NC} $pkg_name"
        return 1
    fi
    
    # Скачиваем основной пакет
    local main_url="${BASE_URL}${MAIN_FILE}"
    log "${CYAN}Скачивание:${NC} $MAIN_FILE"
    download_file "$main_url" "$TMP_DIR/$MAIN_FILE"
    
    if [ ! -f "$TMP_DIR/$MAIN_FILE" ]; then
        log "${RED}ОШИБКА: Не удалось скачать $MAIN_FILE${NC}"
        return 1
    fi
    
    # Скачиваем luci если есть
    if [ -n "$LUCI_FILE" ]; then
        local luci_url="${BASE_URL}${LUCI_FILE}"
        log "${CYAN}Скачивание:${NC} $LUCI_FILE"
        download_file "$luci_url" "$TMP_DIR/$LUCI_FILE"
    fi
    
    # Установка
    log "${CYAN}Установка пакетов...${NC}"
    local packages_to_install=$(ls "$TMP_DIR"/*.$PKG_EXT 2>/dev/null)
    
    
 if [ -n "$packages_to_install" ]; then
        if ! $PKG_INSTALL $packages_to_install; then
            log "${RED}✗ Ошибка установки $pkg_name${NC}"
            log "${RED}Установка остановлена!${NC}"
            rm -f "$TMP_DIR"/*.$PKG_EXT
            return 1
        fi

        if [ "$pkg_name" = "zeroblock" ]; then
            if ! $PKG_INSTALL sing-box; then
                log "${RED}✗ Ошибка установки sing-box${NC}"
                log "${RED}Установка остановлена!${NC}"
                rm -f "$TMP_DIR"/*.$PKG_EXT
                return 1
            fi
        fi

        sleep 2
        log "${GREEN}✓ Установка завершена${NC}"
    fi
	
    
    # Очистка
    rm -f "$TMP_DIR"/*.$PKG_EXT
}

remove_zapret2() {

    echo
    
    log "${MAGENTA}=== Удаление zapret2 ===${NC}"

    # Удаляем основной пакет
    log "${CYAN}Удаление zapret2...${NC}"
    $PKG_REMOVE "zapret2" 2>/dev/null
    
    # Удаляем luci если он установлен
    if is_luci_installed "zapret2"; then
        log "${CYAN}Удаление luci-app-zapret2...${NC}"
        $PKG_REMOVE "luci-app-zapret2" 2>/dev/null
    fi
    rm -f /etc/config/zapret2
    rm -rf /opt/zapret2
    log "${GREEN}✓ Удаление zapret2 завершено${NC}"
}

remove_zeroblock() {

    echo

    log "${MAGENTA}=== Удаление zeroblock ===${NC}"

    # Удаляем основной пакет
    log "${CYAN}Удаление zeroblock...${NC}"
    $PKG_REMOVE "zeroblock" 2>/dev/null
    
    # Удаляем luci если он установлен
    if is_luci_installed "zeroblock"; then
        log "${CYAN}Удаление luci-app-zeroblock...${NC}"
        $PKG_REMOVE "luci-app-zeroblock" 2>/dev/null
    fi
    rm -rf /etc/config/zeroblock*
    rm -rf /etc/zeroblock*
    rm -rf /usr/bin/zeroblock*
    log "${GREEN}✓ Удаление zeroblock завершено${NC}"
}

### =======================================================================
### ФУНКЦИИ ДЛЯ AWG
### =======================================================================

# Определение архитектуры через get_pkgarch (как в оригинальном скрипте)
get_pkgarch() {
    # Пытаемся получить через ubus
    PKGARCH_UBUS=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.arch' 2>/dev/null)
    if [ -n "$PKGARCH_UBUS" ]; then
        echo "$PKGARCH_UBUS"
        return
    fi
    
    # Если ubus не доступен, пробуем opkg
    if command -v opkg >/dev/null 2>&1; then
        opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}'
        return
    fi
    
    # Fallback на /etc/openwrt_release
    if [ -f /etc/openwrt_release ]; then
        PKGARCH_RELEASE=$(grep "^DISTRIB_ARCH='" /etc/openwrt_release | cut -d"'" -f2)
        if [ -n "$PKGARCH_RELEASE" ]; then
            echo "$PKGARCH_RELEASE"
            return
        fi
    fi
    
    # Последний шанс - apk или uname
    if command -v apk >/dev/null 2>&1; then
        apk --print-arch
    else
        uname -m
    fi
}

# Получаем параметры для AWG
PKGARCH=$(get_pkgarch)
TARGET=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
SUBTARGET=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
VERSION=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.version')

# Если ubus не работает, берем из файла
if [ -z "$TARGET" ] && [ -f /etc/openwrt_release ]; then
    TARGET=$(grep DISTRIB_TARGET /etc/openwrt_release | cut -d"'" -f2 | cut -d '/' -f 1)
    SUBTARGET=$(grep DISTRIB_TARGET /etc/openwrt_release | cut -d"'" -f2 | cut -d '/' -f 2)
    VERSION=$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2)
fi

# Формируем постфикс для имени файла
PKGPOSTFIX_BASE="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}"
AWG_BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${VERSION}/"

AWG_PKGS="kmod-amneziawg amneziawg-tools luci-proto-amneziawg luci-i18n-amneziawg-ru"

is_awg_installed() {
    for p in $AWG_PKGS; do
        CHECK_INSTALLED "$p" || return 1
    done
    return 0
}

install_awg() {
    local temp_dir="/tmp/amneziawg"
    mkdir -p "$temp_dir"

    echo

    log "${MAGENTA}=== Установка AmneziaWG ===${NC}"
    log "${CYAN}Архитектура:${NC} $PKGARCH"
    log "${CYAN}Таргет:${NC} $TARGET/$SUBTARGET"
    log "${CYAN}Версия:${NC} $VERSION"

    UPDATE_PACK

    for pkg in $AWG_PKGS; do
        if CHECK_INSTALLED "$pkg"; then
            log "${GREEN}✓ $pkg уже установлен${NC}"
            continue
        fi
    
        local filename="${pkg}${PKGPOSTFIX_BASE}.${PKG_EXT}"
        local url="${AWG_BASE_URL}${filename}"
        
        log "${CYAN}Скачивание:${NC} $filename"
        if curl -fsL -o "$temp_dir/$filename" "$url"; then
            log "${CYAN}Установка:${NC} $pkg"
            if $PKG_INSTALL "$temp_dir/$filename" 2>/dev/null; then
                log "${GREEN}✓ $pkg установлен${NC}"
            else
                log "${RED}✗ Ошибка установки $pkg${NC}"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            log "${RED}✗ Не удалось скачать $pkg${NC}"
            rm -rf "$temp_dir"
            return 1
        fi
    done
    
    rm -rf "$temp_dir"
    log "${CYAN}Перезапускаем сеть! ${YELLOW}Подождите...${NC}"
    /etc/init.d/network restart 2>/dev/null
    log "${GREEN}✓ Установка AWG завершена${NC}"
}

remove_awg() {

    echo

    log "${MAGENTA}=== Удаление AmneziaWG ===${NC}"
    
    log "${CYAN}Удаление:${NC} luci-i18n-amneziawg-ru"
    $PKG_REMOVE luci-i18n-amneziawg-ru 2>/dev/null
    
    log "${CYAN}Удаление:${NC} luci-proto-amneziawg"
    $PKG_REMOVE luci-proto-amneziawg 2>/dev/null
    
    log "${CYAN}Удаление:${NC} amneziawg-tools"
    $PKG_REMOVE amneziawg-tools 2>/dev/null
    
    log "${CYAN}Удаление:${NC} kmod-amneziawg"
    $PKG_REMOVE kmod-amneziawg 2>/dev/null
    
    log "${CYAN}Перезапускаем сеть! ${YELLOW}Подождите...${NC}"
    /etc/init.d/network restart 2>/dev/null
    log "${GREEN}✓ Удаление AWG завершено${NC}"
}

run_awg_action() {
    if is_awg_installed; then
        remove_awg
    else
        install_awg
    fi
}

### =======================================================================
### ОТОБРАЖЕНИЕ МЕНЮ
### =======================================================================

get_menu_label() {
    local pkg_name="$1"
    local state_data="$(get_package_state "$pkg_name")"
    
    local action="$(echo "$state_data" | cut -d'|' -f1)"
    local local_ver="$(echo "$state_data" | cut -d'|' -f2)"
    local remote_ver="$(echo "$state_data" | cut -d'|' -f3)"
    local luci_local_ver="$(echo "$state_data" | cut -d'|' -f4)"
    local luci_remote_ver="$(echo "$state_data" | cut -d'|' -f5)"
    
    case "$action" in
        install) 
            echo -e "${GREEN}Установить${NC} $pkg_name"
            ;;
        update)
            echo -e "${GREEN}Обновить${NC} $pkg_name"
            ;;
        remove)
            echo -e "${GREEN}Удалить${NC} $pkg_name"
            ;;
        *)       echo "$pkg_name → Недоступно" ;;
    esac
}

get_awg_menu_label() {
    if is_awg_installed; then
        echo -e "${GREEN}Удалить${NC} AmneziaWG"
    else
        echo -e "${GREEN}Установить${NC} AmneziaWG"
    fi
}

run_action() {
    local pkg_name="$1"
    local action="$(get_package_state "$pkg_name" | cut -d'|' -f1)"
    
    if [ "$pkg_name" = "zapret2" ] && [ "$action" = "remove" ]; then
        remove_zapret2
    elif [ "$pkg_name" = "zeroblock" ] && [ "$action" = "remove" ]; then
        remove_zeroblock
    elif [ "$action" = "install" ] || [ "$action" = "update" ]; then
        install_package "$pkg_name"
    else
        log "${RED}Ошибка: пакет $pkg_name недоступен${NC}"
    fi
}
###################################################################################################################################################

PODPISKA() {
    echo -ne "\n${YELLOW}Введите ссылку на подписку (${NC}https://...${YELLOW}): ${NC}"
    read -r SUB_URL
    [ -z "$SUB_URL" ] && echo -e "\n${RED}Ошибка! Ссылка пустая!${NC}" && PAUSE && return
    
cat > /etc/config/zeroblock << EOF
config settings 'settings'
	option log_level 'error'
	option show_trace_logs '0'
	option health_interval '600'
	option health_dns_check '1'
	option health_ping_ip '1.1.1.1 8.8.8.8'
	option health_opera_host 'ya.ru google.com'
	option update_interval '1d'
	option timeout_dnsmasq_restart '150'
	option api 'v1'
	option health_enabled '1'
	option update_time '09:00'
	option enable_bad_interface_monitoring '0'
	option download_lists_via_proxy '0'
	option auto_fallback_two_stage '1'
	option timeout_singbox_check '60'
	option timeout_singbox_kill '15'
	option health_dns_server_check '0'
	option health_dns_test_host 'dns.google'
	option dns_query_timeout '15'
	option singbox_double_check '0'
	option singbox_double_check_delay '15'
	option lists_tls_insecure '0'
	option opera_proxy_enabled '1'
	option timeouts_forced_to_max_v4 '1'
	option text_lists_migrated '1'
	option sub_max_proxies_capped '1'
	option schema_version '44'
	option subscription_update_interval '1h'

config section 'StressKVN'
	option connection_type 'proxy'
	option dscp_enabled '0'
	option proxy_config_type 'subscription'
	list subscription_url '$SUB_URL'
	option urltest_check_interval '3m'
	option urltest_tolerance '150'
	option disable_fakeip '0'
	option force_cidr_community '0'
	option community_lists_invert '0'
	option enabled '1'
	list subscription_ignore_tags '⬇️'
	list subscription_ignore_tags 'LTE'
	list subscription_ignore_tags 'Auto'
	list subscription_ignore_tags 'Авто'
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
	list community_lists 'telegram'
	list community_lists 'tiktok'
	list community_lists 'twitter'
	list community_lists 'youtube'

config auto_config 'auto_config'

config dashboard 'dashboard'

config diagnostic 'diagnostic'

config engine 'engine'
	option dns_type 'udp'
	option dns_server '9.9.9.9'
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
	option log_level 'error'
	option dont_touch_dhcp '0'
	option dns_hijack '0'
	option enable_output_network_interface '0'
	option proxy_router_traffic '0'
	option ipv6_enabled '0'
	option discord_voice '1'
	option meta_force_cidr '1'
	option exclude_bittorrent '1'
	option exclude_ntp '1'
	option singbox_logging '0'
	option xray_logging '0'
	option trusttunnel_logging '0'
	option fakeip_query_type_filter '1'
	option xray_path '/usr/bin/xray'
	option trusttunnel_path '/usr/bin/trusttunnel_client'
	option custom_config_dir '/etc/zeroblock/sing-box.d'
	option dpi_check_timeout '15'
	option adblock_convert_timeout '300'
	option fallback_probe_timeout_default '3'
	option singbox_startup_timeout '150000'
	option xray_startup_timeout '60000'
	option trusttunnel_startup_timeout '60000'
	option version_check_timeout '31'
	option bootstrap_port_free_timeout '5250'
	option singbox_sighup_wait_timeout '15500'
	option subscription_timeout '60000'
	option subscription_max_proxies '100'
	option subscription_user_agent 'clash-verge/v2.0.0'
	option subscription_tls_insecure '0'
	list source_network_interfaces 'br-lan'
	option testing_url 'http://www.gstatic.com/generate_204'
	option naive_logging '0'
	option global_exclude_mode 'route'
EOF

echo -e "${CYAN}Применяем конфигурацию${NC}"
/etc/init.d/zeroblock reload >/dev/null 2>&1
sleep 2
echo -e "${CYAN}Перезапускаем сервис${NC}"
/etc/init.d/zeroblock restart >/dev/null 2>&1
echo -e "VPN ${GREEN}подписка интегрирована в ${NC}ZeroBlock${GREEN}!${NC}"
PAUSE
}
### =======================================================================
### МЕНЮ
### =======================================================================

menu() {
    while true; do
        clear
        update_cache >/dev/null 2>&1
echo -e "╔════════════════════════════╗"
echo -e "║  ${BLUE}Z2R Manager by StressOzz${NC}  ║"
echo -e "╚════════════════════════════╝\n"

        echo -e "${CYAN}1)${NC} $(get_menu_label zapret2)"
        echo -e "${CYAN}2)${NC} $(get_menu_label zeroblock)"
        echo -e "${CYAN}3)${NC} $(get_awg_menu_label)"
        echo -e "${CYAN}4) ${GREEN}Интегрировать ${NC}VPN${GREEN} подписку в ${NC}ZeroBlock"
        echo -e "${CYAN}5) ${GREEN}Установить зависимости для ${NC}ZeroBlock"
        echo -e "${CYAN}Enter) ${GREEN}Выход${NC}\n"
        
        echo -en "${YELLOW}Выберите пункт:${NC} "
        read -r user_choice
        
        case "$user_choice" in
            1) run_action zapret2
wget -qO /opt/zapret2/ipset/zapret_hosts_user_exclude.txt https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt
sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2 >/dev/null 2>&1
/etc/init.d/zapret2 restart >/dev/null 2>&1 
PAUSE ;;       
            2) run_action zeroblock; PAUSE ;;
            3) run_awg_action; PAUSE ;;
            4) PODPISKA ;;
			5) 
echo -e "\n${YELLOW}ВНИМАНИЕ !!!${NC}"
echo -e "${CYAN}Будут установлены библиотеки из ${NC}OpenWrt Snapshot${CYAN}:${NC}"
echo
echo -e "  ${YELLOW}•${NC} libubox20260721"
echo -e "  ${YELLOW}•${NC} libblobmsg-json20260721"
echo -e "  ${YELLOW}•${NC} libubus20260628"
echo -e "  ${YELLOW}•${NC} libyaml-0.2.5"
echo
echo -e "${CYAN}Эти пакеты необходимы для работы ${NC}ZeroBlock"
echo
echo -ne "${YELLOW}Продолжить установку? (${NC}Y/n${YELLOW}): ${NC}"
read -r CONFIRM

case "$CONFIRM" in
    n|N|т|Т)
        echo -e "\n${RED}Установка отменена!${NC}"
		PAUSE
		continue
        ;;
esac
			sh <(wget -q -O - https://raw.githubusercontent.com/StressOzz/Z2R-Manager/main/ZeroBlock_zavisimosti.sh); PAUSE;;
            *) exit 0 ;;
        esac
    done
}

# Запуск
menu
