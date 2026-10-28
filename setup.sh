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

# Гарантоване утримання вікна відкритим при будь-якому виході (успіх або помилка)
pause_on_exit() {
    local exit_code=$?
    echo ""
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}${BOLD}❌ Скрипт завершився з помилкою (код помилки: ${exit_code}).${NC}"
        echo -e "${RED}Перегляньте повідомлення вище, щоб зрозуміти причину.${NC}"
    else
        echo -e "${GREEN}${BOLD}✓ Роботу скрипта успішно виконано!${NC}"
    fi
    echo ""
    echo -e "${YELLOW}${BOLD}Натисніть Enter, щоб закрити це вікно...${NC}"
    if [ -t 0 ]; then
        read -r _
    elif [ -e /dev/tty ]; then
        read -r _ </dev/tty || true
    fi
}
trap pause_on_exit EXIT

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

CURRENT_AUTH_EMAIL=$(docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>/dev/null | grep '"email"' | cut -d'"' -f4 || true)
CURRENT_AUTH_USER=$(docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>/dev/null | grep '"username"' | cut -d'"' -f4 || true)

# Якщо в .env вказана пошта, і вона відрізняється від поточної збереженої авторизації - перелогінюємось
if [ -n "$PORTWARP_EMAIL" ] && [ -n "$CURRENT_AUTH_EMAIL" ] && [ "$PORTWARP_EMAIL" != "$CURRENT_AUTH_EMAIL" ]; then
    echo -e "${YELLOW}ℹ Виявлено нову пошту в .env (${PORTWARP_EMAIL}), попередня була (${CURRENT_AUTH_EMAIL}). Перелогінюємось...${NC}"
    docker compose exec -T pwrp pwrp logout >/dev/null 2>&1 || true
    CURRENT_AUTH_EMAIL=""
    CURRENT_AUTH_USER=""
fi

PWRP_DOCTOR=$(docker compose exec -T pwrp pwrp doctor 2>&1 || true)

if echo "$PWRP_DOCTOR" | grep -q "not logged in" || [ -z "$CURRENT_AUTH_EMAIL" ]; then
    echo -e "${YELLOW}Portwarp ще не авторизований.${NC}"
    
    # Спроба увійти з .env якщо дані є
    LOGGED_IN=false
    if [ -n "$PORTWARP_EMAIL" ] && [ -n "$PORTWARP_PASSWORD" ]; then
        echo -e "${CYAN}Виконується автоматичний вхід через дані з .env (${PORTWARP_EMAIL})...${NC}"
        if printf "%s\n%s\n" "$PORTWARP_EMAIL" "$PORTWARP_PASSWORD" | docker compose exec -T pwrp pwrp login --legacy >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Авторизація через .env успішна!${NC}"
            LOGGED_IN=true
        else
            echo -e "${RED}Не вдалося увійти з даними з .env.${NC}"
        fi
    fi

    # Захист від дурня: якщо даних у .env немає або вони не підійшли — інтерактивний вибір
    if [ "$LOGGED_IN" = false ]; then
        echo ""
        echo -e "${CYAN}${BOLD}Даних авторизації у .env немає або вони невірні. Оберіть спосіб входу:${NC}"
        echo "  [1] Через браузер в 1 клік (Рекомендовано: посилання + код)"
        echo "  [2] Ввести Email та Пароль вручну прямо зараз"
        echo -n "Ваш вибір [1/2] (за замовчуванням 1): "
        read -r LOGIN_CHOICE </dev/tty || LOGIN_CHOICE="1"
        LOGIN_CHOICE=${LOGIN_CHOICE:-1}

        if [ "$LOGIN_CHOICE" = "2" ]; then
            echo -n "Введіть Email від portwarp.com: "
            read -r INPUT_EMAIL </dev/tty || true
            echo -n "Введіть Пароль від portwarp.com: "
            read -s -r INPUT_PASS </dev/tty || true
            echo ""
            
            if [ -n "$INPUT_EMAIL" ] && [ -n "$INPUT_PASS" ]; then
                echo -e "${BLUE}Авторизація...${NC}"
                if printf "%s\n%s\n" "$INPUT_EMAIL" "$INPUT_PASS" | docker compose exec -T pwrp pwrp login --legacy; then
                    echo -e "${GREEN}✓ Успішний вхід!${NC}"
                    echo -n "Зберегти ці дані у файл .env для наступних автозапусків? [Y/n]: "
                    read -r SAVE_ENV </dev/tty || SAVE_ENV="y"
                    SAVE_ENV=${SAVE_ENV:-y}
                    if [[ "$SAVE_ENV" =~ ^[Yy]$ ]]; then
                        sed -i -E "s|^PORTWARP_EMAIL=.*|PORTWARP_EMAIL=\"$INPUT_EMAIL\"|" .env 2>/dev/null || echo "PORTWARP_EMAIL=\"$INPUT_EMAIL\"" >> .env
                        sed -i -E "s|^PORTWARP_PASSWORD=.*|PORTWARP_PASSWORD=\"$INPUT_PASS\"|" .env 2>/dev/null || echo "PORTWARP_PASSWORD=\"$INPUT_PASS\"" >> .env
                        echo -e "${GREEN}✓ Облікові дані збережено в .env!${NC}"
                    fi
                else
                    echo -e "${RED}Помилка авторизації за паролем. Перехід до входу через браузер...${NC}"
                    docker compose exec pwrp pwrp login
                fi
            else
                docker compose exec pwrp pwrp login
            fi
        else
            echo -e "${CYAN}>>> Відкрийте посилання у браузері та введіть код авторизації: <<<${NC}"
            docker compose exec pwrp pwrp login
        fi
    fi
fi

# Відображення авторизованого акаунта
AUTH_USER=$(docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>/dev/null | grep '"username"' | cut -d'"' -f4 || true)
AUTH_EMAIL=$(docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>/dev/null | grep '"email"' | cut -d'"' -f4 || true)

if [ -n "$AUTH_EMAIL" ]; then
    echo -e "${GREEN}✓ Portwarp підключено до акаунта: ${BOLD}${CYAN}${AUTH_EMAIL}${NC} (нікнейм: ${BOLD}${AUTH_USER:-N/A}${NC})"
elif [ -n "$AUTH_USER" ]; then
    echo -e "${GREEN}✓ Portwarp підключено: ${BOLD}${CYAN}${AUTH_USER}${NC}"
else
    echo -e "${GREEN}✓ Portwarp авторизований!${NC}"
fi

# 5. Налаштування тунелю
echo -e "${BLUE}🔗 Налаштування та запуск тунелю Portwarp...${NC}"

# Захист від дурня: якщо тунелів в акаунті немає — пропонуємо перелогінитися або створити
while true; do
    TUNNELS_LIST=$(docker compose exec -T pwrp pwrp tunnels 2>&1 || true)
    if echo "$TUNNELS_LIST" | grep -q "No tunnels found"; then
        echo ""
        echo -e "${YELLOW}${BOLD}⚠️ Увага: В акаунті [${AUTH_USER} (${AUTH_EMAIL})] ще немає жодного тунелю!${NC}"
        echo -e "${CYAN}Якщо ваш тунель створено під іншим акаунтом у браузері, потрібно перелогінитися.${NC}"
        echo ""
        echo "  [1] Перелогінитися під акаунт, відкритий у браузері (Рекомендовано)"
        echo "  [2] Створити тунель на https://portwarp.com/dashboard та оновити (Retry)"
        echo -n "Ваш вибір [1/2] (за замовчуванням 1): "
        read -r RELOGIN_CHOICE </dev/tty || RELOGIN_CHOICE="1"
        RELOGIN_CHOICE=${RELOGIN_CHOICE:-1}

        if [ "$RELOGIN_CHOICE" = "1" ]; then
            echo -e "${BLUE}Вихід із поточного акаунта...${NC}"
            docker compose exec -T pwrp pwrp logout >/dev/null 2>&1 || true
            echo -e "${CYAN}>>> Запуск авторизації. Відкрийте посилання та підтвердіть під потрібним акаунтом: <<<${NC}"
            docker compose exec pwrp pwrp login
            
            AUTH_USER=$(docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>/dev/null | grep '"username"' | cut -d'"' -f4 || true)
            AUTH_EMAIL=$(docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>/dev/null | grep '"email"' | cut -d'"' -f4 || true)
            echo -e "${GREEN}✓ Новий авторизований акаунт: ${BOLD}${CYAN}${AUTH_USER}${NC} (${AUTH_EMAIL})"
        else
            echo -e "${YELLOW}Після створення тунелю на сайті натисніть Enter, щоб продовжити...${NC}"
            read -r _ </dev/tty || true
        fi
    else
        break
    fi
done

TUNNEL_NAME="${PORTWARP_TUNNEL_NAME:-TeamSpeak 3}"

# Встановлення цільового контейнера для тунелю
docker compose exec -T pwrp pwrp target set "${TUNNEL_NAME}" teamspeak >/dev/null 2>&1 || \
docker compose exec -T pwrp pwrp target set 1 teamspeak >/dev/null 2>&1 || true

# Підключення тунелю
CONNECT_OUT=$(docker compose exec -T pwrp pwrp connect "${TUNNEL_NAME}" --detach --save --local-host teamspeak 2>&1 || \
              docker compose exec -T pwrp pwrp connect 1 --detach --save --local-host teamspeak 2>&1 || \
              docker compose exec -T pwrp pwrp connect --all --detach --save --local-host teamspeak 2>&1 || true)

# Вмикаємо автоматичний запуск тунелю при старті контейнера (після ребуту системи)
docker compose exec -T pwrp pwrp config set boot-all on >/dev/null 2>&1 || true

AUTO_ADDR=$(echo "$CONNECT_OUT" | grep -E -o '[a-zA-Z0-9.-]+\.tryportwarp\.cc:[0-9]+' | head -n 1 || true)
if [ -z "$AUTO_ADDR" ]; then
    AUTO_ADDR=$(docker compose exec -T pwrp pwrp tunnels 2>&1 | grep -E -o '[a-zA-Z0-9.-]+\.tryportwarp\.cc:[0-9]+' | head -n 1 || true)
fi
if [ -z "$AUTO_ADDR" ]; then
    AUTO_ADDR=$(docker compose exec -T pwrp pwrp ps --once 2>&1 | grep -E -o '[a-zA-Z0-9.-]+\.tryportwarp\.cc:[0-9]+' | head -n 1 || true)
fi

# 6. Очікування отримання токена TeamSpeak
echo -e "${BLUE}⏳ Перевірка ключа привілеїв TeamSpeak 6...${NC}"
ADMIN_TOKEN=""
QUERY_PASS=""

# Спроба отримати токен з логів
for i in {1..10}; do
    ADMIN_TOKEN=$(docker logs ts6-server 2>&1 | grep -o 'token=[A-Za-z0-9+/=]*' | head -n 1 | cut -d'=' -f2 || true)
    if [ -n "$ADMIN_TOKEN" ]; then
        break
    fi
    sleep 1
done

# Якщо в логах немає (наприклад, сервер уже запускався раніше) — читаємо з бази або файлу
if [ -z "$ADMIN_TOKEN" ]; then
    if [ -f "admin-credentials.txt" ]; then
        ADMIN_TOKEN=$(grep "ServerAdmin Token:" admin-credentials.txt 2>/dev/null | awk '{print $3}' || true)
    fi
    if [ -z "$ADMIN_TOKEN" ]; then
        ADMIN_TOKEN=$(docker exec ts6-server cat /var/tsserver/tsserver.sqlitedb 2>/dev/null | strings | grep -B 1 "default serveradmin privilege key" | head -n 1 | tr -d '[:space:]' || true)
    fi
fi

QUERY_PASS=$(docker logs ts6-server 2>&1 | grep -o 'password= "[^"]*"' | head -n 1 | cut -d'"' -f2 || true)
if [ -z "$QUERY_PASS" ] && [ -f "admin-credentials.txt" ]; then
    QUERY_PASS=$(grep "ServerQuery Admin:" admin-credentials.txt 2>/dev/null | sed -nE 's/.*pass: ([^ ]+).*/\1/p' || true)
fi

# 7. Визначення публічної адреси
if [ -n "$AUTO_ADDR" ]; then
    PUBLIC_ADDR="$AUTO_ADDR"
elif [ -n "$PORTWARP_PUBLIC_ADDRESS" ]; then
    PUBLIC_ADDR="$PORTWARP_PUBLIC_ADDRESS"
else
    PUBLIC_ADDR="i6zuaqdg.free.tryportwarp.cc:10153"
fi

# Збереження у постійний файл admin-credentials.txt
cat <<EOF > admin-credentials.txt
=====================================================================
                   TEAMSPEAK 6 SERVER CREDENTIALS
=====================================================================
Portwarp акаунт:       ${AUTH_EMAIL:-N/A} (${AUTH_USER:-N/A})
Адреса для підключення: ${PUBLIC_ADDR}
Локальна адреса:       localhost:9987
ServerAdmin Token:     ${ADMIN_TOKEN}
ServerQuery Admin:     login: serveradmin | pass: ${QUERY_PASS:-4g5miKzv}
=====================================================================
EOF

# 8. Підсумковий звіт
echo ""
echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}             🎉 СЕРВЕР TEAMSPEAK 6 ГОТОВИЙ ДО РОБОТИ!               ${NC}"
echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
echo ""
if [ -n "$AUTH_EMAIL" ]; then
echo -e "  📧 ${BOLD}Portwarp акаунт (email):${NC}"
echo -e "     ${CYAN}${BOLD}${AUTH_EMAIL}${NC} (${AUTH_USER:-N/A})"
echo ""
fi
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
echo -e "  💾 ${BOLD}Дані також збережено у файл:${NC} ${CYAN}admin-credentials.txt${NC}"
echo ""
echo -e "  📋 ${BOLD}Як підключитися:${NC}"
echo -e "     1. Відкрийте клієнт TeamSpeak 6."
echo -e "     2. Вставте адресу: ${CYAN}${PUBLIC_ADDR}${NC}"
echo -e "     3. При запиті прав вставте токен адміністратора."
echo ""
echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
