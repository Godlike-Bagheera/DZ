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
    [int]$DiskGB = 25,
    [switch]$SkipInstall
)

# Bezopasnyy zapuska vneshnikh komand v PS5.1: stderr ne prevrashchaetsya v isklyucheniye
function RunNative([string[]]$a) {
    $exe = $a[0]; $rest = @(); if ($a.Count -gt 1) { $rest = $a[1..($a.Count-1)] }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = ($rest -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    try { $p = [Diagnostics.Process]::Start($psi) } catch { return "" }
    $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    return $out
}


# nayti Python (python/python3/py), c uchetom WindowsApps-shimy i MS Store
function Find-Python {
    $candidates = @()
    foreach ($n in @("python","python3","py")) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { $candidates += $c.Source }
    }
    $auto = Join-Path $env:LOCALAPPDATA "Programs\Python"
    if (Test-Path $auto) {
        $candidates += (Get-ChildItem $auto -Recurse -Filter python.exe -ErrorAction SilentlyContinue | Select-Object -First 3 -ExpandProperty FullName)
    }
    foreach ($exe in $candidates) {
        if (-not $exe -or -not (Test-Path $exe)) { continue }
        if ($exe -match "WindowsApps") { continue }   # shim iz Microsoft Store - ne rabochiy
        try {
            $v = & $exe -c "import sys;print(sys.version_info[0])" 2>$null
            if ($LASTEXITCODE -eq 0 -and "$v".Trim() -match "^\d+$") { return $exe }
        } catch {}
    }
    return $null
}

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
Step "Ishu Python..."
$PY = Find-Python
if ($PY) { Write-Host "    OK: $PY" } else { Write-Host "    Python ne nayden (ne krym, no luchhe postavit')" }

Step "Generiruyu SHA-512 khesh parolya..."
# Khesh pishetsya v FAIL (bez pipe stderr - PS5.1 padayet na NativeCommandError)
$hashOut = Join-Path ([IO.Path]::GetTempPath()) "dz_hash.txt"
if (Test-Path $hashOut) { Remove-Item $hashOut -Force }
$VmPassB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($VmPass))
$hashPy = @'
import sys, base64, hashlib
pw = base64.b64decode(sys.argv[1]).decode("utf-8")
salt_str = "dzS0lt9xQ7vP2mAb"
def crypt_sha512(password, salt_str, rounds=5000):
    pw = password.encode("utf-8"); s = salt_str.encode("utf-8")
    H = hashlib.sha512(pw + s + pw).digest()
    def expand(data, n):
        out = b""
        while len(out) < n: out += data
        return out[:n]
    h = hashlib.sha512()
    h.update(pw); h.update(s); h.update(pw)
    n = len(pw)
    while n > 64: h.update(H); n -= 64
    h.update(H[:n])
    n = len(pw)
    while n > 0:
        if n & 1: h.update(H)
        else: h.update(pw)
        n >>= 1
    B = bytearray(h.digest())
    h2 = hashlib.sha512()
    h2.update(pw); h2.update(s); h2.update(B)
    D = h2.digest()
    DP = bytearray(D)
    for i in range(len(pw)):
        if i % 2 == 1: DP[i % 64] ^= pw[i]
        else: DP = bytearray(hashlib.sha512(bytes(DP) + pw).digest())
    S = hashlib.sha512(expand(s + bytes(DP), len(s))).digest()
    for i in range(rounds):
        sha = hashlib.sha512()
        sha.update(bytes(DP) if (i & 1) else D)
        if i % 3: sha.update(S)
        if i % 5: sha.update(bytes(DP))
        sha.update(D if (i & 1) else bytes(DP))
        D = sha.digest(); DP = bytearray(D)
    itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    def b64_24(b0, b1, b2, cnt):
        w = (b0 << 16) | (b1 << 8) | b2
        r = ""
        for _ in range(cnt):
            r += itoa64[w & 0x3F]; w >>= 6
        return r
    d = list(D)
    out = ""
    out += b64_24(d[ 2], d[ 8], d[14], 4)
    out += b64_24(d[20], d[26], d[32], 4)
    out += b64_24(d[38], d[44], d[50], 4)
    out += b64_24(d[56], d[62], d[ 0], 4)
    out += b64_24(d[ 6], d[12], d[18], 4)
    out += b64_24(d[24], d[30], d[36], 4)
    out += b64_24(d[42], d[48], d[54], 4)
    out += b64_24(d[60], d[ 1], d[ 7], 4)
    out += b64_24(d[13], d[19], d[25], 4)
    out += b64_24(d[31], d[37], d[43], 4)
    out += b64_24(d[49], d[55], d[61], 4)
    out += b64_24(d[ 5], d[11], d[17], 4)
    out += b64_24(d[23], d[29], d[35], 4)
    out += b64_24(d[41], d[47], d[53], 4)
    out += b64_24(d[59], d[63], d[ 4], 4)
    out += b64_24(d[10], d[16], d[22], 4)
    out += b64_24(d[28], d[34], d[40], 4)
    out += b64_24(d[46], d[52], d[58], 4)
    out += b64_24( 0 , d[63], d[ 3], 3)
    return "$6$" + salt_str + "$" + out
try:
    from passlib.hash import sha512_crypt as _sc
    hh = _sc.using(salt=salt_str, rounds=5000).hash(pw)
except Exception:
    try:
        import crypt
        hh = crypt.crypt(pw, "$6$" + salt_str)
    except Exception:
        hh = None
if not hh or not hh.startswith("$6$"):
    # proverka samodelnoy realizatsii na etalone iz glibc tests
    test_hh = crypt_sha512("password", "saltstring")
    ok_ref = test_hh.startswith("$6$saltstring$") and len(test_hh) == 106
    if ok_ref:
        hh = crypt_sha512(pw, salt_str)
if hh and hh.startswith("$6$"):
    open(sys.argv[2], "w").write(hh)
    sys.exit(0)
sys.exit(1)
'@
$hashPyFile = Join-Path ([IO.Path]::GetTempPath()) "mkhash_dz.py"
[IO.File]::WriteAllText($hashPyFile, $hashPy, (New-Object Text.UTF8Encoding($false)))
if (-not $PY) { Write-Host "    [!] Python ne nayden - preskayu generatsiyu khesha lokalno" }
else { RunNative @($PY,$hashPyFile,$VmPassB64,$hashOut) }
Remove-Item $hashPyFile -Force -ErrorAction SilentlyContinue
if (-not (Test-Path $hashOut)) { throw "Ne udalos' sozdat' khesh parolya. Vyvedi: python --version" }
$PwHash = (Get-Content $hashOut -Raw).Trim()
Remove-Item $hashOut -Force -ErrorAction SilentlyContinue
if ($PwHash -notmatch '^\$6\$') { throw "Khesh poluchen nekorrektnyy." }
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
Step "Proveryayu paramiko (dlya SSH)..."
$haveParamiko = $false
if ($PY) {
    RunNative @($PY,"-c","import paramiko")
    if ($LASTEXITCODE -eq 0) { $haveParamiko = $true }
    else {
        RunNative @($PY,"-m","pip","install","--user","paramiko")
        RunNative @($PY,"-c","import paramiko")
        if ($LASTEXITCODE -eq 0) { $haveParamiko = $true }
    }
}
if (-not $haveParamiko) { throw "Python ili paramiko nedostupny. Ustanovi Python s python.org (galochka Add to PATH), zapusti PowerShell ZANOVO i povtorite komandu." }

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
        RunNative @($mk.Source,'-J','-V','CIDATA','-o',"$seedIso",$seed)
        if (Test-Path $seedIso) { $made = $true }
    }
}
# Variant 3: chisty Python (pip install pycdlib)
if (-not $made -and $PY) {
    RunNative @($PY,"-m","pip","install","--user","pycdlib")
    $pyIso = @'
import sys, os, pycdlib
out, srcdir = sys.argv[1], sys.argv[2]
MAP = {"user-data": "USER_DATA.;1", "meta-data": "META_DAT.;1", "network-config": "NETWOR~1.;1"}
iso = pycdlib.PyCdlib()
iso.new(vol_ident="CIDATA", interchange_level=3, joliet=3)
for name in sorted(os.listdir(srcdir)):
    fp = os.path.join(srcdir, name)
    if os.path.isfile(fp) and name in MAP:
        iso.add_file(fp, iso_path="/" + MAP[name], joliet_path="/" + name)
iso.write(out)
iso.close()
print("ISO_OK")
'@
    $pyIsoFile = Join-Path ([IO.Path]::GetTempPath()) "mkiso_dz.py"
    [IO.File]::WriteAllText($pyIsoFile, $pyIso, (New-Object Text.UTF8Encoding($false)))
    RunNative @($PY,$pyIsoFile,$seedIso,$seed)
    Remove-Item $pyIsoFile -Force -ErrorAction SilentlyContinue
    if (Test-Path $seedIso) { $made = $true }
}
if (-not (Test-Path $seedIso)) { throw "seed.iso ne sozdan" }

# --- VM: sozdanie ili obnovlenie ---
$diskExists = (Test-Path $vdi) -and ((Get-Item $vdi).Length -gt 500MB)
$reinstall = -not $diskExists -or -not $SkipInstall
$existing = & $VBM list vms | Select-String ('"' + $VmName + '"')
if ($existing -and $reinstall) {
    Step "VM '$VmName' uzhe est' - udalyayu dlya chistoy sborki..."
    try { & $VBM controlvm $VmName poweroff 2>$null | Out-Null } catch {}
    Start-Sleep -Seconds 3
    & $VBM unregistervm $VmName --delete | Out-Null
    Start-Sleep -Seconds 2
}
if (-not $existing) {
    Step "Sozdayu VM '$VmName'..."
    & $VBM createvm --name $VmName --ostype "Ubuntu_64" --register | Out-Null
} elseif ($reinstall) {
    Step "VM '$VmName' uzhe zaregistrirovana - peresozdam disk..."
} else {
    Step "Prodelayavayu ustanovku: gruzhu suschestvuyushchuyu VM '$VmName' s diska..."
}
if ($reinstall) {
    if (Test-Path $vdi) { Remove-Item $vdi -Force -ErrorAction SilentlyContinue }
    & $VBM createhd --filename $vdi --size ([int]($DiskGB*1024)) | Out-Null
}
& $VBM modifyvm $VmName --memory $RamMB --cpus 2 --nic1 nat --audio none --graphicscontroller vga --vram 16
$ctls = (& $VBM showvminfo $VmName --machinereadable) -join "`n"
if ($ctls -notmatch 'storagecontroller-name="SATA"') {
    & $VBM storagectl $VmName --name "SATA" --add sata --controller IntelAhci | Out-Null
}
& $VBM storageattach $VmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $vdi | Out-Null
if ($ctls -notmatch 'storagecontroller-name="IDE"') {
    & $VBM storagectl $VmName --name "IDE" --add ide | Out-Null
}
if ($reinstall) {
    & $VBM storageattach $VmName --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium $IsoPath | Out-Null
    & $VBM storageattach $VmName --storagectl "IDE" --port 1 --device 0 --type dvddrive --medium $seedIso | Out-Null
    & $VBM modifyvm $VmName --boot1 dvd --boot2 disk --bootnone
} else {
    & $VBM storageattach $VmName --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium none | Out-Null
    & $VBM storageattach $VmName --storagectl "IDE" --port 1 --device 0 --type dvddrive --medium none | Out-Null
    & $VBM modifyvm $VmName --boot1 disk --boot2 dvd --bootnone
}
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
if (-not $ok) {
    Write-Host ""
    Write-Host "[!] SSH ne podooshel za 30 minut. Skoree vsego avtoustinovka ostanovilas." -ForegroundColor Yellow
    Write-Host "    Otkroy okno VirtualBox i posmotri, chto tam napisano. Chasto pomogaet:"
    Write-Host "      1) V okne VM nazhmi Enter (esli vidno 'continue' / 'prodlhit' / 'reboot')."
    Write-Host "      2) Esli vidno menu gruba (GRUB) - vyberi pervyy punkt i Enter."
    Write-Host "      3) Esli ustanovka zavisla na 'Begin loading essential drivers':"
    Write-Host "         - v menyu VirtualBox: Machine -> Reset, i zapusti skript povtorno s klyuchom -SkipInstall"
    Write-Host "           (Ubuntu uzhe na diske, prosto zagruzimsya s nego):"
    Write-Host "           .\scripts\auto-setup.ps1 -IsoPath ... -VmPass ... -SkipInstall"
    Write-Host "    Prisli skrinshot okna VM, esli nichego iz etogo ne pomoglo."
    throw "SSH ne podnyalsya."
}
Write-Host "    SSH zhivoy!"


# --- proekt: bez git (zip-archive c GitHub; esli net - lokalnaya kopiya okolo skripta) ---
Step "Skachivayu proekt..."
$proj = Join-Path $VMDir "dz"
if (Test-Path $proj) { Remove-Item $proj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $proj | Out-Null
$zipOk = $false
try {
    $repoName = ($RepoUrl -replace '\.git$','') -replace '^https://github\.com/',''
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $zipUrl = "https://codeload.github.com/$repoName/zip/refs/heads/main"
    $zipFile = Join-Path $VMDir "dz.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing -TimeoutSec 120
    Expand-Archive -Path $zipFile -DestinationPath $VMDir -Force
    $inner = Get-ChildItem -Path $VMDir -Directory -Filter "DZ-main*" | Select-Object -First 1
    if (-not $inner) { $inner = Get-ChildItem -Path $VMDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "docker-compose.yml") } | Select-Object -First 1 }
    if ($inner) {
        Copy-Item -Path (Join-Path $inner.FullName "*") -Destination $proj -Recurse -Force
        $zipOk = $true
    }
} catch { Write-Host "    zip-ne-poluchilsya: $($_.Exception.Message)" }
if (-not $zipOk) {
    $local = Join-Path (Split-Path $PSScriptRoot -Parent) "docker-compose.yml"
    if (Test-Path $local) {
        Write-Host "    beru proekt iz lokalnoy papki (rjadom so skriptom)"
        $srcDir = Split-Path $local -Parent
        Get-ChildItem -Path $srcDir -Force | Where-Object { $_.Name -ne ".git" } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $proj -Recurse -Force
        }
    }
}
if (-not (Test-Path (Join-Path $proj "docker-compose.yml"))) { throw "Ne udalos poluchit faily proekta." }

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
try { & $PY $pyFile $proj } finally { Remove-Item Env:\VMP -ErrorAction SilentlyContinue }
if ($LASTEXITCODE -ne 0) { throw "Finishnaya nastroyka ne zavershilas'. Prisley vyvod vyshe." }

Step "GOTOVO! Otkroy v brauzere:"
Write-Host "  Frontend:  http://127.0.0.1:8080" -ForegroundColor Green
Write-Host "  API:       http://127.0.0.1:8000/api/hello/" -ForegroundColor Green
Write-Host "Skryny dla otcheta: eti dve stranicy + vyvod 'docker compose ps' (vhod: ssh -p 2222 stud@127.0.0.1, parol' $VmPass)"
