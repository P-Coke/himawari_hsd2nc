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

if (-not $mingwBin) {
    throw "mingw64 bin not found. Set env MINGW_BIN or install MSYS2 mingw64."
}
if (!(Test-Path $reader)) {
    throw "Reader source not found: $reader"
}

$env:PATH = "$mingwBin;$env:PATH"
$mingwRoot = Split-Path -Parent $mingwBin
$toolchainRoot = $mingwRoot
$incDirs = New-Object System.Collections.Generic.List[string]
$candidateInc = @(
    "$mingwRoot/include",
    "$mingwRoot/lib/gfortran/modules",
    "$mingwRoot/lib"
)
foreach ($d in $candidateInc) {
    if (Test-Path $d) { $incDirs.Add(($d -replace '\\','/')) | Out-Null }
}

function Find-NetcdfMod {
    param([string[]]$Roots)
    foreach ($r in $Roots) {
        if (Test-Path $r) {
            $m = Get-ChildItem -Path $r -Filter "netcdf.mod" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($m) { return $m }
        }
    }
    return $null
}

$searchRoots = @($mingwRoot, "C:\msys64\mingw64", "D:\a\_temp\msys64\mingw64", "C:\mingw64", "C:\msys64", "D:\a\_temp\msys64")
$netcdfMod = Find-NetcdfMod -Roots $searchRoots
if (-not $netcdfMod) {
    $bashExe = Join-Path (Split-Path -Parent $mingwRoot) "usr\bin\bash.exe"
    if (Test-Path $bashExe) {
        Write-Host "netcdf.mod missing, installing netcdf packages via MSYS2..."
        & $bashExe -lc "pacman -S --noconfirm --needed mingw-w64-x86_64-netcdf mingw-w64-x86_64-netcdf-fortran"
        $netcdfMod = Find-NetcdfMod -Roots $searchRoots
    }
}
if ($netcdfMod) {
    $modDir = Split-Path -Parent $netcdfMod.FullName
    $incDirs.Add(($modDir -replace '\\','/')) | Out-Null
    $modParent = Split-Path -Parent $modDir
    if ((Split-Path -Leaf $modParent).ToLower() -eq "mingw64") {
        $toolchainRoot = $modParent
    }
} else {
    Write-Warning "netcdf.mod not found; build may fail. Checked: $($searchRoots -join ', ')"
}
$makeLibDir = ($toolchainRoot -replace '\\','/')
$libDir = "$toolchainRoot\lib"
if (-not (Test-Path "$toolchainRoot\bin")) {
    $toolchainRoot = $mingwRoot
    $makeLibDir = ($toolchainRoot -replace '\\','/')
    $libDir = "$toolchainRoot\lib"
}
if (Test-Path "$toolchainRoot\bin") {
    $env:PATH = "$toolchainRoot\bin;$env:PATH"
}
if (-not (Test-Path $libDir)) {
    $libDir = "$mingwRoot\lib"
}
$makeLinkDir = ($libDir -replace '\\','/')
$objdump = Join-Path $toolchainRoot "bin\objdump.exe"
if (-not (Test-Path $objdump)) {
    $objdumpCmd = Get-Command objdump.exe -ErrorAction SilentlyContinue
    if ($objdumpCmd) {
        $objdump = $objdumpCmd.Source
    } else {
        throw "objdump.exe not found under $toolchainRoot\bin and not available in PATH."
    }
}
$uniqInc = $incDirs | Select-Object -Unique
$netcdfFflags = (($uniqInc | ForEach-Object { "-I$_" }) -join " ")
$makeArgs = @(
    "LIBDIR=$makeLibDir",
    "NETCDF_FFLAGS=$netcdfFflags",
    "NETCDF_FLIBS=-L$makeLinkDir -lnetcdff -lnetcdf",
    "HDF5_LIBS=-L$makeLinkDir -lhdf5 -lhdf5_fortran -lhdf5_hl_fortran"
)
Write-Host "Using toolchain root: $toolchainRoot"
Write-Host "Using NETCDF_FFLAGS=$netcdfFflags"
Write-Host "Using link dir: $makeLinkDir"
Write-Host "Using objdump: $objdump"

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
