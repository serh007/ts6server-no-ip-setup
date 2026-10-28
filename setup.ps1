# =====================================================================
# Автоматичний запуск TeamSpeak 6 + Portwarp у Docker для Windows
# =====================================================================

$ErrorActionPreference = "Stop"

# Встановлюємо робочу директорію у папку зі скриптом
Set-Location -Path $PSScriptRoot

Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          АВТОМАТИЧНИЙ ЗАПУСК TEAMSPEAK 6 + PORTWARP               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# 1. Завантаження конфігурації з .env
$envFile = Join-Path $PSScriptRoot ".env"
$envExample = Join-Path $PSScriptRoot ".env.example"

if (-not (Test-Path $envFile)) {
    if (Test-Path $envExample) {
        Write-Host "ℹ Файл .env не знайдено, копіюємо з .env.example..." -ForegroundColor Yellow
        Copy-Item -Path $envExample -Destination $envFile
    }
}

$PORTWARP_EMAIL = ""
$PORTWARP_PASSWORD = ""
$PORTWARP_TUNNEL_NAME = "TeamSpeak 3"
$PORTWARP_PUBLIC_ADDRESS = ""

if (Test-Path $envFile) {
    Write-Host "ℹ Завантаження конфігурації з .env..." -ForegroundColor Blue
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and ($line -match "^(?<key>[A-Za-z0-9_]+)\s*=\s*(?<val>.*)$")) {
            $k = $Matches.key
            $v = $Matches.val.Trim().Trim('"').Trim("'")
            if ($k -eq "PORTWARP_EMAIL") { $global:PORTWARP_EMAIL = $v }
            if ($k -eq "PORTWARP_PASSWORD") { $global:PORTWARP_PASSWORD = $v }
            if ($k -eq "PORTWARP_TUNNEL_NAME" -and $v) { $global:PORTWARP_TUNNEL_NAME = $v }
            if ($k -eq "PORTWARP_PUBLIC_ADDRESS" -and $v) { $global:PORTWARP_PUBLIC_ADDRESS = $v }
        }
    }
}

# 2. Перевірка Docker
Write-Host "🔍 Перевірка Docker..." -ForegroundColor Blue
try {
    $dockerVersion = docker --version
    Write-Host "✓ $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Помилка: Docker не встановлено або не додано у PATH!" -ForegroundColor Red
    Write-Host "Будь ласка, встановіть та запустіть Docker Desktop: https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
    Exit 1
}

# Перевірка чи запущений Docker daemon
$dockerRunning = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Помилка: Docker демон не запущено! Запустіть Docker Desktop." -ForegroundColor Red
    Exit 1
}

# 3. Запуск контейнерів
Write-Host "🚀 Запуск контейнерів TeamSpeak 6 та Portwarp..." -ForegroundColor Blue
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Не вдалося запустити docker compose!" -ForegroundColor Red
    Exit 1
}

Write-Host "⏳ Очікування готовності сервісів..." -ForegroundColor Blue
Start-Sleep -Seconds 3

# 4. Перевірка авторизації Portwarp
Write-Host "🔑 Перевірка авторизації Portwarp..." -ForegroundColor Blue
$doctor = docker compose exec -T pwrp pwrp doctor 2>&1 | Out-String

if ($doctor -match "not logged in") {
    Write-Host "Portwarp не авторизований." -ForegroundColor Yellow
    if ($global:PORTWARP_EMAIL -and $global:PORTWARP_PASSWORD) {
        Write-Host "Виконується автоматичний вхід через дані з .env ($($global:PORTWARP_EMAIL))..." -ForegroundColor Cyan
        $inputData = "$($global:PORTWARP_EMAIL)`n$($global:PORTWARP_PASSWORD)`n"
        $inputData | docker compose exec -i pwrp pwrp login --legacy
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Авторизація через .env успішна!" -ForegroundColor Green
        } else {
            Write-Host "Не вдалося увійти з даними з .env. Запуск інтерактивного входу через браузер..." -ForegroundColor Red
            docker compose exec pwrp pwrp login
        }
    } else {
        Write-Host ">>> Відкрийте посилання у браузері та введіть код авторизації: <<<" -ForegroundColor Cyan
        docker compose exec pwrp pwrp login
    }
} else {
    Write-Host "✓ Portwarp уже авторизований!" -ForegroundColor Green
}

# 5. Налаштування тунелю
Write-Host "🔗 Налаштування та запуск тунелю Portwarp..." -ForegroundColor Blue
$tunnelsList = docker compose exec -T pwrp pwrp tunnels 2>&1 | Out-String
if ($tunnelsList -match "No tunnels found") {
    Write-Host "⚠️ У вашому акаунті Portwarp ще немає тунелів!" -ForegroundColor Yellow
    Write-Host "Будь ласка, перейдіть на https://portwarp.com/dashboard і створіть тунель (+ Add Tunnel: Protocol UDP, Port 9987)." -ForegroundColor Cyan
}

$tunnel = $global:PORTWARP_TUNNEL_NAME

docker compose exec -T pwrp pwrp target set $tunnel teamspeak 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    docker compose exec -T pwrp pwrp target set 1 teamspeak 2>&1 | Out-Null
}

$connectOut = docker compose exec -T pwrp pwrp connect $tunnel --detach --save 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    $connectOut = docker compose exec -T pwrp pwrp connect --all --detach --save 2>&1 | Out-String
}

$autoAddr = ""
if ($connectOut -match "([a-zA-Z0-9.-]+\.tryportwarp\.cc:\d+)") {
    $autoAddr = $Matches[1]
}

# 6. Очікування отримання токена TeamSpeak
Write-Host "⏳ Перевірка ключа привілеїв TeamSpeak 6..." -ForegroundColor Blue
$adminToken = ""
$queryPass = ""

for ($i = 1; $i -le 10; $i++) {
    $tsLogs = docker logs ts6-server 2>&1 | Out-String
    if ($tsLogs -match "token=([A-Za-z0-9+/=]+)") {
        $adminToken = $Matches[1]
        break
    }
    Start-Sleep -Seconds 1
}

$credFile = Join-Path $PSScriptRoot "admin-credentials.txt"

# Якщо в логах немає — шукаємо у збереженому файлі або базі даних
if (-not $adminToken -and (Test-Path $credFile)) {
    $credContent = Get-Content $credFile | Out-String
    if ($credContent -match "ServerAdmin Token:\s*([A-Za-z0-9+/=]+)") {
        $adminToken = $Matches[1]
    }
}

if (-not $adminToken) {
    try {
        $dbStrings = docker exec ts6-server cat /var/tsserver/tsserver.sqlitedb 2>$null
        if ($dbStrings -match "([A-Za-z0-9+/=]{40})`r?`ndefault serveradmin privilege key") {
            $adminToken = $Matches[1]
        }
    } catch {}
}

$tsLogs = docker logs ts6-server 2>&1 | Out-String
if ($tsLogs -match 'password=\s*"([^"]+)"') {
    $queryPass = $Matches[1]
} elseif (Test-Path $credFile) {
    $credContent = Get-Content $credFile | Out-String
    if ($credContent -match "pass:\s*([^\s`r`n]+)") {
        $queryPass = $Matches[1]
    }
}

# 7. Визначення публічної адреси
$publicAddr = "i6zuaqdg.free.tryportwarp.cc:10153"
if ($autoAddr) {
    $publicAddr = $autoAddr
} elseif ($global:PORTWARP_PUBLIC_ADDRESS -and $global:PORTWARP_PUBLIC_ADDRESS -notmatch "your-subdomain") {
    $publicAddr = $global:PORTWARP_PUBLIC_ADDRESS
}

# Збереження у файл admin-credentials.txt
$saveText = @"
=====================================================================
                   TEAMSPEAK 6 SERVER CREDENTIALS
=====================================================================
Адреса для підключення: $publicAddr
Локальна адреса:       localhost:9987
ServerAdmin Token:     $adminToken
ServerQuery Admin:     login: serveradmin | pass: $(if ($queryPass) { $queryPass } else { '4g5miKzv' })
=====================================================================
"@
Set-Content -Path $credFile -Value $saveText -Encoding UTF8

# 8. Підсумковий звіт
Write-Host "`n═════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "             🎉 СЕРВЕР TEAMSPEAK 6 ГОТОВИЙ ДО РОБОТИ!               " -ForegroundColor Green
Write-Host "═════════════════════════════════════════════════════════════════════`n" -ForegroundColor Green

Write-Host "  🌐 Адреса для підключення з Інтернету:"
Write-Host "     $publicAddr" -ForegroundColor Cyan

Write-Host "`n  🏠 Локальна адреса (з цього ПК):"
Write-Host "     localhost:9987" -ForegroundColor Cyan

if ($adminToken) {
    Write-Host "`n  🔑 Ключ повного адміністратора (ServerAdmin Token):"
    Write-Host "     $adminToken" -ForegroundColor Yellow
}

if ($queryPass) {
    Write-Host "`n  ⚙️  ServerQuery Admin логін / пароль:"
    Write-Host "     login: serveradmin | pass: $queryPass" -ForegroundColor Cyan
}

Write-Host "`n  💾 Дані також збережено у файл: admin-credentials.txt" -ForegroundColor Cyan

Write-Host "`n  📋 Як підключитися:"
Write-Host "     1. Відкрийте клієнт TeamSpeak 6."
Write-Host "     2. Вставте адресу: $publicAddr"
Write-Host "     3. При запиті прав вставте токен адміністратора.`n"

Write-Host "═════════════════════════════════════════════════════════════════════`n" -ForegroundColor Green

Read-Host "Натисніть Enter для виходу..."
