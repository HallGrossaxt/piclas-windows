# piclas-win example: DSMC 70° Cone (2D axisymmetric)

A ready-to-run DSMC example for **piclas-win** (unofficial Windows port of PICLas).
Hypersonic rarefied N₂ flow over a 70° blunted cone — the classic Allègre (1997)
wind-tunnel case used to validate surface heat flux.

This example is **self-contained**: the mesh is already converted to HDF5, so you only
need `piclas-win.exe`. No HOPR, no MSYS2, no CUDA Toolkit required.

Verified end-to-end against the **piclas-win v1.1** release binary.

## Contents

| File | Purpose |
|------|---------|
| `parameter.ini` | Main simulation configuration |
| `DSMC.ini` | N₂ species data (VHS collision model) |
| `70degCone_2D_mesh.h5` | Mesh, **pre-converted** (CGNS route, 5 boundaries, 487 elements) |
| `reference/` | Source geometry + `hopr_cgns.ini` showing how the mesh was generated (needs HOPR — only if you want to rebuild it) |

## How to run

1. Download and unzip `piclas-win-v1.1-win64.zip` from the release.
2. Put `piclas-win.exe` (and its DLLs) on your `PATH`, or copy this example's files next
   to the executable.
3. From this folder, run:

   ```
   piclas-win.exe parameter.ini DSMC.ini
   ```

   To run on multiple cores (requires the Microsoft MPI runtime, `msmpisetup.exe`):

   ```
   mpiexec -n 4 piclas-win.exe parameter.ini DSMC.ini
   ```

   > The single-process command works as-is. The `DoLoadBalance` / `DoInitialAutoRestart`
   > options in `parameter.ini` only take effect under `mpiexec` and are harmlessly
   > ignored otherwise.

**Expected runtime:** ~30 min single-process on a modern desktop core
(10,000 timesteps, ~300k simulation particles at steady state).

> **Note (GPU build):** the v1.1 `piclas-win.exe` is a GPU-enabled build and needs an
> NVIDIA driver present. This case is axisymmetric and uses a surface flux, so the GPU
> particle push is automatically disabled and the run executes on the CPU.

## Output

Files are written every `Analyze_dt` (2.5×10⁻⁴ s), through to the final time
`...002000000` (2 ms):

- `dsmc_cone_State_*.h5` — flowfield (velocity, temperature, density)
- `dsmc_cone_DSMCState_*.h5` — DSMC macroscopic values
- `dsmc_cone_DSMCSurfState_*.h5` — **surface values, incl. wall heat flux** (the
  quantity compared against the Allègre 1997 experiment)

A clean run produces **no `*_ERRORS.out`** file and ends with the banner
`PICLAS FINISHED!`.

## Post-processing (optional)

Convert results to ParaView-readable VTK using the `piclas2vtk` tool from the release:

```
piclas2vtk dsmc_cone_DSMCSurfState_000.002000000.h5
piclas2vtk dsmc_cone_State_000.002000000.h5
```

## Rebuilding the mesh (optional)

The shipped `70degCone_2D_mesh.h5` was generated from `reference/70degCone_2D_mesh.cgns`
with HOPR:

```
hopr reference/hopr_cgns.ini
```

This produces the CGNS variant with **5 boundaries** (`IN`, `OUT`, `WALL`, `SYMAXIS`,
`ROTSYM`), which is what `parameter.ini` expects. (A Gmsh route exists in the full
tutorial but yields 6 boundaries and is **not** compatible with this `parameter.ini`
out of the box.)

---

Part of the PICLas tutorials (https://piclas.readthedocs.io). piclas-win is an
unofficial Windows port; license GPLv3 (see the main repository).
