# finish-setup.ps1 - dovodka UZhE ustanovlennoy Ubuntu Server v VirtualBox.
# Ne peresozdayot VM i ne trogaet eyo disk. Delaet: NAT-porty -> SSH -> Docker -> proekt -> docker compose up.
# Trebovaniya: VirtualBox (VBoxManage), Python s paramiko (pip install --user paramiko).
# Zapusk:  .\scripts\finish-setup.ps1 -VmPass "parol_ot_ubuntu"
# Esli Ubuntu stavilas vruchnuyu i login ne stud - ukazhite -VmUser "imya".

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
if ($vmlist -notmatch [regex]::Escape("`"$VmName`"")) {
    throw "VM '$VmName' ne naydena. Spisok vashih VM:`n$vmlist`nUkazhite pravilnoe imya cherez -VmName (imya iz spiska above)."
}
Ok "VM naydena."

# status
$status = (& $VBM showvminfo $VmName --machinereadable | Select-String '^VMState="(.+)"').Matches[0].Groups[1].Value
Bad "Sostoyanie VM: $status"

# ---------- 2. NAT-porty ----------
Info "==> Nastraivayu probros portov NAT (ssh $SshPort->22, frontend 8080->80, backend 8000->8000)..."
# pravila mozhno menyat na letu cherez controlvm (dlya zapuschennoy VM)
foreach ($rule in @(
    "ssh,tcp,,${SshPort},,22",
    "frontend,tcp,,8080,,80",
    "backend,tcp,,8000,,8000")) {
    $name = $rule.Split(',')[0]
    & $VBM controlvm $VmName natpf1 delete $name 2>$null | Out-Null
    & $VBM controlvm $VmName natpf1 "$rule" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # esli VM vyklyuchena  cherez modifyvm
        & $VBM modifyvm $VmName --natpf1 delete $name 2>$null | Out-Null
        & $VBM modifyvm $VmName --natpf1 "$rule" 2>$null | Out-Null
    }
}
Ok "Porty nastroeny."

# ---------- 3. zapusk VM esli vyklyuchena ----------
if ($status -ne "running") {
    Info "==> Zapuskayu VM (headless)..."
    Start-Process -FilePath $VBM -ArgumentList @("startvm", $VmName, "--type", "headless") -WindowStyle Hidden
    Start-Sleep -Seconds 15
}

# ---------- 4. zhdyom SSH-banner ----------
Info "==> Zhdu SSH-banner na 127.0.0.1:${SshPort} (do 3 min)..."
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
    Write-Host "    ...zhdu..."
}
if (-not $banner) {
    throw "SSH-banner ne poluchen. Varianty: 1) V Ubuntu net OpenSSH server - zaydite v okno VM i vypolnite: sudo apt update ; sudo apt install -y openssh-server ; sudo systemctl enable --now ssh. 2) Neverny login/port - proverte -VmUser/-SshPort. 3) Set' adaptera dolzhen byt NAT."

}
Ok "SSH zhivoy!"

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
$pyFile = Join-Path $PSScriptRoot "dz_finish.py"
if (-not (Test-Path $pyFile)) { throw "Ne nayden $pyFile (ryadom s finish-setup.ps1)." }

& $PY $pyFile "127.0.0.1" $SshPort $VmUser $VmPass $root.FullName
if ($LASTEXITCODE -ne 0) { throw "Udalyonnaya nastroyka zavershilas s oshibkoy (sm. vyvod vyshe)." }

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
