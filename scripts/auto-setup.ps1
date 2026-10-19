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

# --- cloud-init autoinstall (NoCloud): SHA-512 khesh parolya cherez lokalnyy Python ---
$VmPassB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($VmPass))
$hashPy = @'
import sys, base64
try:
    import crypt
except ImportError:
    crypt = None
def sha512_crypt(pw, salt):
    from passlib.hash import sha512_crypt as sc
    return sc.using(salt=salt).hash(pw)
pw = base64.b64decode(sys.argv[1]).decode("utf-8")
salt = "dzS0lt9xQ7vP2mAb"
h = None
if crypt is not None:
    try:
        h = crypt.crypt(pw, "$6$" + salt)
    except Exception:
        h = None
if not h or not h.startswith("$6$"):
    try:
        from passlib.hash import sha512_crypt as sc
        h = sc.using(salt=salt).hash(pw)
    except Exception:
        sys.exit(2)
if not h or not h.startswith("$6$"):
    sys.exit(3)
sys.stdout.write(h)
'@
# Python v Windows chitaet .py v koderovke UTF-8 BOM; pishem bez BOM (chisty ASCII)
$hashPyFile = Join-Path ([IO.Path]::GetTempPath()) "mkhash_dz.py"
[IO.File]::WriteAllText($hashPyFile, $hashPy, (New-Object Text.UTF8Encoding($false)))
Step "Generiruyu SHA-512 khesh parolya..."
python -m pip install --user passlib 2>&1 | Out-Null
$PwHash = (& python $hashPyFile $VmPassB64) 2>$null
if (-not $PwHash) { $PwHash = (& py -3 $hashPyFile $VmPassB64) 2>$null }
Remove-Item $hashPyFile -Force -ErrorAction SilentlyContinue
if (-not $PwHash -or ($PwHash -notmatch '^\$6\$')) {
    throw "Ne udalos' sozdat' khesh parolya (proveryu, chto Python ustanovlen: python --version)."
}
$PwHash = ($PwHash | Select-Object -First 1).Trim()
Write-Host "    OK, khesh gotov."

$userDataTemplate = @'
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard: {layout: us}
  identity:
    hostname: dzserver
    username: stud
    password: '__PW_HASH__'
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
'@
$userData = $userDataTemplate.Replace('__PW_HASH__', $PwHash)

$seed = Join-Path $VMDir "seed"
if (Test-Path $seed) { Remove-Item $seed -Recurse -Force }
New-Item -ItemType Directory -Force -Path $seed | Out-Null
Set-Content -Path (Join-Path $seed "user-data") -Value $userData -Encoding ASCII -NoNewline
Set-Content -Path (Join-Path $seed "meta-data") -Value "instance-id: iid-dzvm`nlocal-hostname: dzserver" -Encoding ASCII -NoNewline

# --- sozdat' ISO bezarkhivno cherez ImageMaster API (Win10+) ---
$seedIso = Join-Path $VMDir "seed.iso"
if (Test-Path $seedIso) { Remove-Item $seedIso -Force }
# --- paramiko + pycdlib (nuzhny i dlya sozdaniya seed.iso variantom 3) ---
Step "Stavlyu paramiko i pycdlib (pip)..."
python -m pip install --user paramiko pycdlib 2>&1 | Out-Null
python -c "import paramiko, pycdlib" 2>$null
if ($LASTEXITCODE -ne 0) { throw "Python/paramiko/pycdlib ne dostupny. Ustanovi Python s python.org (galochka Add to PATH)." }

Step "Upakovyvayu cloud-init v seed.iso..."
$made = $false
# Variant 1: IMAPI2 FS Image COM (est' vo vsekh Windows 8/10/11)
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
        $ms.Dispose()
    }
    $im.EndRegisterImage($stream) | Out-Null
    $im.CloseImage($stream) | Out-Null
    [Runtime.InteropServices.Marshal]::ReleaseComObject($im) | Out-Null
    if (Test-Path $seedIso) { $made = $true }
} catch { Write-Host "    IMAPI2 ne srabotal: $($_.Exception.Message)" }
# Variant 2: mkisofs/genisoimage esli on gde-to v PATH
if (-not $made) {
    $mk = Get-Command mkisofs -ErrorAction SilentlyContinue
    if (-not $mk) { $mk = Get-Command genisoimage -ErrorAction SilentlyContinue }
    if ($mk) {
        & $mk.Source -J -V CIDATA -o $seedIso $seed 2>&1 | Out-Null
        if (Test-Path $seedIso) { $made = $true }
    }
}
# Variant 3: chisty Python (pip install pycdlib)
if (-not $made) {
    python -m pip install --user pycdlib 2>&1 | Out-Null
    $pyIso = @'
import sys, os, pycdlib
out, srcdir = sys.argv[1], sys.argv[2]
iso = pycdlib.PyCdlib()
iso.new(vol_ident="CIDATA", rock_ridge="1.10", joliet=3)
for name in sorted(os.listdir(srcdir)):
    fp = os.path.join(srcdir, name)
    if os.path.isfile(fp):
        iso.add_file(fp, rr_name=name.encode(), joliet_path="/" + name)
iso.write(out)
iso.close()
print("ISO_OK")
'@
    $pyIsoFile = Join-Path ([IO.Path]::GetTempPath()) "mkiso_dz.py"
    [IO.File]::WriteAllText($pyIsoFile, $pyIso, (New-Object Text.UTF8Encoding($false)))
    python $pyIsoFile $seedIso $seed 2>&1 | Out-Null
    Remove-Item $pyIsoFile -Force -ErrorAction SilentlyContinue
    if (Test-Path $seedIso) { $made = $true }
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
print('--- faily zality, chinityu image-tagi (Docker Hub ne treb. imya vlastelina) ---')
run("sed -i 's#image: .*/backend-image:latest#image: dz-backend:latest#; s#image: .*/frontend-image:latest#image: dz-frontend:latest#' ~/dz/docker-compose.yml")
print('proveryayu docker...')
rc,_=run('docker --version')
if rc!=0:
    print('stavlyu docker...')
    run('curl -fsSL https://get.docker.com | sudo sh',1800)
    run('sudo usermod -aG docker stud')
print('zapuskayu compose...')
run('sudo systemctl enable --now docker; sleep 2; sudo systemctl is-active docker')
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
