#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bundle_dlls.sh — assemble a self-contained Windows distribution folder.
#
# Copies a MSYS2/UCRT64-built binary together with its full UCRT64 runtime DLL
# dependency closure (libgfortran, libopenblas, libhdf5_fortran, libquadmath,
# libwinpthread, ...), its sibling build DLLs (libpiclas*.dll), the CUDA
# runtime (cudart64_*.dll) and the redistributable MS-MPI runtime (msmpi.dll),
# so the result runs on a clean Windows box without an MSYS2 install on PATH.
#
# Run from the MSYS2 UCRT64 shell.
#   Usage: bundle_dlls.sh <path-to-exe> <output-dir>
# ---------------------------------------------------------------------------
set -euo pipefail

exe="${1:?usage: bundle_dlls.sh <exe> <output-dir>}"
out="${2:?usage: bundle_dlls.sh <exe> <output-dir>}"
bindir="$(dirname "$exe")"

mkdir -p "$out"
cp -f "$exe" "$out"/

# Sibling DLLs loaded dynamically (LoadLibrary) and therefore invisible to ldd
# on the exe itself: the piclas shared libs and the CUDA runtime.
shopt -s nullglob
for d in "$bindir"/libpiclas*.dll "$bindir"/cudart64_*.dll; do
  cp -f "$d" "$out"/
done
shopt -u nullglob

# Copy every non-system DLL from a binary's ldd closure into $out.
# Keep UCRT64/MinGW DLLs and the redistributable msmpi.dll; skip Windows
# system DLLs (KERNEL32, api-ms-win-*, etc. — present on every Windows box).
collect() {
  ldd "$1" 2>/dev/null | awk '{print $3}' | while read -r dep; do
    [ -n "$dep" ] && [ -e "$dep" ] || continue
    case "$dep" in
      */ucrt64/*|*/mingw64/*|*/mingw32/*) cp -n "$dep" "$out"/ 2>/dev/null || true ;;
      *[Mm][Ss][Mm][Pp][Ii]*)             cp -n "$dep" "$out"/ 2>/dev/null || true ;;
    esac
  done
}

# ldd resolves the recursive static-import closure; run it on the exe and on
# every copied DLL (incl. the dynamically-loaded ones) and repeat once so
# deps-of-deps that were only just copied in are themselves resolved.
collect "$exe"
for d in "$out"/*.dll; do collect "$d"; done
for d in "$out"/*.dll; do collect "$d"; done

# Explicitly add the redistributable MS-MPI runtime (msmpi.dll). The binary imports
# it, but it lives in C:\Windows\System32 (installed via msmpisetup on the runner),
# which the ldd closure above does not reliably resolve. Bundling it makes the zip
# run SINGLE-PROCESS on a machine with NO MS-MPI installed. (Multi-rank mpiexec
# still needs the full MS-MPI runtime — that part is not a redistributable DLL.)
if [ ! -f "$out/msmpi.dll" ]; then
  for sys in /c/Windows/System32/msmpi.dll "$(cygpath -u "$SYSTEMROOT" 2>/dev/null)/System32/msmpi.dll"; do
    if [ -f "$sys" ]; then cp -f "$sys" "$out"/ && echo "  + MS-MPI runtime bundled: $sys"; break; fi
  done
  [ -f "$out/msmpi.dll" ] || echo "  WARNING: msmpi.dll not found in System32 — bundle will need an MS-MPI install to run"
fi

echo "== bundle: $out =="
ls -1 "$out"
echo "== $(ls -1 "$out" | wc -l) files total =="
