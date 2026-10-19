# auto-setup.ps1 - polnyy avtomat dlya Windows (VirtualBox + Ubuntu Server)
# Ispolzovanie:
#   .\scripts\auto-setup.ps1 -IsoPath "C:\...\ubuntu-XX.XX-live-server-amd64.iso" -VmPass "superpass"
# Skript sam sozdaet VM, zapuskaet AVToustoiku Ubuntu (s OpenSSH), zhdet SSH,
# stavit Docker, zalyaet proekt i podnimaet konteynery. Rabotaet s lyuboy vershey 22.04+.
param(
    [Parameter(Mandatory=$true)][string]$IsoPath,
    [Parameter(Mandatory=$true)][string]$VmPass,
    [string]$VmName = "UbuntuServ",
    [string]$RepoUrl = "https://github.com/Godlike-Bagheera/DZ.git",
    [int]$RamMB = 2048,
    [int]$DiskGB = 25
)

$ErrorActionPreference = "Stop"
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

# --- nayti VBoxManage ---
Step "Ishu VirtualBox..."
$VBM = $null
$cmd = Get-Command VBoxManage -ErrorAction SilentlyContinue
if ($cmd) { $VBM = $cmd.Source }
if (-not $VBM) {
    $candidates = @(
        "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe",
        "D:\VB\VBoxManage.exe",
        "D:\VirtualBox\VBoxManage.exe",
        "D:\VB\VirtualBox.exe",
        "D:\VirtualBox\VirtualBox.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $VBM = $c; break } }
}
if ($VBM -and ($VBM -notmatch "VBoxManage")) {
    $dir = Split-Path $VBM -Parent
    $cand = Join-Path $dir "VBoxManage.exe"
    if (Test-Path $cand) { $VBM = $cand }
}
if (-not $VBM -or -not (Test-Path $VBM)) { throw "VirtualBox ne nayden. Ustanovi: https://www.virtualbox.org/wiki/Downloads" }
Write-Host "    OK: $VBM"

if (-not (Test-Path $IsoPath)) { throw "ISO ne nayden po puti: $IsoPath" }

$VMDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "DZ-VM"
New-Item -ItemType Directory -Force -Path $VMDir | Out-Null
$vdi = Join-Path $VMDir "$VmName.vdi"

# --- opredelit' versiyu Ubuntu iz imeni ISO (22.04 / 24.04 / 26.04 ...) ---
$ver = "24.04"
if ($IsoPath -match '(\d\d\.\d\d)') { $ver = $Matches[1] }
Step "Versiya Ubuntu iz ISO: $ver (podderzhivayutsya 22.04+)"

# --- cloud-init autoinstall (NoCloud): parol' peredotsya base64, khesh schitaetsya na VM ---
$VmPassB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($VmPass))
# py-gen koda: sohranim otdelno, perebasim v base64, chtoby ne slomat' YAML kvotami
$pyGenSrc = @'
import crypt, base64, sys
print(crypt.crypt(base64.b64decode(sys.argv[1]).decode(), crypt.METHOD_SHA512))
'@
$pyGenB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pyGenSrc))

$userData = @"
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard: {layout: us}
  identity:
    hostname: dzserver
    username: stud
    password: '`$6`$round5`$placeholder'
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
    - chmod 440 /target/etc/sudoers.d/stud
    - curtin in-target -- sh -c 'echo $VmPassB64 | base64 -d > /tmp/p.b64'
    - curtin in-target -- sh -c 'echo $pyGenB64 | base64 -d > /tmp/ph.py'
    - curtin in-target -- sh -c 'python3 -c "import base64,crypt;pw=base64.b64decode(open(\"/tmp/p.b64\").read()).decode();h=crypt.crypt(pw,crypt.METHOD_SHA512);open(\"/tmp/h.txt\",\"w\").write(h)"'
    - curtin in-target -- sh -c 'usermod -p "\$(cat /tmp/h.txt)" stud'
    - curtin in-target -- rm -f /tmp/p.b64 /tmp/ph.py /tmp/h.txt
"@
# zamena bahrev-ekranov backtick-mesta: PowerShell vychedit $ kak peremennye - ekraniruem
$userData = $userData.Replace('`$', '$')

$seed = Join-Path $VMDir "seed"
if (Test-Path $seed) { Remove-Item $seed -Recurse -Force }
New-Item -ItemType Directory -Force -Path $seed | Out-Null
Set-Content -Path (Join-Path $seed "user-data") -Value $userData -Encoding ASCII -NoNewline
Set-Content -Path (Join-Path $seed "meta-data") -Value "instance-id: iid-dzvm`nlocal-hostname: dzserver" -Encoding ASCII -NoNewline

# --- sozdat' ISO bezarkhivno cherez ImageMaster API (Win10+) ---
$seedIso = Join-Path $VMDir "seed.iso"
if (Test-Path $seedIso) { Remove-Item $seedIso -Force }
Step "Upakovyvayu cloud-init v seed.iso..."
try {
    $imClass = [Type]::GetTypeFromCLSID([Guid]"27354125-9F97-4B3A-9E2B-190627258484")
    $im = [Activator]::CreateInstance($imClass)
    $im.ImageFormat = 2          # Joliet
    $stream = $im.BeginRegisterImage($seedIso, "CIDATA", 0x2, 0x1)
    $root = $im.GetRootDirectory(0)
    foreach ($f in Get-ChildItem $seed) {
        $fs = $im.RegisterFileStream($root, $f.Name, 0x2, $f.FullName)
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        $ms = New-Object IO.MemoryStream(,$bytes)
        $fs.WriteStream($ms, $bytes.Length, 0) | Out-Null
        $fs.Release()
    }
    $im.EndRegisterImage($stream) | Out-Null
    $im.CloseImage($stream) | Out-Null
    [Runtime.InteropServices.Marshal]::ReleaseComObject($im) | Out-Null
} catch {
    throw "Ne udalos' sozdat' seed.iso: $($_.Exception.Message). Ustanovi Windows 10+ i povtori."
}
if (-not (Test-Path $seedIso)) { throw "seed.iso ne sozdan" }

# --- VM: chistoe peresozdanie ---
$existing = & $VBM list vms | Select-String ('"' + $VmName + '"')
if ($existing) {
    Step "VM '$VmName' uzhe est' - udalyayu dlya chistoy sborki..."
    try { & $VBM controlvm $VmName poweroff 2>$null | Out-Null } catch {}
    Start-Sleep -Seconds 3
    & $VBM unregistervm $VmName --delete | Out-Null
    Start-Sleep -Seconds 2
}
Step "Sozdayu VM '$VmName'..."
& $VBM createvm --name $VmName --ostype "Ubuntu_64" --register | Out-Null
& $VBM createhd --filename $vdi --size ([int]($DiskGB*1024)) | Out-Null
& $VBM modifyvm $VmName --memory $RamMB --cpus 2 --nic1 nat --audio none --graphicscontroller vga --vram 16
& $VBM storagectl $VmName --name "SATA" --add sata --controller IntelAhci | Out-Null
& $VBM storageattach $VmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $vdi | Out-Null
& $VBM storagectl $VmName --name "IDE" --add ide | Out-Null
& $VBM storageattach $VmName --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium $IsoPath | Out-Null
& $VBM storageattach $VmName --storagectl "IDE" --port 1 --device 0 --type dvddrive --medium $seedIso | Out-Null
Write-Host "    VM sozdana."

# --- NAT port forwarding ---
Step "NASTRAIVAYU NAT-porty: ssh 2222->22, frontend 8080->80, backend 8000->8000..."
& $VBM modifyvm $VmName --natpf1 "ssh,tcp,,2222,,22"
& $VBM modifyvm $VmName --natpf1 "frontend,tcp,,8080,,80"
& $VBM modifyvm $VmName --natpf1 "backend,tcp,,8000,,8000"

# --- start ---
Step "Zapuskaeem VM (okno vidno - ustanovka idet AVTOMATICHESKI, nichego ne tykay!)..."
& $VBM startvm $VmName | Out-Null

Step "Zhdu poavleniya SSH-banner na 127.0.0.1:2222 (avtoustoika ~5-15 min)..."
$deadline = (Get-Date).AddMinutes(30)
$ok = $false
$waited = 0
while ((Get-Date) -lt $deadline) {
    try {
        $tc = New-Object Net.Sockets.TcpClient
        $tc.Connect("127.0.0.1", 2222)
        $ns = $tc.GetStream(); $ns.ReadTimeout = 5000
        $buf = New-Object byte[] 256
        $n = $ns.Read($buf, 0, 256)
        if ($n -gt 0) {
            $txt = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
            if ($txt.StartsWith("SSH-")) { $tc.Close(); $ok = $true; break }
        }
        $tc.Close()
    } catch {}
    $waited += 15
    Write-Host "    ...zhdu ($waited sek.)"
    Start-Sleep -Seconds 15
}
if (-not $ok) { throw "SSH tak i ne podnyalsya. Smotri okno VM: vozmozhno avtoustoika stopnutsya na voprose - prisli skrinshot." }
Write-Host "    SSH zhivoy!"

# --- paramiko ---
Step "Stavlyu paramiko (pip)..."
python -m pip install --user paramiko 2>&1 | Out-Null
python -c "import paramiko" 2>$null
if ($LASTEXITCODE -ne 0) { throw "Python/paramiko ne dostupny. Ustanovi Python s python.org (galochka Add to PATH)." }

# --- proekt ---
Step "Skachivayu proekt..."
$proj = Join-Path $VMDir "dz"
if (Test-Path $proj) { Remove-Item $proj -Recurse -Force }
git clone $RepoUrl $proj 2>&1 | Out-Null
if (-not (Test-Path (Join-Path $proj "docker-compose.yml"))) { throw "git clone ne udalsya. Nuzhen Git: https://git-scm.com" }

# --- finish: zalit' faily, postavit' Docker, zapustit' compose ---
Step "Zalivayu proekt v VM, stavlyu Docker, zapuskayu compose..."
$py = @'
import paramiko, os, sys, time
host='127.0.0.1'; port=2222; user='stud'; pw=os.environ['VMP']
cli=paramiko.SSHClient(); cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
for i in range(40):
    try:
        cli.connect(host,port,user,pw,timeout=15,banner_timeout=60,auth_timeout=60); break
    except Exception as e:
        print('wait ssh:',e); time.sleep(10)
else:
    sys.exit('SSH fail')
def run(c,t=1200):
    _,o,e=cli.exec_command(c,get_pty=True,timeout=t)
    out=''
    for l in iter(o.readline,''):
        print(l,end=''); out+=l
    rc=o.channel.recv_exit_status()
    return rc,out
sftp=cli.open_sftp()
base='/home/stud/dz'
run('mkdir -p '+base)
src=sys.argv[1]
for root,dirs,files in os.walk(src):
    rel=os.path.relpath(root,src)
    relr=base if rel=='.' else (base+'/'+rel).replace('\\','/')
    if '\\.git' in root or '/.git/' in root.replace('\\','/'): continue
    try: sftp.stat(relr)
    except IOError:
        parts=relr.strip('/').split('/')
        cur=''
        for p in parts:
            cur=cur+'/'+p
            try: sftp.stat(cur)
            except IOError: sftp.mkdir(cur)
    for f in files:
        sftp.put(os.path.join(root,f), relr+'/'+f)
sftp.close()
print('--- faily zality, proveryayu docker ---')
rc,_=run('docker --version')
if rc!=0:
    print('stavlyu docker...')
    run('curl -fsSL https://get.docker.com | sudo sh',1800)
    run('sudo usermod -aG docker stud')
print('zapuskayu compose...')
run('cd ~/dz && sudo docker compose up -d --build',2400)
time.sleep(8)
run('sudo docker compose -f ~/dz/docker-compose.yml ps')
print('=== PROVERKA ===')
run('curl -s -m 10 http://localhost:8000/api/hello/; echo')
run('curl -sI -m 10 http://localhost/ | head -3')
cli.close()
print('FINISH_OK')
'@
$pyFile = Join-Path $VMDir "finish.py"
[IO.File]::WriteAllText($pyFile, $py, (New-Object Text.UTF8Encoding($false)))
$env:VMP = $VmPass
python $pyFile $proj
if ($LASTEXITCODE -ne 0) { throw "Finishnaya nastroyka ne zavershilas'. Prisley vyvod vyshe." }

Step "GOTOVO! Otkroy v brauzere:"
Write-Host "  Frontend:  http://127.0.0.1:8080" -ForegroundColor Green
Write-Host "  API:       http://127.0.0.1:8000/api/hello/" -ForegroundColor Green
Write-Host "Skryny dla otcheta: eti dve stranicy + vyvod 'docker compose ps' (vhod: ssh -p 2222 stud@127.0.0.1, parol' $VmPass)"
