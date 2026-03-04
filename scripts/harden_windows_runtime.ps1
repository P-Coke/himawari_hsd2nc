param(
    [string]$RuntimeDir = "src\himawari_hsd2nc\bin\windows-amd64",
    [string]$ObjdumpPath = "D:\Scoop\apps\msys2\current\mingw64\bin\objdump.exe"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $RuntimeDir)) {
    throw "RuntimeDir not found: $RuntimeDir"
}
if (!(Test-Path $ObjdumpPath)) {
    throw "objdump not found: $ObjdumpPath"
}

$RuntimeDir = (Resolve-Path $RuntimeDir).Path

$rootExes = @("AHI.exe", "AHI_FAST.exe", "AHI_FAST_ROI.exe")
$systemDlls = @(
    "KERNEL32.dll", "msvcrt.dll", "ADVAPI32.dll", "SHELL32.dll", "USER32.dll",
    "WS2_32.dll", "IPHLPAPI.dll", "CRYPT32.dll", "OLE32.dll", "GDI32.dll",
    "COMDLG32.dll", "SHLWAPI.dll", "WINMM.dll", "VERSION.dll", "RPCRT4.dll",
    "ntdll.dll", "bcrypt.dll", "secur32.dll", "wldap32.dll", "normaliz.dll",
    "ncrypt.dll", "PSAPI.dll", "USERENV.dll", "WINHTTP.dll", "WININET.dll"
)
$systemSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($d in $systemDlls) { [void]$systemSet.Add($d) }

function Get-NeededDlls([string]$filePath, [string]$objdump) {
    $lines = & $objdump -p $filePath | Select-String "DLL Name:"
    $dlls = @()
    foreach ($l in $lines) {
        $name = ($l.ToString().Split(":")[-1]).Trim()
        if ($name -match "^[A-Za-z].*\.dll$") {
            $dlls += $name
        }
    }
    return $dlls | Select-Object -Unique
}

$missing = New-Object System.Collections.Generic.List[string]
$reachableDlls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$queue = New-Object System.Collections.Generic.Queue[string]
$visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($exe in $rootExes) {
    $p = Join-Path $RuntimeDir $exe
    if (!(Test-Path $p)) {
        throw "Missing root executable: $p"
    }
    $queue.Enqueue($p)
}

while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    if (!$visited.Add($cur)) { continue }

    $deps = Get-NeededDlls -filePath $cur -objdump $ObjdumpPath
    foreach ($dep in $deps) {
        if ($systemSet.Contains($dep)) { continue }
        $depPath = Join-Path $RuntimeDir $dep
        if (!(Test-Path $depPath)) {
            $missing.Add("$([System.IO.Path]::GetFileName($cur)) -> $dep")
            continue
        }
        if ($reachableDlls.Add($dep)) {
            $queue.Enqueue($depPath)
        }
    }
}

if ($missing.Count -gt 0) {
    $msg = ($missing | Sort-Object | Get-Unique) -join "`n"
    throw "Runtime dependency check failed. Missing DLL(s):`n$msg"
}

# Prune orphan DLLs that are not reachable from the root executables.
$allDlls = Get-ChildItem $RuntimeDir -File -Filter *.dll
$removed = @()
foreach ($dll in $allDlls) {
    if (!$reachableDlls.Contains($dll.Name)) {
        Remove-Item $dll.FullName -Force
        $removed += $dll.Name
    }
}

# Basic smoke tests: each executable should start and exit quickly with no input.
function Invoke-SmokeTest([string]$exePath, [int]$timeoutSec = 15) {
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $exePath -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if (!$p.WaitForExit($timeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            throw "Smoke test timeout: $exePath"
        }
        $stdout = Get-Content $outFile -Raw
        $stderr = Get-Content $errFile -Raw
        $text = "$stdout`n$stderr"
        if ($text -notmatch "(usage|channel|input|No channels requested|Incorrect channel)") {
            Write-Warning "Smoke test output did not contain expected usage hints: $exePath"
        }
    } finally {
        Remove-Item $outFile -ErrorAction SilentlyContinue
        Remove-Item $errFile -ErrorAction SilentlyContinue
    }
}

foreach ($exe in $rootExes) {
    Invoke-SmokeTest (Join-Path $RuntimeDir $exe)
}

# Generate runtime manifest (sha256 + size).
$manifestItems = @()
$files = Get-ChildItem $RuntimeDir -File | Sort-Object Name
foreach ($f in $files) {
    $hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestItems += [PSCustomObject]@{
        file = $f.Name
        size = $f.Length
        sha256 = $hash
    }
}
$manifest = [PSCustomObject]@{
    platform = "windows-amd64"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    file_count = $manifestItems.Count
    files = $manifestItems
}
$manifestPath = Join-Path $RuntimeDir "runtime-manifest.json"
$manifest | ConvertTo-Json -Depth 6 | Out-File -FilePath $manifestPath -Encoding utf8

Write-Host "[harden] Runtime directory verified: $RuntimeDir"
Write-Host "[harden] Reachable DLL count: $($reachableDlls.Count)"
Write-Host "[harden] Removed orphan DLLs: $($removed.Count)"
Write-Host "[harden] Manifest: $manifestPath"
