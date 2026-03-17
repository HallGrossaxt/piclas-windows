#************************************************************************************
#
# Description:  Windows PowerShell equivalent of generateuserblock.sh
#               Generates a userblock.txt file with build metadata (git info,
#               CMake configuration, compiler info) and compiles a stub userblock.o
#               object file providing the required userblock_start/end/size symbols.
#
# Usage: powershell -File generateuserblock.ps1 <BinDir> <BuildDir> <CMakeVer> <F90File> <CC>
#   $1 BinDir   : CMAKE_RUNTIME_OUTPUT_DIRECTORY
#   $2 BuildDir : CMAKE_CURRENT_BINARY_DIR
#   $3 CMakeVer : CMAKE_VERSION
#   $4 F90File  : path to globals_vars.f90 (for PICLas version extraction)
#   $5 CC       : C compiler executable (to compile the stub)
#
#************************************************************************************
param(
    [string]$BinDir,
    [string]$BuildDir,
    [string]$CMakeVersion,
    [string]$F90File,
    [string]$CC = "gcc"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Validate required directories
if (-not (Test-Path $BinDir -PathType Container)) {
    Write-Error "BinDir does not exist: $BinDir"
    exit 1
}
if (-not (Test-Path $BuildDir -PathType Container)) {
    Write-Error "BuildDir does not exist: $BuildDir"
    exit 1
}

$UserblockTxt = Join-Path $BinDir "userblock.txt"

# =========================================================================
# Gather git information
# =========================================================================
$BranchName   = "not a git repo"
$GitCommit    = "not a git repo"
$ParentName   = "not a git repo"
$ParentCommit = "not a git repo"
$GitUrl       = "not a git repo"

# Check if inside a git repo
$insideGit = $null
try {
    $insideGit = & git rev-parse --is-inside-work-tree 2>$null
} catch { }

if ($insideGit -eq "true") {
    try { $GitCommit  = (& git rev-parse HEAD 2>$null).Trim() }         catch { }
    try { $BranchName = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim() } catch { }
    try { $GitUrl     = (& git config --get remote.origin.url 2>$null).Trim() } catch { }
    $ParentName   = $BranchName
    try { $ParentCommit = (& git rev-parse "$($GitCommit)^" 2>$null).Trim() } catch { $ParentCommit = "" }
}

# =========================================================================
# Write userblock.txt
# =========================================================================
$content = @()
$content += "{[( CMAKE )]}"

# Append configuration.cmake if it exists
$configFile = Join-Path $BinDir "configuration.cmake"
if (Test-Path $configFile) {
    $content += Get-Content $configFile
}

$content += "{[( GIT BRANCH )]}"
$content += $BranchName
$content += $GitCommit

$content += "{[( GIT REFERENCE )]}"
$content += $ParentName
$content += $ParentCommit

$content += "{[( GIT DIFF )]}"
if ($insideGit -eq "true") {
    try {
        if ($ParentCommit -ne "") {
            $diff = & git diff -p "$ParentCommit..HEAD" 2>$null | Select-Object -First 1000
            $content += $diff
        }
        # Uncommitted changes
        $uncommitted = & git diff -p HEAD 2>$null | Select-Object -First 1000
        $content += $uncommitted
    } catch { }
} else {
    $content += "not a git repo"
}

$content += "{[( GIT URL )]}"
$content += $GitUrl

# Append compile flags if available
$cmakeFilesDir = Join-Path $BuildDir "CMakeFiles"
if (Test-Path $cmakeFilesDir -PathType Container) {
    $flagFiles = @("libpiclasstatic.dir/flags.make", "libpiclasshared.dir/flags.make", "piclas.dir/flags.make")
    foreach ($ff in $flagFiles) {
        $ffPath = Join-Path $cmakeFilesDir $ff
        if (Test-Path $ffPath) {
            $content += "{[( $ff )]}"
            $content += Get-Content $ffPath
        }
    }
}

# Append PICLas version from the F90 file
if (Test-Path $F90File) {
    $f90Content = Get-Content $F90File -Raw
    $major = [regex]::Match($f90Content, 'INTEGER.*PARAMETER.*MajorVersion.*=\s*(\d+)').Groups[1].Value
    $minor = [regex]::Match($f90Content, 'INTEGER.*PARAMETER.*MinorVersion.*=\s*(\d+)').Groups[1].Value
    $patch = [regex]::Match($f90Content, 'INTEGER.*PARAMETER.*PatchVersion.*=\s*(\d+)').Groups[1].Value
    if ($major -ne "" -and $minor -ne "" -and $patch -ne "") {
        $content += "{[( PICLAS VERSION )]}"
        $content += "$major.$minor.$patch"
    }
}

# Append Windows CPU info
$content += "{[( CPU INFO )]}"
try {
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $content += "CPU: $($cpuInfo.Name)"
    $content += "Physical cores: $($cpuInfo.NumberOfCores)"
    $content += "Logical processors: $($cpuInfo.NumberOfLogicalProcessors)"
    $content += "Architecture: $($cpuInfo.Architecture)"
} catch {
    $content += "CPU info not available"
}

# Write the userblock.txt file
$content | Set-Content -Path $UserblockTxt -Encoding UTF8
Write-Host "Generated: $UserblockTxt"

# =========================================================================
# Create userblock_stub.c and compile to userblock.o
# This provides the required userblock_start / userblock_end / userblock_size
# symbols. On Linux these come from objcopy embedding the compressed archive;
# on Windows we use a minimal C stub so the linker is satisfied.
# =========================================================================
$stubC   = Join-Path $BinDir "userblock_stub.c"
$stubObj = Join-Path $BinDir "userblock.o"

$stubCode = @"
/*
 * userblock_stub.c - Windows fallback for the userblock object file.
 * Provides the symbols that the PICLas linker expects.
 * On Linux, userblock.o is created by objcopy from the compressed userblock
 * archive. On Windows we supply empty/stub symbols instead.
 */
#include <stddef.h>

static const char piclas_userblock_data[] = "PICLAS_USERBLOCK_WINDOWS_STUB";

const char*  userblock_start = piclas_userblock_data;
const char*  userblock_end   = piclas_userblock_data + sizeof(piclas_userblock_data);
const size_t userblock_size  = sizeof(piclas_userblock_data);
"@

$stubCode | Set-Content -Path $stubC -Encoding ASCII

# Compile the stub with the C compiler
$ccExe = $CC
if (-not $ccExe -or $ccExe -eq "") { $ccExe = "gcc" }

Write-Host "Compiling userblock stub: $ccExe -c $stubC -o $stubObj"
try {
    $proc = Start-Process -FilePath $ccExe -ArgumentList "-c `"$stubC`" -o `"$stubObj`"" `
                          -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Warning "Failed to compile userblock stub (exit code $($proc.ExitCode)). Trying fallback compilers..."
        # Try common MinGW/MSYS2 compilers
        foreach ($fallback in @("x86_64-w64-mingw32-gcc", "cl")) {
            try {
                $proc2 = Start-Process -FilePath $fallback -ArgumentList "-c `"$stubC`" -o `"$stubObj`"" `
                                       -NoNewWindow -Wait -PassThru
                if ($proc2.ExitCode -eq 0) {
                    Write-Host "Compiled userblock stub with: $fallback"
                    break
                }
            } catch { }
        }
    } else {
        Write-Host "Generated: $stubObj"
    }
} catch {
    Write-Warning "Could not compile userblock stub: $_"
    Write-Warning "The build may fail at the linking stage if userblock.o is missing."
}
