$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$reader = Join-Path $repo "src\fortran"
$readerBin = Join-Path $reader "bin"
$outDir = Join-Path $repo "src\himawari_hsd2nc\bin\windows-amd64"
$mingwCandidates = @()
if ($env:MINGW_BIN) { $mingwCandidates += $env:MINGW_BIN }
$mingwCandidates += @(
    "D:\Scoop\apps\msys2\current\mingw64\bin",
    "C:\msys64\mingw64\bin",
    "C:\tools\msys64\mingw64\bin"
)
$mingwBin = $null
foreach ($c in $mingwCandidates) {
    if (Test-Path $c) { $mingwBin = $c; break }
}
$objdump = Join-Path $mingwBin "objdump.exe"

if (-not $mingwBin) {
    throw "mingw64 bin not found. Set env MINGW_BIN or install MSYS2 mingw64."
}
if (!(Test-Path $reader)) {
    throw "Reader source not found: $reader"
}

$env:PATH = "$mingwBin;$env:PATH"
$mingwRoot = Split-Path -Parent $mingwBin
$makeLibDir = ($mingwRoot -replace '\\','/')
$incDirs = New-Object System.Collections.Generic.List[string]
$incDirs.Add("$makeLibDir/include") | Out-Null
$incDirs.Add("$makeLibDir/lib/gfortran/modules") | Out-Null
$incDirs.Add("$makeLibDir/lib") | Out-Null
$netcdfMod = Get-ChildItem -Path $mingwRoot -Filter "netcdf.mod" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($netcdfMod) {
    $incDirs.Add(((Split-Path -Parent $netcdfMod.FullName) -replace '\\','/')) | Out-Null
}
$uniqInc = $incDirs | Select-Object -Unique
$netcdfFflags = (($uniqInc | ForEach-Object { "-I$_" }) -join " ")
$makeArgs = @(
    "LIBDIR=$makeLibDir",
    "NETCDF_FFLAGS=$netcdfFflags",
    "NETCDF_FLIBS=-L$makeLibDir/lib -lnetcdff -lnetcdf"
)
Write-Host "Using NETCDF_FFLAGS=$netcdfFflags"

Write-Host "[1/4] Build AHI binaries..."
Push-Location $reader
try {
    & mingw32-make @makeArgs clean
    if ($LASTEXITCODE -ne 0) { throw "mingw32-make clean failed with code $LASTEXITCODE" }
    & mingw32-make @makeArgs AHI AHI_FAST AHI_FAST_ROI
    if ($LASTEXITCODE -ne 0) { throw "mingw32-make build failed with code $LASTEXITCODE" }
} finally {
    Pop-Location
}

Write-Host "[2/4] Reset output directory..."
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Get-ChildItem $outDir -File | Remove-Item -Force

$exes = @("AHI.exe", "AHI_FAST.exe", "AHI_FAST_ROI.exe")
foreach ($e in $exes) {
    Copy-Item (Join-Path $readerBin $e) $outDir -Force
}

Write-Host "[3/4] Collect dependent DLLs..."
function Get-DllDeps([string]$filePath) {
    $lines = & $objdump -p $filePath | Select-String 'DLL Name:'
    $dlls = @()
    foreach ($l in $lines) {
        $name = ($l.ToString().Split(':')[-1]).Trim()
        if ($name -match '^[A-Za-z].*\.dll$' -and $name -notmatch '^(KERNEL32|msvcrt|ADVAPI32|SHELL32|USER32|WS2_32|IPHLPAPI|CRYPT32|OLE32|GDI32|COMDLG32|SHLWAPI|WINMM|VERSION|RPCRT4)\.dll$') {
            $dlls += $name
        }
    }
    return $dlls | Select-Object -Unique
}

$queue = New-Object 'System.Collections.Generic.Queue[string]'
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($e in $exes) {
    $rootExe = Join-Path $outDir $e
    foreach ($d in Get-DllDeps $rootExe) {
        if ($seen.Add($d)) { $queue.Enqueue($d) }
    }
}

while ($queue.Count -gt 0) {
    $d = $queue.Dequeue()
    $src = Join-Path $mingwBin $d
    if (Test-Path $src) {
        Copy-Item $src $outDir -Force
        foreach ($sub in Get-DllDeps $src) {
            if ($seen.Add($sub)) { $queue.Enqueue($sub) }
        }
    }
}

Write-Host "[4/4] Done. Output files:"
Get-ChildItem $outDir | Select-Object Name, Length | Sort-Object Name

$hardenScript = Join-Path $repo "scripts\harden_windows_runtime.ps1"
Write-Host "[post] Hardening runtime directory..."
powershell -ExecutionPolicy Bypass -File $hardenScript -RuntimeDir $outDir
