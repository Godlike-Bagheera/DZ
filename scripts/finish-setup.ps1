# finish-setup.ps1 - доводка УЖЕ установленной Ubuntu Server в VirtualBox.
# Не пересоздаёт ВМ и не трогает её диск. Делает: NAT-порты -> SSH -> Docker -> проект -> docker compose up.
# Требования: VirtualBox (VBoxManage), Python с paramiko (pip install --user paramiko).
# Запуск:  .\scripts\finish-setup.ps1 -VmPass "пароль_от_ubuntu"
# Если Ubuntu ставилась вручную и логин не stud - укажите -VmUser "имя".

param(
    [Parameter(Mandatory=$true)][string]$VmPass,
    [string]$VmName = "UbuntuServ",
    [string]$VmUser = "stud",
    [int]$SshPort = 2222
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "    $m" -ForegroundColor Yellow }

# ---------- 0. VirtualBox ----------
Info "==> Ищу VirtualBox..."
$VBM = (Get-Command VBoxManage -ErrorAction SilentlyContinue)
if ($VBM) { $VBM = $VBM.Source } else {
    $cands = @(
        "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe",
        "D:\VB\VBoxManage.exe",
        "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    )
    $VBM = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $VBM) { throw "VBoxManage не найден. Добавьте путь к VirtualBox в PATH." }
Ok "OK: $VBM"

# ---------- 1. ВМ существует? ----------
Info "==> Проверяю наличие ВМ '$VmName'..."
$vmlist = & $VBM list vms | Out-String
if ($vmlist -notmatch [regex]::Escape("`"$VmName`"")) {
    throw "ВМ '$VmName' не найдена. Список ваших ВМ:`n$vmlist`nУкажите правильное имя через -VmName ""ИмяИзСписка""."
}
Ok "ВМ найдена."

# статус
$status = (& $VBM showvminfo $VmName --machinereadable | Select-String '^VMState="(.+)"').Matches[0].Groups[1].Value
Bad "Состояние ВМ: $status"

# ---------- 2. NAT-порты ----------
Info "==> Настраиваю проброс портов NAT (ssh $SshPort->22, frontend 8080->80, backend 8000->8000)..."
# правила можно менять на лету через controlvm (для запущенной ВМ)
foreach ($rule in @(
    "ssh,tcp,,${SshPort},,22",
    "frontend,tcp,,8080,,80",
    "backend,tcp,,8000,,8000")) {
    $name = $rule.Split(',')[0]
    & $VBM controlvm $VmName natpf1 delete $name 2>$null | Out-Null
    & $VBM controlvm $VmName natpf1 "$rule" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # если ВМ выключена — через modifyvm
        & $VBM modifyvm $VmName --natpf1 delete $name 2>$null | Out-Null
        & $VBM modifyvm $VmName --natpf1 "$rule" 2>$null | Out-Null
    }
}
Ok "Порты настроены."

# ---------- 3. запуск ВМ если выключена ----------
if ($status -ne "running") {
    Info "==> Запускаю ВМ (headless)..."
    Start-Process -FilePath $VBM -ArgumentList "startvm","`"$VmName`","--type","headless" -WindowStyle Hidden
    Start-Sleep -Seconds 15
}

# ---------- 4. ждём SSH-баннер ----------
Info "==> Жду SSH-баннер на 127.0.0.1:${SshPort} (до 3 мин)..."
$deadline = (Get-Date).AddMinutes(3)
$banner = $false
while ((Get-Date) -lt $deadline) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $SshPort)
        $stream = $tcp.GetStream()
        $stream.ReadTimeout = 3000
        $buf = New-Object byte[] 64
        $n = $stream.Read($buf, 0, 64)
        $txt = [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
        $tcp.Close()
        if ($txt -match "^SSH-") { $banner = $true; break }
    } catch {}
    Start-Sleep -Seconds 5
    Write-Host "    ...жду..."
}
if (-not $banner) {
    throw @'
SSH-баннер не получен. Частые причины:
  1) В Ubuntu НЕ установлен OpenSSH server. Зайдите в окно ВМ (консоль VirtualBox),
     войдите и выполните:
       sudo apt update && sudo apt install -y openssh-server
       sudo systemctl enable --now ssh
  2) Логин/порт неверны: проверьте -VmUser/-SshPort.
  3) Сеть адаптера не NAT: Network -> Adapter 1 -> Attached to: NAT.
'@
}
Ok "SSH живой!"

# ---------- 5. paramiko ----------
Info "==> Проверяю Python + paramiko..."
$PY = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $PY) { throw "Python не найден. Установите с python.org (галочка Add to PATH)." }
python -c "import paramiko" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    python -m pip install --quiet --user paramiko 2>&1 | Out-Null
    python -c "import paramiko" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Не удалось поставить paramiko. Выполните вручную: python -m pip install --user paramiko" }
}
Ok "OK"

# ---------- 6. скачиваю проект zip (без Git) ----------
Info "==> Скачиваю проект (zip с GitHub)..."
$zip = Join-Path $env:TEMP "dz.zip"
$outDir = Join-Path $env:TEMP "dz-proj"
try {
    Invoke-WebRequest "https://codeload.github.com/Godlike-Bagheera/DZ/zip/refs/heads/main" -OutFile $zip -UseBasicParsing
} catch {
    Bad "codeload недоступен, пробую api.github.com..."
    Invoke-WebRequest "https://api.github.com/repos/Godlike-Bagheera/DZ/zipball/main" -OutFile $zip -UseBasicParsing
}
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
Expand-Archive $zip -DestinationPath $outDir -Force
$root = Get-ChildItem $outDir -Directory | Select-Object -First 1
if (-not (Test-Path (Join-Path $root.FullName "docker-compose.yml"))) { throw "В архиве нет docker-compose.yml" }
Ok "Проект скачан: $($root.FullName)"

# ---------- 7. всё по SSH через python-скрипт ----------
Info "==> Ставлю Docker внутри Ubuntu, заливаю проект, запускаю контейнеры..."
$pyFile = Join-Path $PSScriptRoot "dz_finish.py"
if (-not (Test-Path $pyFile)) { throw "Не найден $pyFile (рядом с finish-setup.ps1)." }

& $PY $pyFile "127.0.0.1" $SshPort $VmUser $VmPass $root.FullName
if ($LASTEXITCODE -ne 0) { throw "Удалённая настройка завершилась с ошибкой (см. вывод выше)." }

# ---------- 8. финальная проверка с Windows ----------
Info "==> Проверка с твоей Windows:"
try {
    $r1 = Invoke-WebRequest "http://127.0.0.1:8000/api/hello/" -UseBasicParsing -TimeoutSec 15
    Ok "API OK: $($r1.Content)"
} catch { Bad "API пока не отвечает: $($_.Exception.Message)" }
try {
    $r2 = Invoke-WebRequest "http://127.0.0.1:8080/" -UseBasicParsing -TimeoutSec 15
    Ok "Фронтенд OK (HTTP $($r2.StatusCode))"
} catch { Bad "Фронтенд пока не отвечает: $($_.Exception.Message)" }

Write-Host ""
Info "=== ГОТОВО ==="
Write-Host "  Фронтенд: http://127.0.0.1:8080"
Write-Host "  API:      http://127.0.0.1:8000/api/hello/"
Write-Host "  SSH в ВМ: ssh $VmUser@127.0.0.1 -p $SshPort  (пароль: $VmPass)"
