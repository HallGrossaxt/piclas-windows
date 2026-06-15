# =========================================================================
# PICLas information
# =========================================================================
SET(PROJECT_NAME "PICLas")
SET(PROJECT_DESC "A parallel, three-dimensional PIC-DSMC solver and flexible particle-based plasma simulation suite")
SET(PROJECT_VER  "4.1.0")
SET(PROJECT_URL  "https://github.com/piclas-framework/piclas")

# =========================================================================
# CMake configuration
# =========================================================================
CMAKE_MINIMUM_REQUIRED(VERSION 3.10.0)

MESSAGE(STATUS "This is ${PROJECT_NAME} (v${PROJECT_VER})")
MESSAGE(STATUS "Generating with [cmake] (v${CMAKE_VERSION})")

# Policies (see https://cmake.org/cmake/help/v3.13/manual/cmake-policies.7.html)
SET(GITSHALLOW "GIT_SHALLOW ON")
IF(${CMAKE_VERSION} VERSION_GREATER_EQUAL "3.12.0")
  CMAKE_POLICY(SET CMP0074 NEW)
ENDIF()
# Required to link visulib against visuReader
IF(${CMAKE_VERSION} VERSION_GREATER_EQUAL "3.13.0")
  CMAKE_POLICY(SET CMP0079 NEW)
ENDIF()

# =========================================================================
# Load CMake modules
# =========================================================================
# Directory for custom CMake source files
LIST(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
SET_PROPERTY(GLOBAL PROPERTY USE_FOLDERS ON)
INCLUDE(CheckOrigin)

# Load CMake internal extensions
INCLUDE(CMakeDependentOption)
INCLUDE(ExternalProject)

# =========================================================================
# Performance mode
# =========================================================================
OPTION(PICLAS_PERFORMANCE "Enable performance optimizations (e.g. PGO for GNU)" OFF)

# =========================================================================
# code development
# =========================================================================
OPTION(PICLAS_CODE_ANALYZE "Code Analyze" OFF)
OPTION(PICLAS_EXTRAE "Extrae instrumentation for code profiling (event tracing)" OFF)

OPTION(PICLAS_READIN_CONSTANTS "Allow read-in of user-defined constants, such as the vacuum speed of light c0, permittivity eps and permeability mu." OFF)
IF (PICLAS_READIN_CONSTANTS)
  ADD_DEFINITIONS(-DUSE_READIN_CONSTANTS=1)
ELSE()
  ADD_DEFINITIONS(-DUSE_READIN_CONSTANTS=0)
ENDIF()

# =========================================================================
# Machine environment
# =========================================================================

INCLUDE(SetLinker)
# Languages are specified in SetCompiler as Hawk requires them
# after specifying CMAKE_COMPILER
INCLUDE(SetMachine)

PROJECT(${PROJECT_NAME}
        VERSION      ${PROJECT_VER}
        DESCRIPTION  ${PROJECT_DESC}
        HOMEPAGE_URL ${PROJECT_URL})

INCLUDE(SetCompiler)
# Load CMake internal extensions
# > must be loaded after target architecture is known
INCLUDE(GNUInstallDirs)

# =========================================================================
# Store the current commit information
# =========================================================================
SET(commit_header "${CMAKE_CURRENT_SOURCE_DIR}/src/commit.h")

# Write an inline CMake update script to a temporary file.
FILE(WRITE "${CMAKE_CURRENT_BINARY_DIR}/update_commit.cmake"
"EXECUTE_PROCESS(
  COMMAND git rev-parse HEAD
  WORKING_DIRECTORY \"${CMAKE_CURRENT_SOURCE_DIR}\"
  OUTPUT_VARIABLE GIT_COMMIT
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_QUIET
)
IF(NOT GIT_COMMIT)
  SET(GIT_COMMIT \"\")
ENDIF()
FILE(WRITE \"\${commit_header}\" \"! Define the current commit hash. The default must remain empty, i.e., ''.\n#define GIT_CURRENT_COMMIT \\\"\${GIT_COMMIT}\\\"\n\")
")

# Create a custom target that always updates the commit header.
# This target will run on every build invocation.
ADD_CUSTOM_TARGET(UpdateGitCommitHash ALL
  COMMAND ${CMAKE_COMMAND} -Dcommit_header=${commit_header} -P ${CMAKE_CURRENT_BINARY_DIR}/update_commit.cmake
  COMMENT "Updating commit header with current git commit"
  VERBATIM
)

# =========================================================================
# Check IPO support:
# =========================================================================
# we need to have languages enabled and compilers defined for this
SET(IPO_CMAKE_MINIMUM "3.9.0")
IF(WIN32)
  # Disable IPO/LTO on Windows: gfortran + LTO + -fstack-arrays triggers internal
  # compiler errors (segfault in f951.exe) with MinGW/UCRT64 gfortran 15.x
  MESSAGE(STATUS "Interprocedural optimization (IPO/LTO) disabled on Windows to avoid gfortran ICE")
  SET(PICLAS_IPO FALSE)
ELSEIF(NOT(${CMAKE_VERSION} VERSION_LESS ${IPO_CMAKE_MINIMUM}))
  CMAKE_POLICY(SET CMP0069 NEW)
  INCLUDE(CheckIPOSupported)
  CHECK_IPO_SUPPORTED(RESULT HASIPO OUTPUT error)
  CMAKE_DEPENDENT_OPTION(PICLAS_IPO "Activate Interprocedural optimization (IPO)" ON "HASIPO" OFF)
ELSE()
  MESSAGE(STATUS "Interprocedural optimization (IPO) not supported with this cmake version ${CMAKE_VERSION}, requires at least ${IPO_CMAKE_MINIMUM}")
  SET(PICLAS_IPO FALSE)
ENDIF()

# =========================================================================
# Windows: suppress CPP line markers in preprocessed Fortran files
# =========================================================================
# gfortran 15.x on Windows crashes (f951.exe segfault) when processing CPP
# line markers that contain angle brackets, e.g.:
#   # 1 "<built-in>"
#   # 1 "<command-line>"
# Angle brackets are invalid Windows path characters and trigger an ICE.
# The -P flag tells cpp to omit all # linemarker output.
IF(WIN32 AND CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  SET(CMAKE_Fortran_PREPROCESS_SOURCE
    "<CMAKE_Fortran_COMPILER> <DEFINES> <INCLUDES> <FLAGS> -cpp -E -P <SOURCE> -o <PREPROCESSED_SOURCE>")
ENDIF()

# =========================================================================
# Output paths
# =========================================================================
SET(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/bin)
SET(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/include)
SET(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/lib)
SET(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/lib)

# Set custom install dir (needs to be done after project has been defined!)
IF(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  SET(CMAKE_INSTALL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}" CACHE PATH "Prefix prepended to install directories" FORCE)
ENDIF()

# =========================================================================
# Build type
# =========================================================================
INCLUDE(SetBuildType)

# =========================================================================
# Location of binary and filenames
# =========================================================================
# append relative filename-macro for __FILENAME__ in __STAMP__ of abort function (see piclas.h)
# subst replacement is GNU make specific
IF("${CMAKE_GENERATOR}" MATCHES "Unix Makefiles")
  SET(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -D__FILENAME__='\"$(subst ${CMAKE_SOURCE_DIR}/,,$(abspath $<))\"'")
ENDIF()

# add basedir for location of corresponding userblock-file
ADD_COMPILE_DEFINITIONS("BASEDIR='\"${CMAKE_CURRENT_BINARY_DIR}/\"'")

# =========================================================================
# Echo compile definitions
# =========================================================================
GET_DIRECTORY_PROPERTY(comp_defs DIRECTORY ${CMAKE_SOURCE_DIR} COMPILE_DEFINITIONS )
SET(comp_defs_str "COMPILE_DEFINITIONS = ")
FOREACH (def ${comp_defs})
   SET(comp_defs_str "${comp_defs_str} -D${def}")
ENDFOREACH()
ADD_CUSTOM_TARGET(preproc_defines COMMAND echo ${comp_defs_str})

# =========================================================================
# USERBLOCK + PREPROC_FLAGS
# =========================================================================
# A function to get all user defined variables with a specified prefix
FUNCTION (GETLISTOFVARSSTARTINGWITH _PREFIX _VARRESULT)
    GET_CMAKE_PROPERTY(_VARS CACHE_VARIABLES)
    STRING(REGEX MATCHALL "(^|;)${_PREFIX}[A-Za-z0-9_]*" _MATCHEDVARS "${_VARS}")
    SET(${_VARRESULT} ${_MATCHEDVARS} PARENT_SCOPE)
ENDFUNCTION()

# A function to get all user defined variables with a specified prefix
SET(configuration ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/configuration.cmake)
FILE(WRITE ${configuration} "")
GETLISTOFVARSSTARTINGWITH("PICLAS_" piclasVars1)
GETLISTOFVARSSTARTINGWITH("HDF5_"   piclasVars2)
GETLISTOFVARSSTARTINGWITH("CMAKE_"  piclasVars3)
GETLISTOFVARSSTARTINGWITH("POSTI_"  piclasVars4)
GETLISTOFVARSSTARTINGWITH("LIBS_"   piclasVars5)
FOREACH (_var IN LISTS piclasVars1 piclasVars2 piclasVars3 piclasVars4 piclasVars5)
  GET_PROPERTY(currentHelpString CACHE "${_var}" PROPERTY HELPSTRING)
  # Skip empty variables
  # Quote every value expansion: a cache variable may hold a ;-separated list
  # (e.g. CMAKE_CUDA_ARCHITECTURES = "75-real;86-real;89-real;90-virtual"), which
  # would otherwise expand into multiple IF/STRING arguments and error out.
  IF(NOT "${${_var}}" STREQUAL "")
    IF("${${_var}}" STREQUAL "ON" OR "${${_var}}" STREQUAL "OFF")
      FILE(APPEND ${configuration} "OPTION(${_var} \"${currentHelpString}\" ${${_var}})\n")
    ELSE()
      IF(${_var})
        STRING(REPLACE "\\" "\\\\" ${_var} "${${_var}}")
      ENDIF()
      FILE(APPEND ${configuration} "SET(${_var} \"${${_var}}\" CACHE STRING \"${currentHelpString}\")\n")
    ENDIF()
  ENDIF()
ENDFOREACH()

# =========================================================================
# HOPR pre-processor
# =========================================================================
# Windows port: HOPR is the hopr-win fork (Windows-buildable). The upstream Linux source is
# https://github.com/hopr-framework/hopr.git.
OPTION(LIBS_BUILD_HOPR "Build HOPR pre-processor by compiling the source code downloaded from https://github.com/HallGrossaxt/hopr-win.git" OFF)
SET(HOPR_TAG "v1.2.0" CACHE STRING "HOPR version tag for downloading the executable or compiling the source code (from GitHub)")
# NOTE: the pre-built HOPR AppImage below is a Linux x86_64 binary and is NOT usable on Windows.
# On Windows, build HOPR from source via LIBS_BUILD_HOPR (hopr-win) or use a separately built
# hopr-win/build_windows/bin/hopr.exe. This Linux download stays OFF.
SET(HOPR_DOWNLOAD_URL "https://github.com/hopr-framework/hopr/releases/download/${HOPR_TAG}/hopr-linux64.zip")
OPTION(LIBS_DOWNLOAD_HOPR "Download HOPR pre-processor AppImage executable from ${HOPR_DOWNLOAD_URL} (Linux only; not for Windows)" OFF)

# =========================================================================
# ADD LIBRARIES
# =========================================================================
INCLUDE(SetLibraries)

# =========================================================================
# GPU acceleration (CUDA) — must be included after SetLibraries and before
# src/CMakeLists.txt so ENABLE_LANGUAGE(CUDA) is in effect for all targets.
# =========================================================================
INCLUDE(SetGPU)

# =========================================================================
# PICLas
# =========================================================================
INCLUDE(${CMAKE_CURRENT_SOURCE_DIR}/src/CMakeLists.txt)

# =========================================================================
# Posti
# =========================================================================
OPTION(PICLAS_BUILD_POSTI "Build POSTI toolset" ON)
IF(PICLAS_BUILD_POSTI)
  INCLUDE(${CMAKE_CURRENT_SOURCE_DIR}/src/posti/CMakeLists.txt)
ELSE()
  GETLISTOFVARSSTARTINGWITH("POSTI_" postiVars)
  FOREACH (_var IN LISTS postiVars)
    UNSET(${_var} CACHE)
  ENDFOREACH()
ENDIF()

# =========================================================================
# Userblock
# =========================================================================
#MESSAGE(STATUS "Running: generateuserblock.sh ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}  ${CMAKE_CACHEFILE_DIR} ${CMAKE_CACHE_MAJOR_VERSION}.${CMAKE_CACHE_MINOR_VERSION}.${CMAKE_CACHE_PATCH_VERSION} ${CMAKE_CURRENT_SOURCE_DIR}/src/globals/globals_vars.f90")
MESSAGE(STATUS "Running: generateuserblock ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}  ${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_VERSION} ${CMAKE_CURRENT_SOURCE_DIR}/src/globals/globals_vars.f90")
#ADD_CUSTOM_COMMAND(TARGET libpiclasstatic PRE_BUILD COMMAND
  #sh ${CMAKE_CURRENT_SOURCE_DIR}/tools/userblock/generateuserblock.sh ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}  ${CMAKE_CACHEFILE_DIR} "${CMAKE_CACHE_MAJOR_VERSION}.${CMAKE_CACHE_MINOR_VERSION}.${CMAKE_CACHE_PATCH_VERSION}" "${CMAKE_CURRENT_SOURCE_DIR}/src/globals/globals_vars.f90")
IF(WIN32)
  # On Windows: use the PowerShell script which creates userblock.txt and a stub userblock.o
  # Use full path to powershell.exe so it is found regardless of PATH during Ninja build
  ADD_CUSTOM_COMMAND(TARGET libpiclasstatic PRE_BUILD COMMAND
    "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" -ExecutionPolicy Bypass -NonInteractive -File
    "${CMAKE_CURRENT_SOURCE_DIR}/tools/userblock/generateuserblock.ps1"
    "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}"
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_VERSION}"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/globals/globals_vars.f90"
    "${CMAKE_C_COMPILER}"
    BYPRODUCTS ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/userblock.o)
ELSE()
  ADD_CUSTOM_COMMAND(TARGET libpiclasstatic PRE_BUILD COMMAND
    sh ${CMAKE_CURRENT_SOURCE_DIR}/tools/userblock/generateuserblock.sh ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}  ${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_VERSION} "${CMAKE_CURRENT_SOURCE_DIR}/src/globals/globals_vars.f90"
    BYPRODUCTS ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/userblock.o)
ENDIF()

# =========================================================================
# generate .piclas in $HOME (Unix/Linux only)
# =========================================================================
IF(NOT WIN32)
  ADD_CUSTOM_COMMAND(TARGET piclas POST_BUILD COMMAND echo \"export PICLAS_DIR=${CMAKE_RUNTIME_OUTPUT_DIRECTORY}\" > $ENV{HOME}/.piclas)
  ADD_CUSTOM_COMMAND(TARGET piclas POST_BUILD COMMAND echo \"alias piclas='${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/piclas'\" >> $ENV{HOME}/.piclas)
ENDIF()

# =========================================================================
# Install
# =========================================================================
INSTALL(FILES    ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/configuration.cmake ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/userblock.txt DESTINATION bin)