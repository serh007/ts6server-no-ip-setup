#!/usr/bin/env bash
set -e

TUNNEL_NAME="TeamSpeak 3"
TARGET_HOST="teamspeak"

echo "=== Налаштування Portwarp для TeamSpeak 6 ==="
echo "Тунель: ${TUNNEL_NAME}"
echo "Цільовий сервіс: ${TARGET_HOST}:9987 (UDP)"
echo ""

# Перевірка чи запущено контейнер
if ! docker compose ps pwrp | grep -q "Up"; then
    echo "Запуск контейнерів через docker compose..."
    docker compose up -d
fi

echo "1. Перевірка статусу авторизації Portwarp..."
AUTH_STATUS=$(docker compose exec -T pwrp pwrp doctor 2>&1 || true)

if echo "$AUTH_STATUS" | grep -q "not logged in"; then
    echo ""
    echo ">>> УВАГА: Потрібно авторизуватися в Portwarp!"
    echo "Зараз буде запущено 'pwrp login'. Відкрийте посилання у браузері та підтвердіть код."
    echo ""
    docker compose exec pwrp pwrp login
fi

echo ""
echo "2. Налаштування цільового хоста для тунелю ${TUNNEL_NAME} -> ${TARGET_HOST}..."
docker compose exec -T pwrp pwrp target set "${TUNNEL_NAME}" "${TARGET_HOST}"

echo ""
echo "3. Підключення тунелю ${TUNNEL_NAME} у фоновому режимі..."
docker compose exec -T pwrp pwrp connect "${TUNNEL_NAME}" --detach --save || \
docker compose exec -T pwrp pwrp connect --all --detach --save

echo ""
echo "4. Поточний статус тунелів:"
docker compose exec -T pwrp pwrp ps --once || true

echo ""
echo "=== Portwarp успішно налаштовано! ==="
echo "Адреса для підключення у клієнті TeamSpeak 6: i6zuaqdg.free.tryportwarp.cc:10153"
