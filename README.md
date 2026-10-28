# TeamSpeak 6 Server Beta + Portwarp у Docker (Повна автоматизація)

Повний стек для автоматичного розгортання сервера **TeamSpeak 6 (Beta)** у Docker з тунелем **Portwarp** без потреби у білій статичній IP-адресі.

---

## 📁 Структура проєкту

* `setup.sh` — головний all-in-one скрипт для **Linux / macOS**.
* `setup.ps1` — головний all-in-one скрипт для **Windows (PowerShell)**.
* `.env` / `.env.example` — конфігураційний файл (можна вказати логін/пароль Portwarp для 100% тихого автоналаштування).
* `Dockerfile` — збірка контейнера TeamSpeak 6 Server Beta.
* `docker-compose.yml` — опис сервісів `teamspeak` та `pwrp` (Portwarp CLI) у спільній bridge-мережі.
* `get-admin-token.sh` — скрипт вилучення токена адміністратора та пароля ServerQuery.
* `portwarp-setup.sh` — скрипт швидкого перепідключення тунелю.

---

## ⚡ Як користуватися: 2 простих варіанти
0. Створюємо аккаунт Portwarp та створюємо Tunnel
<img width="1421" height="751" alt="image" src="https://github.com/user-attachments/assets/d583b6bb-a9f3-4fbd-b0cf-1484477d6739" />
<img width="1301" height="668" alt="image" src="https://github.com/user-attachments/assets/333815d2-5cf1-4231-9488-875979b5f9ea" />
<img width="1260" height="722" alt="image" src="https://github.com/user-attachments/assets/cd87166c-5598-4ed9-bed2-d14fe3361b88" />
<img width="1285" height="777" alt="image" src="https://github.com/user-attachments/assets/8d70212d-792e-467e-b524-fc918b44f57c" />

   
### 🌟 Варіант А: 100% Автоматизація через `.env` (без браузера)
1. Відкрийте файл `.env`:
   ```bash
   nano .env
   ```
2. Вкажіть ваші дані акаунта `portwarp.com` та вставте адресу яку оримали при відкритті тунелю:
   ```env
   PORTWARP_EMAIL="ваш_email@gmail.com"
   PORTWARP_PASSWORD="ваш_пароль"
   PORTWARP_TUNNEL_NAME="TeamSpeak 3"
   PORTWARP_PUBLIC_ADDRESS="i6zuaqdg.free.tryportwarp.cc:12345"
   ```
3. Запустіть один скрипт:
   * **На Linux / macOS:**
     ```bash
     ./setup.sh
     ```
   * **На Windows (PowerShell):**
     ```powershell
     .\setup.ps1
     ```
   *Скрипт сам увійде в акаунт, прив'яже тунель, запустить TeamSpeak і виведе готові ключі та адресу для друзів!*

---

### 🌐 Варіант Б: Авторизація в 1 клік через браузер (Device Flow)
Якщо ви не хочете вводити пароль у файл:
1. Залиште поля `PORTWARP_EMAIL` та `PORTWARP_PASSWORD` у `.env` порожніми.
2. Запустіть:
   * **На Linux / macOS:** `./setup.sh`
   * **На Windows (PowerShell):** `.\setup.ps1`
3. Відкрийте у браузері посилання [https://portwarp.com/device](https://portwarp.com/device) та введіть 8-значний код із терміналу.
4. Скрипт сам автоматично підхопить підключення, запустить тунель і надрукує дані для входу.

---

## 🔑 Ваші поточні дані сервера

* **Публічна адреса:**
  ```text
  i6zuaqdg.free.tryportwarp.cc:12345
  ```
* **Локальна адреса (з цього ПК):**
  ```text
  localhost:9987
  ```
* **Ключ повного адміністратора (ServerAdmin Token):**
  ```text
  someTokenDgTxLObtDcqfv6BJBjj69s5TdCe9HMn
  ```
* **ServerQuery Admin:**
  * Login: `serveradmin`
  * Password: `passiKzv`

---

## 🛠 Керування сервером

* **Перевірити статус підключення Portwarp:**
  ```bash
  docker compose exec pwrp pwrp ps
  ```
* **Перегляд логів сервера TeamSpeak:**
  ```bash
  docker compose logs -f teamspeak
  ```
* **Зупинити все:**
  ```bash
  docker compose down
  ```
* **Запустити повторно:**
  ```bash
  ./setup.sh
  ```
