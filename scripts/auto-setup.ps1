# auto-setup.ps1 — полный автомат для Windows (VirtualBox + Ubuntu Server)
# Использование:
#   1) Установи VirtualBox и скачай ISO: https://ubuntu.com/download/server (ubuntu-24.04-live-server-amd64.iso)
#   2) Запусти ЭТОТ скрипт от обычного пользователя в PowerShell:
#        Set-ExecutionPolicy -Scope Process Bypass -Force
#        .\scripts\auto-setup.ps1 -IsoPath "C:\Downloads\ubuntu-24.04-live-server-amd64.iso" -VmPass "superpass"
#   3) Скрипт сам создаст ВМ, запустит её с автоустановкой Ubuntu Server (с OpenSSH!),
#      дождётся SSH, поставит Docker, зальёт проект и поднимет контейнеры.
param(
    [Parameter(Mandatory=$true)][string]$IsoPath,     # путь к скачанному ISO Ubuntu Server
    [Parameter(Mandatory=$true)][string]$VmPass,      # пароль, который зададим для юзера stud
    [string]$VmName = "UbuntuServ",
    [string]$RepoUrl = "https://github.com/Godlike-Bagheera/DZ.git",
    [int]$RamMB = 2048,
    [int]$DiskGB = 25
)

$ErrorActionPreference = "Stop"
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

# --- найти VBoxManage ---
Step "Ищу VirtualBox..."
$VBM = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $VBM)) { $VBM = (Get-Command VBoxManage -ErrorAction SilentlyContinue)?.Source }
if (-not $VBM) { throw "VirtualBox не найден. Установи: https://www.virtualbox.org/wiki/Downloads и повтори запуск." }
Write-Host "    OK: $VBM"

if (-not (Test-Path $IsoPath)) { throw "ISO не найден по пути: $IsoPath. Скачай: https://ubuntu.com/download/server" }

$VMDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "DZ-VM"
New-Item -ItemType Directory -Force -Path $VMDir | Out-Null
$vdi = Join-Path $VMDir "$VmName.vdi"

# --- cloud-init автоустановка (чтобы не тыкать мышкой в установщике) ---
Step "Готовлю файл автоустановки Ubuntu (cloud-init/subiquity)..."
$userData = @"
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard: {layout: us}
  identity:
    hostname: dzserver
    username: stud
    password: "$(python -c "import crypt;print(crypt.crypt('$VmPass',crypt.METHOD_SHA512))" 2>$null)"
  ssh:
    install-server: true
    allow-pw: true
  storage:
    layout:
      name: direct
  apt:
    primary: [{arches: [amd64], uri: http://archive.ubuntu.com/ubuntu/}]
  packages:
    - openssh-server
    - curl
  late-commands:
    - echo 'stud ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/stud
"@ -replace '\$\(python.*?\)', ''  # заглушка, пароль ниже через хеш
# Проще: сгенерировать sha512-crypt хеш на PowerShell
$salt = -join ((48..57)+(97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_})
Add-Type -AssemblyName System.Security
function Crypt-Mkpass([string]$pass, [string]$salt) {
    # crypt(3) sha512: используем готовый способ через openssl если есть, иначе python из коробки не нужен —
    # subiquity принимает и plaintext через user-data? Нет. Используем $6$ через DotNet bcrypt нельзя.
    # Решение: ставим пароль позже по SSH (первый вход через cloud-init с временным паролем 'changeme').
    return $null
}
# Надёжнее: автоустановка без пароля, а пароль ставим сразу после первого входа по SSH (cloud-init создаёт юзера с par-хешем ниже).
$sha = ""
try {
    $py = (Get-Command python -ErrorAction SilentlyContinue)?.Source
    if ($py) { $sha = & $py -c "import crypt;print(crypt.crypt('$VmPass', '\$6`$$salt'))" }
} catch {}
if (-not $sha) {
    # fallback: openssl passwd -6
    $ossl = (Get-Command openssl -ErrorAction SilentlyContinue)?.Source
    if ($ossl) { $sha = & $ossl passwd -6 -salt $salt $VmPass }
}
if (-not $sha) { throw "Не могу захешировать пароль (нужен python или openssl). Поставь Python с python.org и повтори." }

$userData = @"
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard: {layout: us}
  identity:
    hostname: dzserver
    username: stud
    password: "$sha"
  ssh:
    install-server: true
    allow-pw: true
  storage:
    layout:
      name: direct
  packages:
    - openssh-server
    - curl
    - python3
  late-commands:
    - echo 'stud ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/stud
"@
$cid = Join-Path $VMDir "user-data"
Set-Content -Path $cid -Value $userData -Encoding ASCII -NoNewline

# --- создать ВМ ---
Step "Создаю ВМ '$VmName'..."
& $VBM createvm --name $VmName --ostype "Ubuntu_64" --register | Out-Null
& $VBM createhd --filename $vdi --size $([int]($DiskGB*1024)) | Out-Null
& $VBM modifyvm $VmName --memory $RamMB --cpus 2 --nic1 nat --audio none --graphicscontroller vga --vram 16
& $VBM storagectl $VmName --name "SATA" --add sata --controller IntelAhci | Out-Null
& $VBM storageattach $VmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $vdi | Out-Null
& $VBM storagectl $VmName --name "IDE" --add ide | Out-Null
& $VBM storageattach $VmName --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium $IsoPath | Out-Null
# облако cloud-init как второй диск
$ciddisk = Join-Path $VMDir "cid.vdi"
if (Test-Path $ciddisk) { Remove-Item $ciddisk -Force }
& $VBM createhd --filename $ciddisk --size 10 --format VDI | Out-Null
& $VBM storageattach $VmName --storagectl "SATA" --port 1 --device 0 --type hdd --medium $ciddisk | Out-Null
# записать user-data в iso-образ cloud-init проще через NoCloud на CD: делаем small ISO
$mkisoinfo = Get-Command genisoimage,mkisofs -ErrorAction SilentlyContinue
& $VBM storageattach $VmName --storagectl "IDE" --port 1 --device 0 --type dvddrive --medium none | Out-Null
Write-Host "    ВМ создана."

# --- проброс портов ---
Step "Настраиваю NAT-порты: ssh 2222->22, frontend 8080->80, backend 8000->8000..."
& $VBM modifyvm $VmName --natpf1 "ssh,tcp,,2222,,22"
& $VBM modifyvm $VmName --natpf1 "frontend,tcp,,8080,,80"
& $VBM modifyvm $VmName --natpf1 "backend,tcp,,8000,,8000"

# --- cloud-init ISO (NoCloud): meta-data + user-data ---
Step "Упаковываю cloud-init в ISO..."
$seed = Join-Path $VMDir "seed"; New-Item -ItemType Directory -Force -Path $seed | Out-Null
Set-Content -Path (Join-Path $seed "user-data") -Value $userData -Encoding ASCII -NoNewline
Set-Content -Path (Join-Path $seed "meta-data") -Value "instance-id: iid-dzvm`nlocal-hostname: dzserver" -Encoding ASCII
$seedIso = Join-Path $VMDir "seed.iso"
# ищем mkisofs/xorriso
$xor = Get-Command xorriso -ErrorAction SilentlyContinue
if ($xor) {
    & xorriso -as mkisofs -o $seedIso -volid CIDATA -J $seed | Out-Null
} else {
    #powershell: используем встроенный DiscBuilder
    Add-Type -AssemblyName System.IO.FileSystem.DiscImageApi -ErrorAction SilentlyContinue
    $fs = New-Object Microsoft.Windows.SDK.FileSystem
    $img = [Windows.Storage.Blobs.StorageFile]::CreateAsync("seed.iso").GetAwaiter().GetResult()
    Write-Host "    (fallback) Создаю ISO через ImageMaster..."
    $imClass = [Type]::GetTypeFromCLSID([Guid]"27354125-9F97-4B3A-9E2B-190627258484")
    $im = [Activator]::CreateInstance($imClass)
    $im.ImageFormat = 2
    $stream = $im.BeginRegisterImage($seedIso, "CIDATA", 0x2, 0x1)
    $root = $im.GetRootDirectory(0)
    foreach ($f in Get-ChildItem $seed) {
        $s = $im.RegisterFileStream($root, $f.Name, 0x2, $f.FullName)
        $st = $f.OpenRead()
        $buf = New-Object byte[] $f.Length
        $st.Read($buf,0,$f.Length) | Out-Null
        $s.WriteAsync($buf).GetAwaiter().GetResult(); $st.Close()
    }
    $im.EndRegisterImage($stream).GetAwaiter().GetResult()
    $im.CloseImage($stream); [Runtime.InteropServices.Marshal]::ReleaseComObject($im) | Out-Null
}
& $VBM storageattach $VmName --storagectl "IDE" --port 1 --device 0 --type dvddrive --medium $seedIso | Out-Null

# --- старт ---
Step "Запускаю ВМ (окно видно — установка идёт автоматически, трогать ничего не надо)..."
& $VBM startvm $VmName | Out-Null

Step "Жду появления SSH-баннера на 127.0.0.1:2222 (автоустановка ~5-10 мин)..."
$deadline = (Get-Date).AddMinutes(25)
$ok = $false
while ((Get-Date) -lt $deadline) {
    try {
        $c = New-Object Net.Sockets.TcpClient("127.0.0.1", 2222)
        $s = $c.GetStream(); $s.ReadTimeout = 3000
        $b = New-Object byte[] 256
        $n = $s.Read($b, 0, 256)
        $txt = [Text.Encoding]::ASCII.GetString($b, 0, $n)
        if ($txt -match "^SSH-") { $c.Close(); $ok = $true; break }
        $c.Close()
    } catch { Start-Sleep 10 }
    Write-Host "    ...жду ($(((Get-Date)-$deadline).Negotiate().TotalMinutes.ToString('0') ) мин прошло)"
    Start-Sleep 10
}
if (-not $ok) { throw "SSH так и не поднялся. Смотри окно ВМ — возможно автоустановка зависла; нажми Enter/Tab там." }
Write-Host "    SSH живой!"

# --- paramiko для дальнейшей работы ---
Step "Ставлю paramiko (pip)..."
python -m pip install --user paramiko 2>&1 | Out-Null

# --- скачать проект ---
Step "Скачиваю проект..."
$proj = Join-Path $VMDir "dz"
if (Test-Path $proj) { Remove-Item $proj -Recurse -Force }
git clone $RepoUrl $proj 2>&1 | Out-Null
if (-not (Test-Path "$proj\docker-compose.yml")) { throw "git clone не удался (нужен Git: https://git-scm.com)" }

# --- всё остальное через python+paramiko ---
Step "Заливаю проект в ВМ, ставлю Docker, запускаю compose..."
$py = @"
import paramiko, os, sys, time
host='127.0.0.1'; port=2222; user='stud'; pw=os.environ['VMP']
cli=paramiko.SSHClient(); cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
for i in range(30):
    try:
        cli.connect(host,port,user,pw,timeout=15,banner_timeout=30,auth_timeout=30); break
    except Exception as e:
        print('wait',e); time.sleep(10)
else: sys.exit('SSH fail')
def run(c):
    _,o,e=cli.exec_command(c,get_pty=True,timeout=900)
    out=''
    for l in iter(o.readline,''):
        print(l,end=''); out+=l
    rc=o.channel.recv_exit_status()
    return rc,out
sftp=cli.open_sftp()
base='/home/stud/dz'
run(f'mkdir -p {base}')
for root,dirs,files in os.walk(sys.argv[1]):
    rel=os.path.relpath(root,sys.argv[1])
    if rel=='.': relr=base
    else: relr=f'{base}/{rel}'.replace(chr(92),'/')
    try: sftp.stat(relr)
    except IOError: sftp.mkdir(relr)
    for f in files:
        if '.git' in root: continue
        sftp.put(os.path.join(root,f), f'{relr}/{f}')
sftp.close()
print('--- файлы залиты, ставлю docker ---')
rc,_=run('docker --version')
if rc!=0:
    run('curl -fsSL https://get.docker.com | sudo sh')
    run('sudo usermod -aG docker stud')
run('cd ~/dz && sudo docker compose up -d --build')
time.sleep(8)
run('sudo docker compose -f ~/dz/docker-compose.yml ps')
print('=== проверка ===')
run('curl -s -m 10 http://localhost/api/hello/ || curl -s -m 10 http://localhost:8000/api/hello/')
run('curl -sI -m 10 http://localhost/ | head -3')
cli.close()
"@
$pyFile = Join-Path $VMDir "finish.py"
Set-Content -Path $pyFile -Value $py -Encoding UTF8
$env:VMP = $VmPass
python $pyFile $proj
if ($LASTEXITCODE -ne 0) { throw "Финишная настройка не завершилась" }

Step "ГОТОВО! Открой в браузере:"
Write-Host "  Фронтенд:  http://127.0.0.1:8080" -ForegroundColor Green
Write-Host "  API:       http://127.0.0.1:8000/api/hello/" -ForegroundColor Green
Write-Host "Скриншоты для отчёта: эти две страницы + вывод 'docker compose ps' (заходит: ssh -p 2222 stud@127.0.0.1, пароль $VmPass)"
