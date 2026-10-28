#!/usr/bin/env bash

echo "=== Отримання ключа привілеїв (Privilege Key / Token) для TeamSpeak 6 ==="
echo ""

if ! docker ps | grep -q "ts6-server"; then
    echo "Контейнер ts6-server не запущений! Спочатку запустіть: docker compose up -d"
    exit 1
fi

echo "--- Дані облікового запису ServerQuery Admin ---"
docker logs ts6-server 2>&1 | grep -A 4 "Server Query Admin Account created" || echo "Не знайдено в поточних логах."

echo ""
echo "--- Ключ привілеїв адміністратора (ServerAdmin Token) ---"
TOKEN=$(docker logs ts6-server 2>&1 | grep -o 'token=[A-Za-z0-9+/=]*' | head -n 1)

if [ -n "$TOKEN" ]; then
    echo ">>> $TOKEN <<<"
    echo ""
    echo "Скопіюйте значення після 'token=' та використайте його при першому підключенні до сервера у TeamSpeak 6."
else
    echo "Ключ привілеїв не знайдено у логах. Можливо сервер вже запускався раніше."
    echo "Останні логи сервера:"
    docker logs --tail 25 ts6-server
fi
