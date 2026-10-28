#!/usr/bin/env bash
set -e

# Перехід у папку скрипта
cd "$(dirname "$0")"

# Кольори для красивого виводу
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}"
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║          АВТОМАТИЧНИЙ ЗАПУСК TEAMSPEAK 6 + PORTWARP               ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. Завантаження налаштувань з .env
if [ -f ".env" ]; then
    echo -e "${BLUE}ℹ Завантаження конфігурації з .env...${NC}"
    while IFS='=' read -r key val || [ -n "$key" ]; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | tr -d '[:space:]')
        val=$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'"'"']//' -e 's/["'"'"']$//')
        if [ -n "$key" ]; then
            export "$key=$val"
        fi
    done < .env
else
    if [ -f ".env.example" ]; then
        echo -e "${YELLOW}Файл .env не знайдено, копіюємо з .env.example...${NC}"
        cp .env.example .env
    fi
fi

# 2. Перевірка Docker
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Помилка: Docker не встановлено на цій системі!${NC}"
    exit 1
fi

# 3. Запуск контейнерів
echo -e "${BLUE}🚀 Запуск контейнерів TeamSpeak 6 та Portwarp...${NC}"
docker compose up -d

echo -e "${BLUE}⏳ Очікування готовності сервісів...${NC}"
sleep 3

# 4. Перевірка авторизації Portwarp
echo -e "${BLUE}🔑 Перевірка авторизації Portwarp...${NC}"
PWRP_DOCTOR=$(docker compose exec -T pwrp pwrp doctor 2>&1 || true)

if echo "$PWRP_DOCTOR" | grep -q "not logged in"; then
    echo -e "${YELLOW}Portwarp не авторизований.${NC}"
    
    if [ -n "$PORTWARP_EMAIL" ] && [ -n "$PORTWARP_PASSWORD" ]; then
        echo -e "${CYAN}Виконується автоматичний вхід через дані з .env (${PORTWARP_EMAIL})...${NC}"
        if printf "%s\n%s\n" "$PORTWARP_EMAIL" "$PORTWARP_PASSWORD" | docker compose exec -T pwrp pwrp login --legacy; then
            echo -e "${GREEN}✓ Авторизація через .env успішна!${NC}"
        else
            echo -e "${RED}Не вдалося увійти з даними з .env. Запуск інтерактивного входу через браузер...${NC}"
            docker compose exec pwrp pwrp login
        fi
    else
        echo -e "${CYAN}>>> Відкрийте посилання у браузері та введіть код авторизації: <<<${NC}"
        docker compose exec pwrp pwrp login
    fi
else
    echo -e "${GREEN}✓ Portwarp уже авторизований!${NC}"
fi

# 5. Налаштування тунелю
echo -e "${BLUE}🔗 Налаштування та запуск тунелю Portwarp...${NC}"
TUNNEL_NAME="${PORTWARP_TUNNEL_NAME:-TeamSpeak 3}"

# Встановлення цільового контейнера для тунелю
docker compose exec -T pwrp pwrp target set "${TUNNEL_NAME}" teamspeak >/dev/null 2>&1 || \
docker compose exec -T pwrp pwrp target set 1 teamspeak >/dev/null 2>&1 || true

# Підключення тунелю
CONNECT_OUT=$(docker compose exec -T pwrp pwrp connect "${TUNNEL_NAME}" --detach --save 2>&1 || \
              docker compose exec -T pwrp pwrp connect --all --detach --save 2>&1 || true)

AUTO_ADDR=$(echo "$CONNECT_OUT" | grep -E -o '[a-zA-Z0-9.-]+\.tryportwarp\.cc:[0-9]+' | head -n 1 || true)

# 6. Очікування отримання токена TeamSpeak
echo -e "${BLUE}⏳ Перевірка ключа привілеїв TeamSpeak 6...${NC}"
ADMIN_TOKEN=""
QUERY_PASS=""
for i in {1..15}; do
    ADMIN_TOKEN=$(docker logs ts6-server 2>&1 | grep -o 'token=[A-Za-z0-9+/=]*' | head -n 1 | cut -d'=' -f2 || true)
    if [ -n "$ADMIN_TOKEN" ]; then
        break
    fi
    sleep 1
done

QUERY_PASS=$(docker logs ts6-server 2>&1 | grep -o 'password= "[^"]*"' | head -n 1 | cut -d'"' -f2 || true)

# 7. Визначення публічної адреси
if [ -n "$AUTO_ADDR" ]; then
    PUBLIC_ADDR="$AUTO_ADDR"
elif [ -n "$PORTWARP_PUBLIC_ADDRESS" ]; then
    PUBLIC_ADDR="$PORTWARP_PUBLIC_ADDRESS"
else
    PUBLIC_ADDR="i6zuaqdg.free.tryportwarp.cc:10153"
fi

# 8. Підсумковий звіт
echo ""
echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}             🎉 СЕРВЕР TEAMSPEAK 6 ГОТОВИЙ ДО РОБОТИ!               ${NC}"
echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  🌐 ${BOLD}Адреса для підключення з Інтернету:${NC}"
echo -e "     ${CYAN}${BOLD}${PUBLIC_ADDR}${NC}"
echo ""
echo -e "  🏠 ${BOLD}Локальна адреса (з цього ПК):${NC}"
echo -e "     ${CYAN}localhost:9987${NC}"
echo ""
if [ -n "$ADMIN_TOKEN" ]; then
echo -e "  🔑 ${BOLD}Ключ повного адміністратора (ServerAdmin Token):${NC}"
echo -e "     ${YELLOW}${BOLD}${ADMIN_TOKEN}${NC}"
echo ""
fi
if [ -n "$QUERY_PASS" ]; then
echo -e "  ⚙️  ${BOLD}ServerQuery Admin логін / пароль:${NC}"
echo -e "     login: ${CYAN}serveradmin${NC} | pass: ${CYAN}${QUERY_PASS}${NC}"
echo ""
fi
echo -e "  📋 ${BOLD}Як підключитися:${NC}"
echo -e "     1. Відкрийте клієнт TeamSpeak 6."
echo -e "     2. Вставте адресу: ${CYAN}${PUBLIC_ADDR}${NC}"
echo -e "     3. При запиті прав вставте токен адміністратора."
echo ""
echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
