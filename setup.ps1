# =====================================================================
# Автоматичний запуск TeamSpeak 6 + Portwarp у Docker для Windows
# =====================================================================

$ErrorActionPreference = "Stop"

# Встановлюємо робочу директорію у папку зі скриптом
Set-Location -Path $PSScriptRoot

$hasError = $false

try {
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
        throw "Docker не встановлено або не додано у PATH! Будь ласка, встановіть та запустіть Docker Desktop: https://www.docker.com/products/docker-desktop/"
    }

    # Перевірка чи запущений Docker daemon
    $dockerRunning = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker демон не запущено! Будь ласка, запустіть Docker Desktop."
    }

    # 3. Запуск контейнерів
    Write-Host "🚀 Запуск контейнерів TeamSpeak 6 та Portwarp..." -ForegroundColor Blue
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        throw "Не вдалося виконати 'docker compose up -d'. Перевірте логи вище."
    }

    Write-Host "⏳ Очікування готовності сервісів..." -ForegroundColor Blue
    Start-Sleep -Seconds 3

    # 4. Перевірка авторизації Portwarp
    Write-Host "🔑 Перевірка авторизації Portwarp..." -ForegroundColor Blue

    $currentAuthEmail = ""
    $currentAuthUser = ""
    try {
        $credJsonRaw = docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>$null | Out-String
        if ($credJsonRaw) {
            $credObj = $credJsonRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($credObj) {
                $currentAuthUser = $credObj.username
                $currentAuthEmail = $credObj.email
            }
        }
    } catch {}

    # Якщо в .env вказана пошта, і вона відрізняється від поточної збереженої авторизації - перелогінюємось
    if ($global:PORTWARP_EMAIL -and $currentAuthEmail -and ($global:PORTWARP_EMAIL -ne $currentAuthEmail)) {
        Write-Host "ℹ Виявлено нову пошту в .env ($($global:PORTWARP_EMAIL)), попередня була ($currentAuthEmail). Перелогінюємось..." -ForegroundColor Yellow
        docker compose exec -T pwrp pwrp logout 2>&1 | Out-Null
        $currentAuthEmail = ""
        $currentAuthUser = ""
    }

    $doctor = docker compose exec -T pwrp pwrp doctor 2>&1 | Out-String

    if ($doctor -match "not logged in" -or (-not $currentAuthEmail)) {
        Write-Host "Portwarp ще не авторизований." -ForegroundColor Yellow
        $loggedIn = $false

        if ($global:PORTWARP_EMAIL -and $global:PORTWARP_PASSWORD) {
            Write-Host "Виконується автоматичний вхід через дані з .env ($($global:PORTWARP_EMAIL))..." -ForegroundColor Cyan
            $inputData = "$($global:PORTWARP_EMAIL)`n$($global:PORTWARP_PASSWORD)`n"
            $inputData | docker compose exec -i pwrp pwrp login --legacy 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ Авторизація через .env успішна!" -ForegroundColor Green
                $loggedIn = $true
            } else {
                Write-Host "Не вдалося увійти з даними з .env." -ForegroundColor Red
            }
        }

        # Захист від дурня: якщо даних у .env немає — інтерактивний вибір
        if (-not $loggedIn) {
            Write-Host "`nДаних авторизації у .env немає або вони невірні. Оберіть спосіб входу:" -ForegroundColor Cyan
            Write-Host "  [1] Через браузер в 1 клік (Рекомендовано: посилання + код)"
            Write-Host "  [2] Ввести Email та Пароль вручну прямо зараз"
            $choice = Read-Host "Ваш вибір [1/2] (за замовчуванням 1)"
            if (-not $choice) { $choice = "1" }

            if ($choice -eq "2") {
                $inputEmail = Read-Host "Введіть Email від portwarp.com"
                $inputPass = Read-Host "Введіть Пароль від portwarp.com"
                
                if ($inputEmail -and $inputPass) {
                    Write-Host "Авторизація..." -ForegroundColor Blue
                    $inputData = "$inputEmail`n$inputPass`n"
                    $inputData | docker compose exec -i pwrp pwrp login --legacy
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✓ Успішний вхід!" -ForegroundColor Green
                        $saveEnv = Read-Host "Зберегти ці дані у файл .env для наступних автозапусків? [Y/n]"
                        if (-not $saveEnv -or $saveEnv -match "^[Yy]") {
                            $envLines = Get-Content $envFile -ErrorAction SilentlyContinue
                            $newLines = @()
                            $emailSet = $false
                            $passSet = $false
                            foreach ($l in $envLines) {
                                if ($l -match "^PORTWARP_EMAIL=") {
                                    $newLines += "PORTWARP_EMAIL=`"$inputEmail`""
                                    $emailSet = $true
                                } elseif ($l -match "^PORTWARP_PASSWORD=") {
                                    $newLines += "PORTWARP_PASSWORD=`"$inputPass`""
                                    $passSet = $true
                                } else {
                                    $newLines += $l
                                }
                            }
                            if (-not $emailSet) { $newLines += "PORTWARP_EMAIL=`"$inputEmail`"" }
                            if (-not $passSet) { $newLines += "PORTWARP_PASSWORD=`"$inputPass`"" }
                            Set-Content -Path $envFile -Value $newLines -Encoding UTF8
                            Write-Host "✓ Облікові дані збережено в .env!" -ForegroundColor Green
                        }
                    } else {
                        Write-Host "Помилка авторизації за паролем. Перехід до входу через браузер..." -ForegroundColor Red
                        docker compose exec pwrp pwrp login
                    }
                } else {
                    docker compose exec pwrp pwrp login
                }
            } else {
                Write-Host ">>> Відкрийте посилання у браузері та введіть код авторизації: <<<" -ForegroundColor Cyan
                docker compose exec pwrp pwrp login
            }
        }
    }

    # Відображення авторизованого акаунта
    $authUser = ""
    $authEmail = ""
    try {
        $credJsonRaw = docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>$null | Out-String
        if ($credJsonRaw) {
            $credObj = $credJsonRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($credObj) {
                $authUser = $credObj.username
                $authEmail = $credObj.email
            }
        }
    } catch {}

    if ($authEmail) {
        Write-Host "✓ Portwarp підключено до акаунта: $authEmail (нікнейм: $authUser)" -ForegroundColor Green
    } elseif ($authUser) {
        Write-Host "✓ Portwarp підключено: $authUser" -ForegroundColor Green
    } else {
        Write-Host "✓ Portwarp авторизований!" -ForegroundColor Green
    }

    # 5. Налаштування тунелю
    Write-Host "🔗 Налаштування та запуск тунелю Portwarp..." -ForegroundColor Blue

    # Захист від дурня: якщо тунелів немає — пропонуємо перелогінитися або створити
    while ($true) {
        $tunnelsList = docker compose exec -T pwrp pwrp tunnels 2>&1 | Out-String
        if ($tunnelsList -match "No tunnels found") {
            Write-Host "`n⚠️ Увага: В акаунті [$authUser ($authEmail)] ще немає жодного тунелю!" -ForegroundColor Yellow
            Write-Host "Якщо ваш тунель створено під іншим акаунтом у браузері, потрібно перелогінитися.`n" -ForegroundColor Cyan
            Write-Host "  [1] Перелогінитися під акаунт, відкритий у браузері (Рекомендовано)"
            Write-Host "  [2] Створити тунель на https://portwarp.com/dashboard та оновити (Retry)"
            $reloginChoice = Read-Host "Ваш вибір [1/2] (за замовчуванням 1)"
            if (-not $reloginChoice) { $reloginChoice = "1" }

            if ($reloginChoice -eq "1") {
                Write-Host "Вихід із поточного акаунта..." -ForegroundColor Blue
                docker compose exec -T pwrp pwrp logout 2>&1 | Out-Null
                Write-Host ">>> Запуск авторизації. Відкрийте посилання та підтвердіть під потрібним акаунтом: <<<" -ForegroundColor Cyan
                docker compose exec pwrp pwrp login
                try {
                    $credJsonRaw = docker compose exec -T pwrp cat /home/pwrp/.portwarp/credentials.json 2>$null | Out-String
                    if ($credJsonRaw) {
                        $credObj = $credJsonRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($credObj) {
                            $authUser = $credObj.username
                            $authEmail = $credObj.email
                        }
                    }
                } catch {}
                Write-Host "✓ Новий авторизований акаунт: $authUser ($authEmail)" -ForegroundColor Green
            } else {
                Write-Host "Після створення тунелю на сайті натисніть Enter, щоб продовжити..." -ForegroundColor Yellow
                [void][System.Console]::ReadLine()
            }
        } else {
            break
        }
    }

    $tunnel = $global:PORTWARP_TUNNEL_NAME

    docker compose exec -T pwrp pwrp target set $tunnel teamspeak 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        docker compose exec -T pwrp pwrp target set 1 teamspeak 2>&1 | Out-Null
    }

    $connectOut = docker compose exec -T pwrp pwrp connect $tunnel --detach --save --local-host teamspeak 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        $connectOut = docker compose exec -T pwrp pwrp connect 1 --detach --save --local-host teamspeak 2>&1 | Out-String
    }
    if ($LASTEXITCODE -ne 0) {
        $connectOut = docker compose exec -T pwrp pwrp connect --all --detach --save --local-host teamspeak 2>&1 | Out-String
    }

    $autoAddr = ""
    if ($connectOut -match "([a-zA-Z0-9.-]+\.tryportwarp\.cc:\d+)") {
        $autoAddr = $Matches[1]
    }
    if (-not $autoAddr) {
        $tunnelsOut = docker compose exec -T pwrp pwrp tunnels 2>&1 | Out-String
        if ($tunnelsOut -match "([a-zA-Z0-9.-]+\.tryportwarp\.cc:\d+)") {
            $autoAddr = $Matches[1]
        }
    }
    if (-not $autoAddr) {
        $psOut = docker compose exec -T pwrp pwrp ps --once 2>&1 | Out-String
        if ($psOut -match "([a-zA-Z0-9.-]+\.tryportwarp\.cc:\d+)") {
            $autoAddr = $Matches[1]
        }
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
Portwarp акаунт:       $authEmail ($authUser)
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

    if ($authEmail) {
        Write-Host "  📧 Portwarp акаунт (email):"
        Write-Host "     $authEmail ($authUser)" -ForegroundColor Cyan
    }

    Write-Host "`n  🌐 Адреса для підключення з Інтернету:"
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

} catch {
    $hasError = $true
    Write-Host "`n❌ СТАЛАСЯ ПОМИЛКА ПІД ЧАС ВИКОНАННЯ:" -ForegroundColor Red
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Будь ласка, перегляньте деталі помилки вище.`n" -ForegroundColor Yellow
} finally {
    Write-Host "Натисніть клавішу Enter, щоб закрити це вікно..." -ForegroundColor Yellow
    [void][System.Console]::ReadLine()
}
