# finish-setup.ps1 - dovodka UZhE ustanovlennoy Ubuntu Server v VirtualBox.
# Ne peresozdayot VM i ne trogaet eyo disk. Delaet: NAT-porty -> SSH -> Docker -> proekt -> docker compose up.
# Trebovaniya: VirtualBox (VBoxManage), Python s paramiko (pip install --user paramiko).
# Zapusk:  .\scripts\finish-setup.ps1 -VmPass "parol_ot_ubuntu"
# Esli Ubuntu stavilas vruchnuyu i login ne stud - ukazhite -VmUser "imya".
# Logirovanie: vsegda pishetsya polny log v $env:USERPROFILE\dz-finish.log
#              + transcript vsego ekrana v $env:USERPROFILE\dz-finish-transcript.txt

param(
    [Parameter(Mandatory=$true)][string]$VmPass,
    [string]$VmName = "UbuntuServ",
    [string]$VmUser = "stud",
    [int]$SshPort = 2222,
    [switch]$Dbg
)

$ErrorActionPreference = "Stop"

# ---------- logging ----------
$LogFile = Join-Path $env:USERPROFILE "dz-finish.log"
$TranscriptFile = Join-Path $env:USERPROFILE "dz-finish-transcript.txt"
try { Start-Transcript -Path $TranscriptFile -Append | Out-Null } catch {}
Write-Host "Log skriptov:  $TranscriptFile" -ForegroundColor DarkGray
Write-Host "Log VM-nastrojki: $LogFile" -ForegroundColor DarkGray

function TS { Get-Date -Format "HH:mm:ss" }
function Info($m) { Write-Host ("[{0}] {1}" -f (TS), $m) -ForegroundColor Cyan }
function Ok($m)   { Write-Host ("[{0}]     {1}" -f (TS), $m) -ForegroundColor Green }
function Bad($m)  { Write-Host ("[{0}]     {1}" -f (TS), $m) -ForegroundColor Yellow }

# ---------- 0. VirtualBox ----------
Info "==> Ischu VirtualBox..."
$VBM = (Get-Command VBoxManage -ErrorAction SilentlyContinue)
if ($VBM) { $VBM = $VBM.Source } else {
    $cands = @(
        "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe",
        "D:\VB\VBoxManage.exe",
        "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    )
    $VBM = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $VBM) { throw "VBoxManage ne nayden. Dobavte put k VirtualBox v PATH." }
Ok "OK: $VBM"

# ---------- 1. VM suschestvuet? ----------
Info "==> Proveryayu nalichie VM '$VmName'..."
$vmlist = & $VBM list vms | Out-String
Info "    Spisok VM: $($vmlist.Trim())"
if ($vmlist -notmatch [regex]::Escape("`"$VmName`"" )) {
    throw "VM '$VmName' ne naydena. Spisok vashih VM:`n$vmlist`nUkazhite pravilnoe imya cherez -VmName (imya iz spiska above)."
}
Ok "VM naydena."

# status
$stateLine = (& $VBM showvminfo $VmName --machinereadable | Select-String '^VMState="(.+)"')
if (-not $stateLine) { throw "Ne udalos uznat sostoyanie VM '$VmName' (VBoxManage showvminfo). Vypolnite vruchnuyu: & `"$VBM`" showvminfo `"$VmName`" --machinereadable i prishlite vyvod." }
$status = $stateLine.Matches[0].Groups[1].Value
Bad "Sostoyanie VM: $status"

# ---------- 2. NAT-porty ----------
Info "==> Nastraivayu probros portov NAT (ssh $SshPort->22, frontend 8080->80, backend 8000->8000)..."
$rules = @(
    @{n="ssh";      r="tcp,,${SshPort},,22"},
    @{n="frontend"; r="tcp,,8080,,80"},
    @{n="backend";  r="tcp,,8000,,8000"}
)
# Vazhno: ErrorActionPreference=Stop prevrashchaet lyuboy stderr VBoxManage v fatal.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
if ($status -eq "running") {
    # na letu: chitaem sushchestvuyushchie pravila, peresozdaem tolko esli port ne tot
    $existing = @(& $VBM showvminfo $VmName --machinereadable 2>$null | Select-String '^natpf1-')
    foreach ($q in $rules) {
        $already = $existing | Where-Object { $_.ToString().StartsWith("natpf1-" + $q.n + "=") }
        if ($already) {
            Info ("  pravilo '{0}' uzhe est': {1}" -f $q.n, $already.ToString())
            $needReplace = $false
            if     ($q.n -eq "ssh")      { if ($already.ToString() -notmatch ("," + $SshPort + ",")) { $needReplace = $true } }
            elseif ($q.n -eq "frontend") { if ($already.ToString() -notmatch ",8080,") { $needReplace = $true } }
            elseif ($q.n -eq "backend")  { if ($already.ToString() -notmatch ",8000,") { $needReplace = $true } }
            if ($needReplace) {
                & $VBM controlvm $VmName natpf1 delete $q.n 2>$null | Out-Null
                & $VBM controlvm $VmName natpf1 "$($q.n),$($q.r)" 2>$null | Out-Null
            }
        } else {
            & $VBM controlvm $VmName natpf1 "$($q.n),$($q.r)" 2>$null | Out-Null
        }
    }
    $check = @(& $VBM showvminfo $VmName --machinereadable 2>$null | Select-String '^natpf1-')
    if ($check.Count -eq 0) { Bad "Ne udalos dobavit NAT-pravila na letu. Vykluchi VM (poweroff/Full Reset) i zapusti skript povtorno."; exit 1; }
} else {
    # vyklyuchena: modifyvm + proverka, chto imenno natpf1 (a ne hostonly/bridged)
    & $VBM modifyvm $VmName --natpf1 delete ssh 2>$null | Out-Null
    & $VBM modifyvm $VmName --natpf1 delete frontend 2>$null | Out-Null
    & $VBM modifyvm $VmName --natpf1 delete backend 2>$null | Out-Null
    foreach ($q in $rules) {
        & $VBM modifyvm $VmName --natpf1 "$($q.n),$($q.r)" 2>$null | Out-Null
    }
    $netInfo = & $VBM showvminfo $VmName --machinereadable | Select-String 'nic1='
    if ($netInfo -match 'hostonly|bridged|notattached') {
        Bad "Adapter1 v VM tip $(($netInfo -join '').Trim()) - NAT neobkhodim. Ustanovite: Network Adapter 1 -> Attached to: NAT, i povtorite skript."
        exit 1
    }
    Info "==> Zapuskayu VM (headless)..."
    Start-Process -FilePath $VBM -ArgumentList @("startvm", $VmName, "--type", "headless") -WindowStyle Hidden
    Start-Sleep -Seconds 15
}
Ok "Porty nastroeny."

$ErrorActionPreference = $prevEAP
# ---------- 3. (VM uzhe zapushchenya vyse) ----------

# ---------- 4. zhdyom SSH-banner ----------
Info "==> Zhdu SSH-banner na 127.0.0.1:${SshPort} (do 3 min)..."
$deadline = (Get-Date).AddMinutes(3)
$banner = $false
$attemptN = 0
while ((Get-Date) -lt $deadline) {
    $attemptN++
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $SshPort)
        $stream = $tcp.GetStream()
        $stream.ReadTimeout = 3000
        $buf = New-Object byte[] 64
        $n = $stream.Read($buf, 0, 64)
        $txt = [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
        $tcp.Close()
        Info "    proverka #${attemptN}: poluchen banner: '$($txt.Trim())'"
        if ($txt -match "^SSH-") { $banner = $true; break }
    } catch {
        Info "    proverka #${attemptN}: $($_.Exception.GetType().Name): $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 5
}
if (-not $banner) {
    throw @"
SSH-banner ne poluchen za 3 min. Diagnoz i varianty:
  1) V Ubuntu net OpenSSH server. Zaydite v okno VirtualBox (login/password kak pri ustanovke) i vypolnite:
       sudo apt update ; sudo apt install -y openssh-server ; sudo systemctl enable --now ssh
     Potom povtorite zapusk etogo skripta.
  2) Nevernyj login ili port - proverte parametry -VmUser/-SshPort.
  3) Set' adaptera VM dolzhen byt NAT (Network Adapter 1 -> Attached to: NAT).
  4) Proveryaye, cto VM voobshche zagruzilas': v okne VirtualBox dolzhna byt stroka login:.
"@

}
Ok "SSH zhivoy! (posle #${attemptN} proverok)"

# ---------- 5. paramiko ----------
Info "==> Proveryayu Python + paramiko..."
$PY = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $PY) { throw "Python ne nayden. Ustanovite s python.org (galochka Add to PATH)." }
python -c "import paramiko" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    python -m pip install --quiet --user paramiko 2>&1 | Out-Null
    python -c "import paramiko" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Ne udalos postavit paramiko. Vypolnite vruchnuyu: python -m pip install --user paramiko" }
}
Ok "OK"

# ---------- 6. skachivayu proekt zip (bez Git) ----------
Info "==> Skachivayu proekt (zip s GitHub)..."
$zip = Join-Path $env:TEMP "dz.zip"
$outDir = Join-Path $env:TEMP "dz-proj"
try {
    Invoke-WebRequest "https://codeload.github.com/Godlike-Bagheera/DZ/zip/refs/heads/main" -OutFile $zip -UseBasicParsing
} catch {
    Bad "codeload nedostupen, probuyu api.github.com..."
    Invoke-WebRequest "https://api.github.com/repos/Godlike-Bagheera/DZ/zipball/main" -OutFile $zip -UseBasicParsing
}
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
Expand-Archive $zip -DestinationPath $outDir -Force
$root = Get-ChildItem $outDir -Directory | Select-Object -First 1
if (-not (Test-Path (Join-Path $root.FullName "docker-compose.yml"))) { throw "V arhive net docker-compose.yml" }
Ok "Proekt skachan: $($root.FullName)"

# ---------- 7. vsyo po SSH cherez python-skript ----------
Info "==> Stavlyu Docker vnutri Ubuntu, zalivayu proekt, zapuskayu konteynery..."
Info "    (podrobnyj log etogo etapa: $LogFile)"
$pyFile = Join-Path $PSScriptRoot "dz_finish.py"
if (-not (Test-Path $pyFile)) { throw "Ne nayden $pyFile (ryadom s finish-setup.ps1)." }

if ($Dbg) { $env:DZ_DEBUG = "1" } else { Remove-Item Env:\DZ_DEBUG -ErrorAction SilentlyContinue }

# Avto-opredelenie realnogo login-vnutri-VM: esli vy v SSH napisali whoami=root,
# a vmeste s etim parolem vkhodit imenno root - peredajom root bez dop. parametr.
$probe = Join-Path $env:TEMP "dz_ssh_probe.py"
@'
import sys, paramiko
host, port, pw = sys.argv[1], int(sys.argv[2]), sys.argv[4]
users = [u for u in sys.argv[3].split(",") if u]
for u in users:
    try:
        c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(host, port=port, username=u, password=pw, timeout=10,
                  look_for_keys=False, allow_agent=False, banner_timeout=15, auth_timeout=15)
        print(u); c.close(); sys.exit(0)
    except Exception:
        pass
sys.exit(1)
'@ | Set-Content -Encoding ASCII $probe
$cands = "$VmUser,admin,root,stud"
& $PY $probe "127.0.0.1" $SshPort $cands $VmPass 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $found = ((& $PY $probe "127.0.0.1" $SshPort $cands $VmPass 2>$null) | Select-Object -Last 1)
    if ($found) {
        $found = $found.Trim()
        if ($found -ne $VmUser) { Info "  NAJDEN rabochiy login v VM: '$found' - ispol'zuyego ego vmesto '$VmUser'" }
        $VmUser = $found
    }
} else {
    Bad "  Eto zhe oshibka 'Authentication failed': parol ne podoshel ni k odnomu loginu ($cands)."
    Bad "  Vmestno s SSH vykhodit tol'ko banner - znachit Ubuntu pustila vas pod kakim-to drugim loginom/parolem."
    Bad "  Posmotrite kto est': v okne VirtualBox vojdite (ili esli uzhe voshli) vypolnite: whoami; ls /home"
    Bad "  I zapustite skript s veroznymi dannymi: .\scripts\finish-setup.ps1 -VmUser "TOCHNYJ_LOGIN" -VmPass "TOCHNYJ_PAROL""
    throw "SSH ne pustil ni odin variant login/parol'. Sm. vyshche."
}
Info ("  parametry: host=127.0.0.1 port={0} user='{1}' parol='{2}' (dlina {3}) proekt={4}" -f $SshPort, $VmUser, ("*" * $VmPass.Length), $VmPass.Length, $root.FullName)
& $PY $pyFile "127.0.0.1" $SshPort $VmUser $VmPass $root.FullName $LogFile
$pyExit = $LASTEXITCODE
if ($pyExit -eq 2) {
    Bad "SSH-aontifikatsiya ne udalas'. Smoyka: login='$VmUser' parol'-iz-parametra -VmPass."
    Bad "Eto PAROL OT UBUNTU (zadayotsya pri ustanovke OS), NE ot Windows."
    Bad "Esli somnevaeshsya - vojdite vruchnuyu: ssh $VmUser@127.0.0.1 -p $SshPort"
    Bad "ili smenity parol v konsoli VM: sudo passwd $VmUser"
    throw "Python-skript vernul kod 2 (SSH auth failed). Polnyj log: $LogFile i $TranscriptFile"
} elseif ($pyExit -ne 0) {
    throw "Udalyonnaya nastroyka zavershilas s oshibkoy (kod $pyExit). Sm. vyvod vyshe i logi: $LogFile, $TranscriptFile"
}

# ---------- 8. finalnaya proverka s Windows ----------
Info "==> Proverka s tvoey Windows:"
try {
    $r1 = Invoke-WebRequest "http://127.0.0.1:8000/api/hello/" -UseBasicParsing -TimeoutSec 15
    Ok "API OK: $($r1.Content)"
} catch { Bad "API poka ne otvechaet: $($_.Exception.Message)" }
try {
    $r2 = Invoke-WebRequest "http://127.0.0.1:8080/" -UseBasicParsing -TimeoutSec 15
    Ok "Frontend OK (HTTP $($r2.StatusCode))"
} catch { Bad "Frontend poka ne otvechaet: $($_.Exception.Message)" }

Write-Host ""
Info "=== GOTOVO ==="
Write-Host "  Frontend: http://127.0.0.1:8080"
Write-Host "  API:      http://127.0.0.1:8000/api/hello/"
Write-Host "  SSH v VM: ssh $VmUser@127.0.0.1 -p $SshPort  (parol: $VmPass)"
