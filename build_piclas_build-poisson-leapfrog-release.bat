@echo off
title PICLas Build: build-poisson-leapfrog-release
set BASH=C:\msys64\usr\bin\bash.exe
if not exist "%BASH%" (
  echo ERROR: MSYS2 bash not found at %BASH%
  pause & exit /b 1
)
echo.
echo  PICLas Build Configurator
echo  Config: build-poisson-leapfrog-release
echo.
echo ======================================
echo  CONFIGURE
echo ======================================
"%BASH%" -c "cd 'C:/Data/PRJ/Piclas/piclas-master' && cmake --preset windows-ucrt64 -B 'C:/Data/PRJ/Piclas/build-poisson-leapfrog-release' -DPICLAS_EQNSYSNAME=poisson -DPICLAS_TIMEDISCMETHOD=Leapfrog -DCMAKE_BUILD_TYPE=Release -DPICLAS_BUILD_POSTI=ON -DPICLAS_UNITTESTS=OFF -DLIBS_USE_MPI=OFF -DPICLAS_READIN_CONSTANTS=ON -DPICLAS_PERFORMANCE=ON -DPICLAS_CODE_ANALYZE=OFF '-DPICLAS_INSTRUCTION=-march=x86-64-v2 -mtune=generic'"
if %ERRORLEVEL% neq 0 (
  echo.
  echo CONFIGURE FAILED
  pause & exit /b 1
)
echo.
echo ======================================
echo  BUILD  ^(target: piclas piclas2vtk^)
echo ======================================
"%BASH%" -c "export TEMP=/tmp && export TMP=/tmp && cmake --build 'C:/Data/PRJ/Piclas/build-poisson-leapfrog-release' --target piclas piclas2vtk"
if %ERRORLEVEL% neq 0 (
  echo.
  echo BUILD FAILED
  pause & exit /b 1
)
echo.
echo BUILD SUCCEEDED
echo Binary in: C:\Data\PRJ\Piclas\build-poisson-leapfrog-release
pause
