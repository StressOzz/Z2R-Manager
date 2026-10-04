#!/bin/sh

# ==========================================
# ZeroBlock — зависимости
# Имена пакетов определяются автоматически
# по листингу snapshot-репозитория OpenWrt
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

clear
echo -e "          ${GREEN}ZeroBlock${NC}"
echo -e "     ${YELLOW}Dependencies Installer${NC}\n"

BASE_URL="https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53"
TMP_DIR="/tmp/zb-libs"

# Формат: регулярка_начала_имени|репозиторий|название_для_вывода
PACKAGES="
libubox2[0-9]*-|base|libubox
libblobmsg-json2[0-9]*-|base|libblobmsg-json
libubus2[0-9]*-|base|libubus
libyaml-[0-9]|packages|libyaml
"

fail() {
    echo -e "${RED}$1${NC}"
    rm -rf "$TMP_DIR"
    exit 1
}

# Проверка apk
command -v apk >/dev/null 2>&1 || fail "Ошибка: apk не найден"

# Проверка архитектуры
ARCH="$(awk -F= '/^DISTRIB_ARCH=/{gsub(/'\''/, "", $2); print $2}' /etc/openwrt_release)"
[ "$ARCH" = "aarch64_cortex-a53" ] || fail "Ошибка: неподдерживаемая архитектура: $ARCH"

echo -e "${CYAN}Архитектура:${NC} ${GREEN}$ARCH${NC}"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" || fail "Ошибка создания $TMP_DIR"

# Кэш листингов репозиториев
get_listing() {
    LIST="$TMP_DIR/.list_$1"
    if [ ! -s "$LIST" ]; then
        wget -q "$BASE_URL/$1/" -O "$LIST" || return 1
    fi
    cat "$LIST"
}

FILES=""

for ITEM in $PACKAGES; do
    PATTERN="$(echo "$ITEM" | cut -d'|' -f1)"
    REPO="$(echo "$ITEM" | cut -d'|' -f2)"
    NAME="$(echo "$ITEM" | cut -d'|' -f3)"

    echo -e "${CYAN}Ищем актуальную версию:${NC} ${YELLOW}$NAME${NC}"

    LISTING="$(get_listing "$REPO")" || fail "Ошибка получения списка пакетов ($REPO)"

    FILE="$(echo "$LISTING" \
        | grep -o "href=\"${PATTERN}[^\"]*\.apk\"" \
        | sed 's/^href="//; s/"$//' \
        | grep -v -- '-lua-' \
        | sort | tail -n1)"

    [ -n "$FILE" ] || fail "Пакет не найден в репозитории: $NAME"

    # В листинге "~" может быть закодирована как %7E
    FILE="$(echo "$FILE" | sed 's/%7E/~/g; s/%7e/~/g')"

    echo -e "${CYAN}Скачиваем:${NC} ${YELLOW}$FILE${NC}"

    wget -q "$BASE_URL/$REPO/$FILE" -O "$TMP_DIR/$FILE" || fail "Ошибка загрузки: $FILE"
    [ -s "$TMP_DIR/$FILE" ] || fail "Ошибка: файл пустой: $FILE"

    echo -e "${GREEN}[ OK ]${NC} $FILE"
    FILES="$FILES $TMP_DIR/$FILE"
done

echo
echo -e "${MAGENTA}Устанавливаем зависимости...${NC}"

# shellcheck disable=SC2086
apk add --allow-untrusted $FILES || fail "Ошибка установки зависимостей"

echo
echo -e "${MAGENTA}Проверяем установленные пакеты...${NC}"

INSTALLED="$(apk list --installed 2>/dev/null)"

for CHECK in 'libubox2[0-9]*-' 'libblobmsg-json2[0-9]*-' 'libubus2[0-9]*-' 'libyaml-[0-9]'; do
    PKG="$(echo "$INSTALLED" | grep -o "^${CHECK}[^ ]*" | head -n1)"
    if [ -n "$PKG" ]; then
        echo -e "${GREEN}[ OK ]${NC} $PKG"
    else
        fail "[FAIL] не установлен: $CHECK"
    fi
done

rm -rf "$TMP_DIR"

echo
echo -e "${GREEN}Все зависимости успешно установлены!${NC}"
