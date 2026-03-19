# =========================================================================
# GPU Acceleration (CUDA)
# =========================================================================
# Enables GPU-accelerated particle kernels via CUDA C + Fortran ISO_C_BINDING.
# Requirements:
#   - NVIDIA GPU (Ampere or newer recommended; RTX 3060 = CC 8.6)
#   - CUDA Toolkit 12.x or newer installed from https://developer.nvidia.com/cuda-downloads
#   - Windows: nvcc must be on PATH or CUDA_PATH env var set
#
# Usage:
#   cmake --preset windows-ucrt64-gpu
#   cmake --preset windows-ucrt64-gpu -DCMAKE_CUDA_ARCHITECTURES=89  # RTX 4090
# =========================================================================

OPTION(PICLAS_USE_GPU
  "Enable GPU acceleration via CUDA (requires NVIDIA GPU + CUDA Toolkit)" OFF)

IF(PICLAS_USE_GPU)

  # -----------------------------------------------------------------------
  # Locate CUDA Toolkit
  # -----------------------------------------------------------------------
  FIND_PACKAGE(CUDAToolkit 11.0 REQUIRED)

  # -----------------------------------------------------------------------
  # On Windows: nvcc requires MSVC cl.exe (or Clang MSVC-mode) as host
  # compiler.  MinGW g++ is explicitly unsupported ("unsupported OS").
  # We locate cl.exe from VS Build Tools and set it as host compiler
  # BEFORE ENABLE_LANGUAGE(CUDA) so the compiler-ID test passes.
  #
  # If cl.exe is not found, a clear install hint is printed.
  # The extern "C" interface in piclas_gpu.h means MSVC-ABI CUDA objects
  # link without issues against the MinGW-compiled Fortran/C++ code.
  # -----------------------------------------------------------------------
  IF(WIN32 AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")

    # 1) Check if cl.exe is already on PATH (e.g. user ran vcvars64.bat)
    FIND_PROGRAM(_MSVC_CL cl NAMES cl.exe)

    # 2) If not on PATH, search known VS 2019/2022 Build Tools install paths
    IF(NOT _MSVC_CL)
      FILE(GLOB _cl_candidates
        "C:/Program Files/Microsoft Visual Studio/2022/*/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe"
        "C:/Program Files/Microsoft Visual Studio/2019/*/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe"
        "C:/Program Files (x86)/Microsoft Visual Studio/2022/*/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe"
        "C:/Program Files (x86)/Microsoft Visual Studio/2019/*/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe"
      )
      LIST(GET _cl_candidates 0 _MSVC_CL)
    ENDIF()

    IF(_MSVC_CL)
      SET(CMAKE_CUDA_HOST_COMPILER "${_MSVC_CL}" CACHE FILEPATH
        "CUDA host compiler (MSVC cl.exe — required by nvcc on Windows)" FORCE)
      MESSAGE(STATUS "  CUDA host   : ${_MSVC_CL}")

      # CMake's CUDA link test uses 'cmake -E vs_link_exe' (MSVC protocol) because
      # the host compiler is cl.exe.  That helper drives GNU ld with MSVC flags
      # (/nologo, /out:) and windres.exe with MSVC manifest args — both fail.
      # Since piclasGPU is a STATIC library we never need to link a CUDA executable;
      # pre-set the cache variables that would normally be written by the test so
      # CMake skips it and ENABLE_LANGUAGE(CUDA) succeeds.
      SET(CMAKE_CUDA_COMPILER_WORKS TRUE CACHE INTERNAL
        "CUDA compiler works (link test skipped — piclasGPU is a static lib)" FORCE)
      # ABI detection uses the same failing link step; pre-set to TRUE so CMake
      # treats ABI as "already determined" and skips the link test entirely.
      SET(CMAKE_CUDA_ABI_COMPILED TRUE CACHE INTERNAL
        "CUDA ABI detection skipped (vs_link_exe/windres incompatibility)" FORCE)
      MESSAGE(STATUS "  CUDA link test bypassed (static-library build only)")
    ELSE()
      MESSAGE(FATAL_ERROR
        "\nPICLAS_USE_GPU=ON on Windows requires Visual Studio Build Tools (cl.exe).\n"
        "nvcc does not support MinGW g++ as host compiler on Windows.\n\n"
        "Install 'Build Tools for Visual Studio 2022' (free, no IDE needed):\n"
        "  https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022\n"
        "  -> Select workload: 'Desktop development with C++'\n\n"
        "After install, re-run cmake. cl.exe will be found automatically.\n"
        "The GPU sources use extern \"C\" so MSVC objects link with MinGW correctly.\n")
    ENDIF()

  ENDIF()

  # -----------------------------------------------------------------------
  # Enable CUDA language for .cu compilation
  # -----------------------------------------------------------------------
  ENABLE_LANGUAGE(CUDA)

  # After ENABLE_LANGUAGE(CUDA), CMake sets CUDA_STATIC_LIBRARY_LINKER to an
  # MSVC-style rule: "ar.exe /nologo /out:TARGET OBJECTS".  MinGW ar does not
  # understand /nologo or /out: — replace with the GNU ar invocation.
  IF(WIN32 AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    SET(CMAKE_CUDA_CREATE_STATIC_LIBRARY
      "<CMAKE_AR> qc <TARGET> <LINK_FLAGS> <OBJECTS>"
      CACHE STRING "GNU ar rule for CUDA static library" FORCE)

    # ENABLE_LANGUAGE(CUDA) with cl.exe as host compiler probes the MSVC
    # toolchain and records all implicit Windows SDK libraries (kernel32,
    # ws2_32, m, ncrypt, bcrypt, cudadevrt, cudart, stdc++, …) into
    # CMAKE_CUDA_IMPLICIT_LINK_LIBRARIES as MSVC-style bare names.
    # MinGW's ld cannot resolve bare names (needs -l<name>).  The same
    # libraries are already added correctly by HDF5 / MPI CMake configs with
    # -l prefix.  Clear these variables so they are not appended a second time
    # (without -l) to every target that transitively depends on piclasGPU.
    # The cudart.dll dependency is handled explicitly via the full-path
    # cudart.lib in src/CMakeLists.txt instead.
    SET(CMAKE_CUDA_IMPLICIT_LINK_LIBRARIES   "" CACHE INTERNAL
      "Cleared: MinGW ld cannot use MSVC-style bare lib names from CUDA host detect")
    SET(CMAKE_CUDA_IMPLICIT_LINK_DIRECTORIES "" CACHE INTERNAL
      "Cleared: -LIBPATH: flags from CUDA host detect incompatible with MinGW ld")

    # Root cause of all bare-name link failures:
    # Platform/Windows-NVIDIA-CUDA.cmake includes Platform/Windows-MSVC.cmake
    # which sets CMAKE_LINK_LIBRARY_FLAG="" (empty — MSVC style) and
    # CMAKE_LIBRARY_PATH_FLAG="-LIBPATH:" globally.  This strips the -l prefix
    # from ALL subsequent Fortran/C link commands: bare names like "m","kernel32"
    # from HDF5/AWS CMake targets no longer get -l prefixed by CMake's generator.
    # Restore GNU linker flags so gfortran/ld receive -l<name> and -L<path>.
    SET(CMAKE_LINK_LIBRARY_FLAG "-l")
    SET(CMAKE_LIBRARY_PATH_FLAG "-L")
    # Also prevent CUDA linker preference from propagating to Fortran targets.
    SET(CMAKE_CUDA_LINKER_PREFERENCE_PROPAGATES 0)
  ENDIF()

  # -----------------------------------------------------------------------
  # GPU architecture — default = RTX 3060 (Ampere, CC 8.6)
  # Override via -DCMAKE_CUDA_ARCHITECTURES=89 for Ada (RTX 4090) etc.
  # -----------------------------------------------------------------------
  IF(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    SET(CMAKE_CUDA_ARCHITECTURES 86 CACHE STRING
      "CUDA architectures: 86=Ampere(RTX30xx) 89=Ada(RTX40xx) 90=Hopper(H100)")
  ENDIF()

  SET(CMAKE_CUDA_STANDARD 17)
  SET(CMAKE_CUDA_STANDARD_REQUIRED ON)

  # -----------------------------------------------------------------------
  # Preprocessor flag visible to both Fortran (via -D) and C/CUDA
  # -----------------------------------------------------------------------
  ADD_COMPILE_DEFINITIONS(PICLAS_USE_GPU=1)

  MESSAGE(STATUS "Compiling with [CUDA] GPU acceleration")
  MESSAGE(STATUS "  CUDA Toolkit : ${CUDAToolkit_VERSION}")
  MESSAGE(STATUS "  nvcc         : ${CUDAToolkit_NVCC_EXECUTABLE}")
  MESSAGE(STATUS "  Architectures: sm_${CMAKE_CUDA_ARCHITECTURES}")

ELSE()

  ADD_COMPILE_DEFINITIONS(PICLAS_USE_GPU=0)

ENDIF() # PICLAS_USE_GPU
