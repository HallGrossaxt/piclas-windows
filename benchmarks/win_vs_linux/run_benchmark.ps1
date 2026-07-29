# =====================================================================================================================
#  PICLas Windows-vs-Linux benchmark driver  (Windows / MS-MPI side)
#  Mirror of run_benchmark.sh -- keep the two in lockstep.
#
#  Drives reggie against PREBUILT release binaries (-e) so we time the exact
#  shipped .exe, never a fresh compile. Rank sweep + GAMG sweep come from the
#  case .ini files (command_line.ini: MPI=1,2,4,6 ; parameter.ini: PrecondType=2,4).
#
#  Usage:   pwsh -File run_benchmark.ps1
#  Output:  logs\pic.log, logs\dsmc.log  ->  results\win_timings.csv
# =====================================================================================================================
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

# --- knobs (edit to match your tree) -------------------------------------------------------------------------------
$PICLAS_ROOT = 'C:\Data\PRJ\piclas-win\piclas-win-master'
$REGGIE      = 'C:\Data\PRJ\reggie2.0-venv\bin\reggie.exe'
$PYTHON      = 'C:\Data\PRJ\reggie2.0-venv\bin\python.exe'
$MPIEXE      = 'mpiexec'                       # MS-MPI launcher (reggie uses '-n <ranks>')

# PIC (HDG-Poisson): the GAMG-capable PETSc build (poisson + Boris-Leapfrog + LIBS_USE_PETSC=ON).
$PIC_BIN     = "$PICLAS_ROOT\build-poisson-boris-petsc-mpi\bin\piclas-win.exe"
# DSMC: maxwell + TIMEDISC=DSMC, PETSc OFF.
$DSMC_BIN    = "$PICLAS_ROOT\build-maxwell-dsmc-release-mpi\bin\piclas-win.exe"

# --- setup ---------------------------------------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path "$here\logs","$here\results" | Out-Null

function Invoke-Case {
    param([string]$Label, [string]$CaseDir, [string]$Exe)
    Write-Host "==== $Label :: $Exe ====" -ForegroundColor Cyan
    if (-not (Test-Path $Exe)) { throw "binary not found: $Exe" }
    # Windows resolves libpiclas.dll from the .exe's own directory; prepend it (and MS-MPI is on PATH already).
    $env:PATH = (Split-Path -Parent $Exe) + ';' + $env:PATH
    # reggie -e sets run-mode (no compile) and writes each run's full stdout to std.out in its run dir.
    # Give each case its own output tree so the two cases never clobber each other.
    Remove-Item "$here\output_dir","$here\results\run_$Label" -Recurse -Force -ErrorAction SilentlyContinue
    & $REGGIE $CaseDir -e $Exe -m $MPIEXE -s 2>&1 | Tee-Object -FilePath "$here\logs\$Label.log"
    Write-Host "reggie exit: $LASTEXITCODE (analyze is disabled; non-zero only means a run crashed)" -ForegroundColor Yellow
    if (Test-Path "$here\output_dir") { Move-Item "$here\output_dir" "$here\results\run_$Label" -Force }
}

Invoke-Case -Label 'pic'  -CaseDir "$here\pic_hempt_hdg"   -Exe $PIC_BIN
Invoke-Case -Label 'dsmc' -CaseDir "$here\dsmc_periodic3d" -Exe $DSMC_BIN

# --- collect ------------------------------------------------------------------------------------------------------
& $PYTHON "$here\parse_timings.py" --os win --out "$here\results\win_timings.csv" `
    --case "pic=$here\results\run_pic" --case "dsmc=$here\results\run_dsmc"
Write-Host "`nDone. See results\win_timings.csv" -ForegroundColor Green
