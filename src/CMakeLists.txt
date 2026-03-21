# =========================================================================
# PICLas Options
# =========================================================================

# Build directory list
MACRO(SUBDIRLIST result curdir)
  FILE(GLOB children RELATIVE ${curdir} ${curdir}/*)
  SET(dirlist "")
  FOREACH(child ${children})
    IF(IS_DIRECTORY ${curdir}/${child})
      LIST(APPEND dirlist ${child})
    ENDIF()
  ENDFOREACH()
  SET(${result} ${dirlist})
ENDMACRO()
SUBDIRLIST(EQNSYSTEMS ${CMAKE_CURRENT_SOURCE_DIR}/src/equations/)

OPTION(PICLAS_PARTICLES "Particles" ON)

# =========================================================================
# Time discretization
# =========================================================================
SET(PICLAS_TIMEDISCMETHOD "RK4" CACHE STRING "Time integration method")
SET_PROPERTY(CACHE PICLAS_TIMEDISCMETHOD PROPERTY STRINGS Euler-Explicit
                                                          Leapfrog
                                                          Boris-Leapfrog
                                                          Higuera-Cary
                                                          RK3
                                                          RK4
                                                          RK14
                                                          DSMC
                                                          FP-Flow
                                                          BGK-Flow
                                                          ED-DVM
                                                          Explicit-FV
                                                          PLOESMA
                                                          Radiation)

# =========================================================================
# Shared memory region splitting
# =========================================================================
# Get environment variable, e.g. PICLAS_SPLIT_TYPE=OMPI_COMM_TYPE_CORE
SET(PICLAS_SPLIT_TYPE "$ENV{PICLAS_SPLIT_TYPE}")
IF("${PICLAS_SPLIT_TYPE}" STREQUAL "")
  SET(PICLAS_SPLIT_TYPE "MPI_COMM_TYPE_SHARED")
ELSE()
  #IF("${PICLAS_SPLIT_TYPE}" STREQUAL "${PICLAS_SHARED_MEMORY}")
  MESSAGE(STATUS "Using user-defined environment variable [PICLAS_SPLIT_TYPE = ${PICLAS_SPLIT_TYPE}] for shared memory communicator splitting. Setting [PICLAS_SHARED_MEMORY = ${PICLAS_SPLIT_TYPE}]")
  #ENDIF()
ENDIF()
SET(PICLAS_SHARED_MEMORY "${PICLAS_SPLIT_TYPE}" CACHE STRING "Split type for creating new communicators based on colors and keys (requires MPI 3 or higher). Options with the prefix OMPI_ are specific to Open MPI.")
SET_PROPERTY(CACHE PICLAS_SHARED_MEMORY PROPERTY STRINGS MPI_COMM_TYPE_SHARED
                                                         OMPI_COMM_TYPE_CORE
                                                         PICLAS_COMM_TYPE_NODE)

ADD_DEFINITIONS(-DSharedMemoryMethod=${PICLAS_SHARED_MEMORY})
IF(PICLAS_SHARED_MEMORY STREQUAL "MPI_COMM_TYPE_SHARED")
  UNSET(PICLAS_SHARED_MEMORY_CORES CACHE)
  ADD_DEFINITIONS(-DCORE_SPLIT=0)
  MESSAGE(STATUS "Shared memory split type for subcommunicators set to node-level")
ELSEIF(PICLAS_SHARED_MEMORY STREQUAL "OMPI_COMM_TYPE_CORE")
  UNSET(PICLAS_SHARED_MEMORY_CORES CACHE)
  ADD_DEFINITIONS(-DCORE_SPLIT=1)
  MESSAGE(STATUS "Shared memory split type for subcommunicators set to core-level")
ELSEIF(PICLAS_SHARED_MEMORY STREQUAL "PICLAS_COMM_TYPE_NODE")
  SET(PICLAS_SHARED_MEMORY_CORES "2" CACHE STRING "Number of cores per node when setting PICLAS_SHARED_MEMORY=PICLAS_COMM_TYPE_NODE. All cores must be on the same physical node!")
  ADD_DEFINITIONS(-DCORE_SPLIT=${PICLAS_SHARED_MEMORY_CORES})
  MESSAGE(STATUS "Shared memory split type for subcommunicators set to sub-node-level with user-specific value [PICLAS_SHARED_MEMORY_CORES = ${PICLAS_SHARED_MEMORY_CORES}] cores per node")
ENDIF()

# =========================================================================
# MISC
# =========================================================================
CMAKE_DEPENDENT_OPTION(PICLAS_LOADBALANCE "Use load balance time measurement" ON "LIBS_USE_MPI" OFF)

OPTION(PICLAS_INTKIND8 "Enable particle numbers larger than 2147483647 (on most systems, huge(4-byte-integer)))" OFF)
IF(PICLAS_INTKIND8)
   ADD_DEFINITIONS(-DINTKIND8)
ENDIF()

# =========================================================================
# Polynomial degree
# =========================================================================
SET(PICLAS_POLYNOMIAL_DEGREE "N" CACHE STRING "N: compile with variable polynomial degree. 1,2,3,...: compile with fixed polynomial degree for performance (untested).")
ADD_DEFINITIONS(-DPP_N=${PICLAS_POLYNOMIAL_DEGREE})

# =========================================================================
# Node type
# =========================================================================
SET(PICLAS_NODETYPE "GAUSS" CACHE STRING "Set of nodes used for representing the solution (GAUSS/GAUSS-LOBATTO).")
SET_PROPERTY(CACHE PICLAS_NODETYPE PROPERTY STRINGS "GAUSS" "GAUSS-LOBATTO")
IF(PICLAS_NODETYPE STREQUAL "GAUSS")
  ADD_DEFINITIONS(-DPP_NodeType=1)
ELSEIF(PICLAS_NODETYPE STREQUAL "GAUSS-LOBATTO")
  ADD_DEFINITIONS(-DPP_NodeType=2)
ELSE()
  MESSAGE(SEND_ERROR "Unknown node type.")
ENDIF()
ADD_DEFINITIONS(-DPP_nElems=NELEMZ)

# =========================================================================
# Equation system
# =========================================================================
SET(PICLAS_EQNSYSNAME "maxwell" CACHE STRING "Used equation system")
SET_PROPERTY(CACHE PICLAS_EQNSYSNAME PROPERTY STRINGS ${EQNSYSTEMS})

# =========================================================================
# Analytical Vandermonde
# =========================================================================
OPTION(PICLAS_VDM_ANALYTICAL "Alternative to matrix inversion: Compute inverse Vandermonde directly (required for inverse of Bezier and Legendre Vdm)" OFF)
# VDM inverse for Lagrange polynomials, replace lapack with analytical solution, for Bezier switch to LU inverse calculation
IF (FORCE_VDM_ANALYTICAL)
  SET(PICLAS_VDM_ANALYTICAL ON CACHE BOOL "Auto-Activated: Alternative to matrix inversion: Compute inverse Vandermonde directly (required for inverse of Bezier and Legendre Vdm)" FORCE)
ENDIF()
IF (PICLAS_VDM_ANALYTICAL)
  ADD_DEFINITIONS(-DVDM_ANALYTICAL)
ENDIF()

# =========================================================================
# Equation system
# =========================================================================
IF(PICLAS_EQNSYSNAME STREQUAL "maxwell")
  #SET(PICLAS_C_PREPROC ${F2P_C_PREPROC} -Dmaxwell)
  ADD_DEFINITIONS(-DPP_nVar=8 -Dmaxwell)
  SET(PICLAS_HDG OFF)
  SET(PICLAS_FV OFF)
ELSEIF(PICLAS_EQNSYSNAME STREQUAL "poisson")
  ADD_DEFINITIONS(-DPP_nVar=1 -Dpoisson)
  SET(PICLAS_HDG ON)
  SET(PICLAS_FV OFF)
ELSEIF(PICLAS_EQNSYSNAME STREQUAL "maxwell_pois")
  ADD_DEFINITIONS(-DPP_nVar=8 -Dmaxwell_pois -DPOIS)
  SET(PICLAS_HDG OFF)
  SET(PICLAS_FV OFF)
  MESSAGE(SEND_ERROR "Equation system is currently not supported.")
ELSEIF(PICLAS_EQNSYSNAME STREQUAL "magnetostatic")
  ADD_DEFINITIONS(-DPP_nVar=3 -Dmagnetostatic)
  SET(PICLAS_HDG ON)
  SET(PICLAS_FV OFF)
  MESSAGE(SEND_ERROR "Equation system is currently not supported.")
ELSEIF(PICLAS_EQNSYSNAME STREQUAL "magnetostatic_poisson")
  ADD_DEFINITIONS(-DPP_nVar=4 -Dmagnetostatic_poisson)
  SET(PICLAS_HDG ON)
  SET(PICLAS_FV OFF)
  MESSAGE(SEND_ERROR "Equation system is currently not supported.")
ELSEIF(PICLAS_EQNSYSNAME STREQUAL "discrete_velocity")
  IF(PICLAS_TIMEDISCMETHOD STREQUAL "PLOESMA")
    ADD_DEFINITIONS(-Ddiscrete_velocity)
    ADD_DEFINITIONS(-DPP_nVar=1 -Dpoisson)
    SET(PICLAS_HDG ON)
    SET(PICLAS_FV ON)
  ELSE()
    ADD_DEFINITIONS(-DPP_nVar=0 -Ddiscrete_velocity)
    SET(PICLAS_HDG OFF)
    SET(PICLAS_FV ON)
  ENDIF()
ELSEIF(PICLAS_EQNSYSNAME STREQUAL "drift_diffusion")
  ADD_DEFINITIONS(-DPP_nVar_FV=1 -Ddrift_diffusion)
  ADD_DEFINITIONS(-DPP_nVar=1 -Dpoisson)
  SET(PICLAS_HDG ON)
  SET(PICLAS_FV ON)

ELSE()
   MESSAGE(SEND_ERROR "Unknown equation system.")
ENDIF()

# =========================================================================
# PARTICLES
# =========================================================================
IF(PICLAS_PARTICLES)
  ADD_DEFINITIONS(-DPARTICLES)
ELSE()
  IF(PICLAS_TIMEDISCMETHOD STREQUAL "DSMC")
    MESSAGE(SEND_ERROR "DSMC cannot be used without particles.")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "BGK-Flow")
    MESSAGE(SEND_ERROR "BGK-Flow cannot be used without particles.")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "FP-Flow")
    MESSAGE(SEND_ERROR "FP-Flow cannot be used without particles.")
  ENDIF()
ENDIF(PICLAS_PARTICLES)

# =========================================================================
# CODE_ANALYZE and EXTRAE instrumentation
# =========================================================================
IF(PICLAS_CODE_ANALYZE)
  ADD_DEFINITIONS(-DCODE_ANALYZE)
ENDIF(PICLAS_CODE_ANALYZE)

IF(PICLAS_EXTRAE)
  MESSAGE(STATUS "Activated extrae code tracing instrumentation using: $ENV{EXTRAE_HOME}")
  ADD_DEFINITIONS(-DEXTRAE)
ENDIF(PICLAS_EXTRAE)

# =========================================================================
# Timedisc method
# =========================================================================
IF(PICLAS_TIMEDISCMETHOD STREQUAL "Euler-Explicit")
  IF(PICLAS_HDG)
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepPoisson.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=500)
  ELSE()
      MESSAGE(SEND_ERROR "Time discretization method requires PICLAS_EQNSYSNAME=poisson.")
  ENDIF()
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Higuera-Cary")
  IF(PICLAS_HDG)
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepPoissonByHigueraCary.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=507)
  ELSE()
      MESSAGE(SEND_ERROR "Time discretization method requires PICLAS_EQNSYSNAME=poisson.")
  ENDIF()
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Boris-Leapfrog")
  IF(PICLAS_HDG)
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepPoissonByBorisLeapfrog.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=508)
  ELSE()
      MESSAGE(SEND_ERROR "Time discretization method requires PICLAS_EQNSYSNAME=poisson.")
  ENDIF()
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Leapfrog")
  IF(PICLAS_HDG)
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepPoisson.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=509)
  ELSE()
      MESSAGE(SEND_ERROR "Time discretization method requires PICLAS_EQNSYSNAME=poisson.")
  ENDIF()
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK3")
  IF(PICLAS_HDG)
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepPoissonByLSERK.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=501 -DLSERK)
  ELSE()
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepByLSERK.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=1 -DLSERK)
  ENDIF()
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK4")
  IF(PICLAS_HDG)
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepPoissonByLSERK.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=502 -DLSERK)
  ELSE()
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepByLSERK.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=2 -DLSERK)
  ENDIF()
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK14")
  IF(PICLAS_HDG)
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepPoissonByLSERK.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=506 -DLSERK)
  ELSE()
      FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStepByLSERK.f90)
      ADD_DEFINITIONS(-DPP_TimeDiscMethod=6 -DLSERK)
  ENDIF()
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "DSMC")
  FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStep_DSMC.f90)
  ADD_DEFINITIONS(-DPP_TimeDiscMethod=4)
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "FP-Flow")
   FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStep_FPFlow.f90)
   ADD_DEFINITIONS(-DPP_TimeDiscMethod=300)
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "BGK-Flow")
   FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStep_BGK.f90)
   ADD_DEFINITIONS(-DPP_TimeDiscMethod=400)
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Radiation")
   FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStep_Radiation.f90)
   ADD_DEFINITIONS(-DPP_TimeDiscMethod=600)
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "ED-DVM")
  FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStep_DVM.f90)
  ADD_DEFINITIONS(-DPP_TimeDiscMethod=700)
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Explicit-FV")
  FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStep_ExplicitFV.f90)
  ADD_DEFINITIONS(-DPP_TimeDiscMethod=701)
ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "PLOESMA")
  FILE(GLOB timediscF90 ${CMAKE_CURRENT_SOURCE_DIR}/src/timedisc/timedisc_TimeStep_ploesma.f90)
  ADD_DEFINITIONS(-DPP_TimeDiscMethod=702)
ELSE()
   MESSAGE(SEND_ERROR "Unknown time discretization method.")
ENDIF()

# =========================================================================
# HDG
# =========================================================================

IF(PICLAS_HDG)
  ADD_DEFINITIONS(-DUSE_HDG=1)
  IF(PICLAS_TIMEDISCMETHOD STREQUAL "Euler-Explicit")
      MESSAGE(STATUS "use HDG with Euler-Explicit")
    ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Higuera-Cary")
      MESSAGE(STATUS "use HDG with Higuera-Cary")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Boris-Leapfrog")
      MESSAGE(STATUS "use HDG with Boris-Leapfrog")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Leapfrog")
      MESSAGE(STATUS "use HDG with Leapfrog")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK3")
      MESSAGE(STATUS "use HDG with RK3")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK4")
      MESSAGE(STATUS "use HDG with RK4")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK14")
      MESSAGE(STATUS "use HDG with RK14")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Explicit-FV")
     MESSAGE(STATUS "use HDG in parallel to Explicit-FV")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "PLOESMA")
     MESSAGE(STATUS "use HDG in parallel to DVM")
  ELSE()
      MESSAGE(SEND_ERROR "Unknown time discretization method for HDG.")
  ENDIF()
ELSE()
  ADD_DEFINITIONS(-DUSE_HDG=0)
ENDIF(PICLAS_HDG)

# =========================================================================
# FV
# =========================================================================

CMAKE_DEPENDENT_OPTION(PICLAS_FV_2D "FV fluxes not calculated for dimension Z" OFF "PICLAS_FV" OFF)

IF(PICLAS_FV)
  ADD_DEFINITIONS(-DUSE_FV=1)
  IF(PICLAS_FV_2D)
    IF (PICLAS_HDG)
      MESSAGE(SEND_ERROR "PICLAS_FV_2D not available in combination with HDG")
    ELSE()
      ADD_DEFINITIONS(-DPP_dim=2)
      MESSAGE(STATUS "use FV with 2D fluxes")
    ENDIF(PICLAS_HDG)
  ELSE()
    ADD_DEFINITIONS(-DPP_dim=3)
  ENDIF(PICLAS_FV_2D)
  IF(PICLAS_TIMEDISCMETHOD STREQUAL "ED-DVM")
    MESSAGE(STATUS "use FV with DVM")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "Explicit-FV")
    MESSAGE(STATUS "use Explicit Finite Volumes")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "PLOESMA")
    MESSAGE(STATUS "use HDG for fields and FV for DVM")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK3")
    MESSAGE(STATUS "use HDG/FV with RK3")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK4")
    MESSAGE(STATUS "use HDG/FV with RK4")
  ELSEIF(PICLAS_TIMEDISCMETHOD STREQUAL "RK14")
    MESSAGE(STATUS "use HDG/FV with RK14")
  ELSE()
    MESSAGE(SEND_ERROR "Unknown time discretization method for FV.")
  ENDIF()
ELSE()
  ADD_DEFINITIONS(-DUSE_FV=0)
  ADD_DEFINITIONS(-DPP_dim=3)
ENDIF(PICLAS_FV)

# ========================================================================
# LOADBALANCE
# =========================================================================
IF(LIBS_USE_MPI)
  IF(PICLAS_LOADBALANCE)
    MESSAGE(STATUS "Building PICLas with LoadBalance")
    ADD_DEFINITIONS(-DUSE_LOADBALANCE=1)
  ELSE()
    ADD_DEFINITIONS(-DUSE_LOADBALANCE=0)
  ENDIF()
ELSE()
  ADD_DEFINITIONS(-DUSE_LOADBALANCE=0)
ENDIF()

# =========================================================================
# Coffee Lib
# =========================================================================
OPTION(CMAKE_ANS_COFFEE "Enable coffee lib" OFF)
MARK_AS_ADVANCED(FORCE CMAKE_ANS_COFFEE)
IF(CMAKE_ANS_COFFEE)
  ADD_DEFINITIONS(-DUSE_COFFEE=1)
ELSE()
  ADD_DEFINITIONS(-DUSE_COFFEE=0)
ENDIF()

# =========================================================================
# Unit test at end of compilation
# =========================================================================
# Check is unit tests can be activated
IF(BUILD_TYPE_LC MATCHES "sanitize" AND LIBS_USE_MPI)
  SET(ACTIVATE_UNIT_TEST OFF)
  # Check if unit tests were previously activated
  IF(PICLAS_UNITTESTS AND LIBS_MPI_NAME MATCHES "OpenMPI")
    MESSAGE(WARNING "Unit tests automatically disabled (PICLAS_UNITTESTS=OFF) with\n CMAKE_BUILD_TYPE = ${CMAKE_BUILD_TYPE}\n LIBS_USE_MPI = ${LIBS_USE_MPI}\nas the tests will always fail due to memory errors returned from the MPI library.")
    SET(PICLAS_UNITTESTS OFF)
  ENDIF()
ELSE()
  SET(ACTIVATE_UNIT_TEST ON)
ENDIF()

# Enable unit testing only when ACTIVATE_UNIT_TEST=ON
CMAKE_DEPENDENT_OPTION(PICLAS_UNITTESTS "Enable unit tests after build" ON "ACTIVATE_UNIT_TEST" OFF)

IF(PICLAS_UNITTESTS)
  INCLUDE(${CMAKE_CURRENT_SOURCE_DIR}/unitTests/CMakeLists.txt)
ENDIF()

# =========================================================================
# PICLas sources & targets
# =========================================================================
FUNCTION(add_exec target)
  ADD_EXECUTABLE(       ${target} ${ARGN})
  TARGET_LINK_LIBRARIES(${target} libpiclasshared)
  IF(WIN32)
    # On Windows, MPI symbols (mpi_finalize_ etc.) are not transitively exported through the
    # shared library import stub, so link executables directly against the same libs as the DLL.
    TARGET_LINK_LIBRARIES(${target} ${linkedlibs})
    SET_TARGET_PROPERTIES(${target} PROPERTIES COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS}
                                               CMAKE_POSITION_INDEPENDENT_CODE ON
                                               LINKER_LANGUAGE Fortran)
  ELSE()
    SET_TARGET_PROPERTIES(${target} PROPERTIES COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS}
                                               COMPILE_OPTIONS "-fPIC"
                                               CMAKE_POSITION_INDEPENDENT_CODE ON
                                               LINKER_LANGUAGE Fortran)
  ENDIF()
  INSTALL(PROGRAMS ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${target} DESTINATION bin)
  STRING(TOUPPER ${target} TARGETUP)
  ADD_CUSTOM_COMMAND(TARGET ${target} POST_BUILD COMMAND ${CMAKE_COMMAND} -E cmake_echo_color --cyan "SUCCESS: ${TARGETUP} BUILD COMPLETE!")
ENDFUNCTION()

FUNCTION(add_lib_shared target)
  ADD_LIBRARY(          ${target} SHARED ${ARGN})
  IF(WIN32)
    TARGET_LINK_LIBRARIES(${target} PRIVATE ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/userblock.o $<LINK_LIBRARY:WHOLE_ARCHIVE,libpiclasstatic> userblocklib stacksizelib globlib memusagelib ${linkedlibs})
  ELSE()
    TARGET_LINK_LIBRARIES(${target} PRIVATE ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/userblock.o libpiclasstatic userblocklib stacksizelib globlib memusagelib ${linkedlibs})
  ENDIF()
  IF(WIN32)
    SET_TARGET_PROPERTIES(${target} PROPERTIES PREFIX ""
                                               COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS}
                                               CMAKE_POSITION_INDEPENDENT_CODE ON
                                               LINKER_LANGUAGE Fortran)
    TARGET_LINK_OPTIONS(${target} PRIVATE -Wl,--export-all-symbols)
  ELSE()
    SET_TARGET_PROPERTIES(${target} PROPERTIES PREFIX ""
                                               COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS}
                                               COMPILE_OPTIONS "-fPIC"
                                               CMAKE_POSITION_INDEPENDENT_CODE ON
                                               LINKER_LANGUAGE Fortran)
  ENDIF()
  INSTALL(TARGETS ${target} LIBRARY PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                                                GROUP_READ GROUP_EXECUTE
                                                WORLD_READ WORLD_EXECUTE
                            DESTINATION lib)
  STRING(TOUPPER ${target} TARGETUP)
  ADD_CUSTOM_COMMAND(TARGET ${target} POST_BUILD COMMAND ${CMAKE_COMMAND} -E cmake_echo_color --cyan "SUCCESS: ${TARGETUP} BUILD COMPLETE!")
ENDFUNCTION()

# include piclas.h
INCLUDE_DIRECTORIES(${CMAKE_CURRENT_SOURCE_DIR}/src)

# collect all F90 files needed for libpiclasstatic
FILE(GLOB_RECURSE piclasF90 ./src/init/*.f90
                            ./src/analyze/*.f90
                            ./src/filter/*.f90
                            ./src/globals/*.f90
                            ./src/mortar/*.f90
                            ./src/interpolation/basis.f90
                            ./src/interpolation/interpolation.f90
                            ./src/interpolation/interpolation_vars.f90
                            ./src/interpolation/changeBasis.f90
                            ./src/io_hdf5/*.f90
                            ./src/loadbalance/*.f90
                            ./src/mesh/*.f90
                            ./src/interfaces/*.f90
                            ./src/dielectric/*.f90
                            ./src/mpi/*.f90
                            ./src/output/*.f90
                            ./src/readintools/*.f90
                            ./src/recordpoints/*.f90
                            ./src/restart/*.f90
                            ./src/utils/*.f90
                            ./src/symmetry/*.f90
                            ./unitTests/unittest.f90
                            ./unitTests/unittest_vars.f90)

LIST(APPEND timediscF90 ${timediscF90}
                        ./src/timedisc/timedisc.f90
                        ./src/timedisc/timedisc_init.f90
                        ./src/timedisc/timedisc_vars.f90)

LIST(APPEND piclasF90 ${timediscF90})

FILE(GLOB_RECURSE dgF90 ./src/dg/*.f90
                        ./src/interpolation/prolongtoface.f90
                        ./src/pml/*.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/*.f90)

FILE(GLOB_RECURSE hdgF90 ./src/hdg/*.f90
                         ./src/dg/dg.f90
                         ./src/dg/dg_vars.f90
                         ./src/interpolation/prolongtoface.f90
                         ./src/equations/${PICLAS_EQNSYSNAME}/equation.f90
                         ./src/equations/${PICLAS_EQNSYSNAME}/equation_tools.f90
                         ./src/equations/${PICLAS_EQNSYSNAME}/equation_vars.f90
                         ./src/equations/${PICLAS_EQNSYSNAME}/timeavg.f90
                         ./src/equations/${PICLAS_EQNSYSNAME}/timeavg_vars.f90
                         ./src/equations/${PICLAS_EQNSYSNAME}/getboundaryflux.f90)

FILE(GLOB_RECURSE fvF90 ./src/fv/*.f90
                        ./src/gradients/*.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/*.f90)

FILE(GLOB_RECURSE hdgfvF90 ./src/hdg/*.f90
                         ./src/dg/dg.f90
                         ./src/dg/dg_vars.f90
                         ./src/fv/*.f90
                        ./src/interpolation/prolongtoface.f90
                        ./src/gradients/*.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/equation.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/equation_vars.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/transport_data.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/riemann.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/getboundaryflux.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/getboundarygrad.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/ionization.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/dvm_boundary_analyze.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/distfunc.f90
                        ./src/equations/${PICLAS_EQNSYSNAME}/calctimestep.f90
                        ./src/equations/poisson/equation.f90
                        ./src/equations/poisson/equation_tools.f90
                        ./src/equations/poisson/equation_vars.f90
                        ./src/equations/poisson/timeavg.f90
                        ./src/equations/poisson/timeavg_vars.f90)

#FILE(GLOB mainF90 ./src/piclas.f90
                  #./src/piclaslib.f90)
FILE(GLOB_RECURSE particlesF90 ./src/particles/*.f90
                               ./src/posti/superB/*.f90
                               ./src/interpolation/eval_xyz.f90
                               ./src/radiation/ray_tracing/*.f90
                               ./src/radiation/radiative_transfer/radtrans_vars.f90
                               ./src/radiation/radiative_transfer/tracking/*.f90
                               ./src/radiation/radiation_solver/radiation_vars.f90)

FILE(GLOB noparticlesF90 ./src/particles/analyze/particle_analyze_vars.f90
                         ./src/particles/particle_mesh/particle_surfaces_vars.f90
                         ./src/particles/particle_mesh/particle_mesh_vars.f90
                         ./src/particles/particle_vars.f90
                         ./src/particles/emission/particle_emission_vars.f90
                         ./src/particles/emission/particle_surface_flux_vars.f90
                         ./src/posti/superB/superB_vars.f90
                         ./src/particles/boundary/particle_boundary_vars.f90)

FILE(GLOB_RECURSE extraeF90 ./src/extrae/*.f90)

FILE(GLOB_RECURSE radiationF90 ./src/radiation/*.f90)

IF(PICLAS_EXTRAE)
  LIST(APPEND piclasF90 ${extraeF90})
ENDIF(PICLAS_EXTRAE)

IF(PICLAS_HDG)
  IF(PICLAS_FV)
    LIST(APPEND piclasF90 ${hdgfvF90})
  ELSE()
    LIST(APPEND piclasF90 ${hdgF90})
  ENDIF()
ELSEIF(PICLAS_FV)
  LIST(FILTER noparticlesF90 EXCLUDE REGEX ".*superb.f90$")
  LIST(APPEND piclasF90 ${fvF90})
ELSE()
  LIST(FILTER particlesF90 EXCLUDE REGEX ".*particle_br_electron_fluid.f90$")
  LIST(FILTER particlesF90 EXCLUDE REGEX ".*superb.f90$")
  LIST(APPEND piclasF90 ${dgF90})
ENDIF(PICLAS_HDG)

#LIST(APPEND piclasF90 ${mainF90})
IF (PICLAS_PARTICLES)
  LIST(APPEND piclasF90 ${particlesF90})
ELSE()
  LIST(APPEND piclasF90 ${noparticlesF90})
ENDIF(PICLAS_PARTICLES)
IF (PICLAS_TIMEDISCMETHOD STREQUAL "Radiation")
  LIST(APPEND piclasF90 ${radiationF90})
ENDIF()

# =========================================================================
# GPU acceleration — add Fortran interface sources to the main lib
# =========================================================================
IF(PICLAS_USE_GPU)
  FILE(GLOB gpuF90 ./src/gpu/gpu_vars.f90
                   ./src/gpu/gpu_interface.f90)
  LIST(APPEND piclasF90 ${gpuF90})
ENDIF()

# define libs
ADD_LIBRARY(          libpiclasstaticF90 OBJECT ${piclasF90} )
SET_TARGET_PROPERTIES(libpiclasstaticF90 PROPERTIES COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS}
                                                    COMPILE_OPTIONS "-fPIC"
                                                    CMAKE_POSITION_INDEPENDENT_CODE ON)
ADD_LIBRARY(          libpiclasstatic    STATIC $<TARGET_OBJECTS:libpiclasstaticF90>)
SET_TARGET_PROPERTIES(libpiclasstatic    PROPERTIES PREFIX ""
                                                    COMPILE_OPTIONS "-fPIC"
                                                    CMAKE_POSITION_INDEPENDENT_CODE ON
                                                    OUTPUT_NAME "libpiclasf90")
# Make sure that the script is executed even though cmake is not explicitly executed after the commit is changed in git
ADD_DEPENDENCIES(libpiclasstaticF90 UpdateGitCommitHash)
IF(SELFBUILTEXTERNALS)
  ADD_DEPENDENCIES(libpiclasstaticF90 ${SELFBUILTEXTERNALS})
ENDIF()

ADD_LIBRARY(userblocklib STATIC ./src/output/read_userblock.c)
SET_TARGET_PROPERTIES(userblocklib PROPERTIES LANGUAGE C LINKER_LANGUAGE C
                                              COMPILE_OPTIONS "-fPIC"
                                              CMAKE_POSITION_INDEPENDENT_CODE ON)

ADD_LIBRARY(stacksizelib STATIC ./src/globals/stacksize.c)
SET_TARGET_PROPERTIES(stacksizelib PROPERTIES LANGUAGE C LINKER_LANGUAGE C
                                              COMPILE_OPTIONS "-fPIC"
                                              CMAKE_POSITION_INDEPENDENT_CODE ON)

ADD_LIBRARY(globlib STATIC ./src/globals/glob_windows.c)
SET_TARGET_PROPERTIES(globlib PROPERTIES LANGUAGE C LINKER_LANGUAGE C
                                         COMPILE_OPTIONS "-fPIC"
                                         CMAKE_POSITION_INDEPENDENT_CODE ON)

ADD_LIBRARY(memusagelib STATIC ./src/globals/processmemusage.cxx)
SET_TARGET_PROPERTIES(memusagelib PROPERTIES LANGUAGE CXX LINKER_LANGUAGE CXX
                                              COMPILE_OPTIONS "-fPIC"
                                             CMAKE_POSITION_INDEPENDENT_CODE ON)

# =========================================================================
# GPU acceleration — CUDA static library (compiled by nvcc)
# =========================================================================
IF(PICLAS_USE_GPU)
  FILE(GLOB gpuCU ./src/gpu/*.cu)
  ADD_LIBRARY(piclasGPU STATIC ${gpuCU})
  SET_TARGET_PROPERTIES(piclasGPU PROPERTIES
    CUDA_SEPARABLE_COMPILATION OFF
    CUDA_ARCHITECTURES         "${CMAKE_CUDA_ARCHITECTURES}"
    # On Windows+MinGW: CMAKE_CUDA_RUNTIME_LIBRARY_DEFAULT=SHARED causes CMake
    # to inject CUDA::cudart into piclasGPU's INTERFACE_LINK_LIBRARIES, which
    # then propagates MSVC-style bare library names to all consumers.
    # Set to None so we control CUDA runtime linking explicitly via cudart.lib.
    CUDA_RUNTIME_LIBRARY       None)
  # Override INCLUDE_DIRECTORIES to prevent MinGW UCRT64 headers from being
  # passed to nvcc when using cl.exe as host compiler.  MinGW's stdio.h etc.
  # are ABI-incompatible with MSVC and cause compilation errors.
  # The .cu files only need: src/gpu (piclas_gpu.h) + CUDA SDK headers (added
  # automatically by nvcc via -isystem).
  SET_PROPERTY(TARGET piclasGPU PROPERTY INCLUDE_DIRECTORIES
    "${CMAKE_CURRENT_SOURCE_DIR}/src/gpu")
  # On Windows+MinGW: CUDA::cudart / CUDA::cudart_static both carry
  # INTERFACE_LINK_LIBRARIES with MSVC-style bare names (m, wsock32, kernel32,
  # cudadevrt, stdc++, ...) that MinGW's ld cannot resolve without -l prefix.
  # Link cudart.lib as a full-path file — MinGW can use MSVC import .lib files
  # and we avoid all the broken INTERFACE propagation from CMake CUDA targets.
  IF(WIN32 AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    # Compile CUDA host code with MSVC /GS- (disable buffer security check so
    # __security_check_cookie/__GSHandlerCheck are not generated in our .cu.obj)
    # and /MD (use MSVC DLL CRT so printf → __imp_printf resolvable by MinGW).
    # -Xcompiler=/GS-,/MD passes /GS- (disable buffer security check) and /MD
    # (use MSVC DLL CRT: printf→__imp_printf resolvable by MinGW) to cl.exe.
    # Comma-list syntax keeps the flags as a single nvcc token — spacing causes
    # nvcc to misinterpret /MD as an input file (fatal error on Windows).
    TARGET_COMPILE_OPTIONS(piclasGPU PRIVATE
      $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=/GS-,/MD,/Zc:threadSafeInit->)

    # Patch COMDAT .bss sections in gpu_init.cu.obj BEFORE the archiver runs.
    # nvcc (cl.exe host) emits ?__ref@?2??__nv_cudaEntityRegisterCallback... and
    # ?__ref@?1??____nv_dummy_param_ref... as LINK_ONCE_DISCARD COMDAT .bss
    # sections.  GNU ld discards them, leaving IMAGE_REL_AMD64_REL32 relocations
    # in ?__sti____cudaRegisterAll resolved to 0 → `mov %rax, 0(%rip)` writes
    # the fat-binary handle into the read-only .text section → ACCESS VIOLATION
    # → STATUS_DLL_INIT_FAILED at DLL load time (error 1114).
    # The Python script clears IMAGE_SCN_LNK_COMDAT from every .bss section so
    # GNU ld includes them as regular BSS and the relocations resolve correctly.
    # Patch all three CUDA object files — each .cu TU gets its own
    # COMDAT BSS sections for the CUDA fat-binary registration helpers.
    SET(_GPU_OBJ_DIR "${CMAKE_BINARY_DIR}/CMakeFiles/piclasGPU.dir/src/gpu")
    SET(_PATCH_PY    "${CMAKE_CURRENT_SOURCE_DIR}/src/gpu/patch_cuda_comdat.py")
    ADD_CUSTOM_COMMAND(TARGET piclasGPU PRE_LINK
      # Delete the archive first so 'ar qc' creates a fresh one with only patched objects.
      # Without this, 'ar qc' appends patched objects AFTER the old unpatched ones and
      # GNU ld uses the first (unpatched) definition, leaving zero-displacement relocations.
      COMMAND ${CMAKE_COMMAND} -E remove -f "${CMAKE_BINARY_DIR}/lib/libpiclasGPU.a"
      COMMAND python3 "${_PATCH_PY}" "${_GPU_OBJ_DIR}/gpu_init.cu.obj"
      COMMAND python3 "${_PATCH_PY}" "${_GPU_OBJ_DIR}/gpu_memory.cu.obj"
      COMMAND python3 "${_PATCH_PY}" "${_GPU_OBJ_DIR}/particle_push.cu.obj"
      COMMENT "Patching COMDAT BSS sections in all CUDA objects to fix DLL init crash")

    # Build a small C-only static library (compiled by MinGW gcc, not nvcc/cl.exe)
    # providing MSVC runtime stubs that CUDA objects compiled with cl.exe need when
    # MSVC objects participate in the MinGW link (__security_check_cookie, etc.).
    ADD_LIBRARY(piclasGPUStubs STATIC ./src/gpu/msvc_stubs.c)
    SET_TARGET_PROPERTIES(piclasGPUStubs PROPERTIES LINKER_LANGUAGE C)

    # Use a MinGW-native dlltool import library instead of cudart.lib (MSVC format).
    # cudart.lib embeds cudart_static_loader.obj — an MSVC-compiled CRT static
    # initializer that calls LoadLibrary("cudart64_13.dll") during DllMain.  Under
    # GNU ld, .CRT$XCU section ordering is not guaranteed, so the fat-binary
    # registration constructors from piclasGPU.a may run before the static loader
    # has loaded the CUDA runtime, producing STATUS_DLL_INIT_FAILED (0xC0000142).
    # A dlltool-generated libcudart.dll.a puts cudart64_13.dll in the PE IAT so
    # Windows loads it before any DllMain/constructor runs — ordering is resolved
    # by the loader, not by .CRT$XCU index.
    SET(_CUDA_CUDART_IMP "${CMAKE_BINARY_DIR}/libcudart.dll.a")
    IF(NOT EXISTS "${_CUDA_CUDART_IMP}")
      MESSAGE(STATUS "Generating MinGW import library for cudart64_13.dll ...")
      FIND_PROGRAM(_GENDEF  gendef  PATHS C:/msys64/ucrt64/bin NO_DEFAULT_PATH)
      FIND_PROGRAM(_DLLTOOL dlltool PATHS C:/msys64/ucrt64/bin NO_DEFAULT_PATH)
      # cudart64_13.dll lives in bin\x64\ on CUDA 13.x (not bin\ directly)
      SET(_CUDART_DLL "${CUDAToolkit_BIN_DIR}/cudart64_13.dll")
      IF(NOT EXISTS "${_CUDART_DLL}")
        SET(_CUDART_DLL "${CUDAToolkit_BIN_DIR}/x64/cudart64_13.dll")
      ENDIF()
      EXECUTE_PROCESS(
        COMMAND "${_GENDEF}" "${_CUDART_DLL}"
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        RESULT_VARIABLE _GENDEF_RC)
      IF(NOT _GENDEF_RC EQUAL 0)
        MESSAGE(FATAL_ERROR "gendef failed (rc=${_GENDEF_RC}) on ${_CUDART_DLL}")
      ENDIF()
      EXECUTE_PROCESS(
        COMMAND "${_DLLTOOL}" -d "${CMAKE_BINARY_DIR}/cudart64_13.def"
                              -l "${_CUDA_CUDART_IMP}"
                              -D cudart64_13.dll
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        RESULT_VARIABLE _DLLTOOL_RC)
      IF(NOT _DLLTOOL_RC EQUAL 0)
        MESSAGE(FATAL_ERROR "dlltool failed (rc=${_DLLTOOL_RC}) creating libcudart.dll.a")
      ENDIF()
      MESSAGE(STATUS "  MinGW cudart import lib: ${_CUDA_CUDART_IMP}")
    ENDIF()
    TARGET_LINK_LIBRARIES(piclasGPU PRIVATE "${_CUDA_CUDART_IMP}")
    # Do NOT add GPU libs to the global linkedlibs variable — linkedlibs is applied to
    # every executable (incl. post-processing tools like piclas2vtk) by the ADD_EXEC macro.
    # GPU libraries are instead linked explicitly into only the targets that need them
    # (libpiclasshared and piclas) via TARGET_LINK_LIBRARIES below.
  ELSE()
    TARGET_LINK_LIBRARIES(piclasGPU PRIVATE CUDA::cudart_static)
    # Same rationale: add GPU to specific targets only, not the global linkedlibs.
  ENDIF()
ENDIF()

# we link the statically built libs
ADD_LIB_SHARED(libpiclasshared ./src/piclaslib.f90)
SET_TARGET_PROPERTIES(libpiclasshared PROPERTIES OUTPUT_NAME "libpiclas")
ADD_DEPENDENCIES(libpiclasshared libpiclasstatic userblocklib stacksizelib globlib memusagelib ${INTERNALLIBS})
IF(WIN32 AND CMAKE_CXX_COMPILER_ID MATCHES "GNU" AND PICLAS_USE_GPU)
  # CUDA .obj files compiled with cl.exe as host contain COFF .drectve sections
  # with /DEFAULTLIB:cudart and /DEFAULTLIB:cudadevrt directives.  GNU ld processes
  # these as -lcudart / -lcudadevrt at link time.
  # Search order: CMAKE_BINARY_DIR first (has libcudart.dll.a), then CUDAToolkit_LIBRARY_DIR
  # (has cudadevrt.lib).  This ensures -lcudart resolves to the MinGW import library
  # rather than cudart.lib (MSVC static loader).
  # Force piclasGPUStubs into the link with --whole-archive so that MSVC security
  # stubs and __local_stdio_printf_options are unconditionally present, regardless
  # of library scan order.  libcudart.dll.a may be seen twice (full path + -lcudart
  # from .drectve), so --allow-multiple-definition prevents duplicate-symbol errors.
  ADD_DEPENDENCIES(libpiclasshared piclasGPUStubs)
  TARGET_LINK_LIBRARIES(libpiclasshared PRIVATE piclasGPUStubs piclasGPU "${_CUDA_CUDART_IMP}")
  TARGET_LINK_OPTIONS(libpiclasshared PRIVATE
    "-L${CMAKE_BINARY_DIR}"
    "-L${CUDAToolkit_LIBRARY_DIR}"
    "-Wl,--whole-archive,$<TARGET_FILE:piclasGPUStubs>,--no-whole-archive"
    "-Wl,--allow-multiple-definition"
    # Suppress MSVC-mangled and MSVC CRT symbols from CUDA objects (.drectve EXPORTS)
    # being auto-exported from libpiclas.dll.  CUDA host stubs and cudart objects embed
    # /EXPORT: directives for math/CRT functions (trunc, fabsf, _vfprintf_l, …) that
    # are only DLL imports in our link — --export-all-symbols + undefined import =
    # "cannot export X: symbol not defined" error.  Excluding these archives from
    # auto-export suppresses the spurious exports without hiding the GPU API functions
    # (piclas_gpu_init etc.) which are internal to the DLL and need no export entry.
    # IMPORTANT: gfortran -Wl,... splits on commas, so multi-archive --exclude-libs
    # must use = (option=value) and : (colon, not comma) as the list delimiter.
    "-Wl,--exclude-libs=libpiclasGPU.a:libcudart.dll.a:cudadevrt.lib")
  # The .voltbl section (MSVC volatile-metadata / Control-Flow-Guard table) placed
  # by MSVC-compiled CUDA objects is assigned an address outside the normal DLL
  # address range by GNU ld, producing a malformed PE that Windows refuses to load
  # (STATUS_INVALID_IMAGE_FORMAT).  Strip it post-link with objcopy.
  ADD_CUSTOM_COMMAND(TARGET libpiclasshared POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E echo "Stripping .voltbl from libpiclas.dll"
    COMMAND C:/msys64/ucrt64/bin/objcopy.exe --remove-section=.voltbl
            $<TARGET_FILE:libpiclasshared>
    COMMENT "Remove .voltbl MSVC guard section from libpiclas.dll")
ELSEIF(PICLAS_USE_GPU)
  # Non-Windows GPU: link piclasGPU and CUDA runtime directly into libpiclasshared.
  TARGET_LINK_LIBRARIES(libpiclasshared PRIVATE piclasGPU CUDA::cudart_static)
ENDIF()
ADD_EXEC(piclas ./src/piclas.f90)
ADD_DEPENDENCIES(piclas libpiclasstatic userblocklib stacksizelib globlib memusagelib ${INTERNALLIBS})
IF(WIN32 AND CMAKE_CXX_COMPILER_ID MATCHES "GNU" AND PICLAS_USE_GPU)
  # piclas.exe on Windows links the GPU archives directly (MPI transitive-export workaround).
  # CMAKE_BINARY_DIR first so -lcudart resolves to libcudart.dll.a (MinGW import lib)
  # rather than cudart.lib (MSVC static loader).
  TARGET_LINK_LIBRARIES(piclas piclasGPUStubs piclasGPU "${_CUDA_CUDART_IMP}")
  TARGET_LINK_OPTIONS(piclas PRIVATE
    "-L${CMAKE_BINARY_DIR}"
    "-L${CUDAToolkit_LIBRARY_DIR}"
    "-Wl,--whole-archive,$<TARGET_FILE:piclasGPUStubs>,--no-whole-archive"
    "-Wl,--allow-multiple-definition"
    "-Wl,--exclude-libs=libpiclasGPU.a:libcudart.dll.a:cudadevrt.lib")
ELSEIF(PICLAS_USE_GPU)
  # Non-Windows GPU: link piclasGPU and CUDA runtime directly into piclas.
  TARGET_LINK_LIBRARIES(piclas piclasGPU CUDA::cudart_static)
ENDIF()

# special compiler flags to avoid warnings for empty functions of testcase.f90 and overwrite of intrinsic abort in globals.f90
IF (CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  SET_SOURCE_FILES_PROPERTIES(${CMAKE_CURRENT_SOURCE_DIR}/src/globals/globals.f90 PROPERTIES COMPILE_FLAGS "-Wno-intrinsic-shadow")
ENDIF()

# =========================================================================
# EXTRAE instrumentation
# =========================================================================
IF(PICLAS_EXTRAE)
  # MPI+OpenMP
  #SET(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -lompitracef -L$ENV{EXTRAE_HOME}/lib")
  # only MPI
  SET(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -lmpitracef -L$ENV{EXTRAE_HOME}/lib")
  # change binary name by adding the suffix '_extrae'
  SET_TARGET_PROPERTIES(piclas PROPERTIES OUTPUT_NAME "piclas_extrae")
ENDIF(PICLAS_EXTRAE)

# =========================================================================
# Shared memory debug flags
# =========================================================================
SET(PICLAS_DEBUG_MEMORY OFF CACHE BOOL "Output shared memory window sizes. 'USE MOD_MPI_Shared' cannot be used together with the 'ONLY:' statement in this case!")
IF(PICLAS_DEBUG_MEMORY)
  SET (CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -DDEBUG_MEMORY")
ENDIF()

# =========================================================================
# MPI_WAIT measurement and output
# =========================================================================
CMAKE_DEPENDENT_OPTION(PICLAS_MEASURE_MPI_WAIT "Output measured and accumulated wall time during MPI_WAIT for each process." OFF "LIBS_USE_MPI" OFF)
IF(LIBS_USE_MPI)
  IF(PICLAS_MEASURE_MPI_WAIT)
    SET (CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -DMEASURE_MPI_WAIT")
    MESSAGE(STATUS "Activated measurement of MPI_WAIT [-DMEASURE_MPI_WAIT]")
  ENDIF()
ENDIF()

# =========================================================================
# Ctags
# =========================================================================
OPTION(PICLAS_CTAGS "Use Ctags" ON)
IF(PICLAS_CTAGS)
  MARK_AS_ADVANCED(FORCE CTAGS_PATH)
  FIND_PROGRAM(CTAGS_PATH ctags-exuberant)
  IF(CTAGS_PATH)
    SET(             EQNS_WO_ACTUAL ${EQNSYSTEMS})
    LIST(REMOVE_ITEM EQNS_WO_ACTUAL ${PICLAS_EQNSYSNAME})
    SET(EXLUDES "")
    FOREACH(item ${EQNS_WO_ACTUAL})
       SET(EXLUDES "--exclude=src/equations/${item}/*" ${EXLUDES})
    ENDFOREACH()

    ADD_CUSTOM_COMMAND(OUTPUT ctags.txt COMMAND cd ${CMAKE_CURRENT_SOURCE_DIR} && ${CTAGS_PATH} -R --fortran-kinds=+i+L -f ctags.txt ${EXLUDES} src && ${CTAGS_PATH} -R --fortran-kinds=+i+L -f ctags.txt ${EXLUDES} --append src/posti && ln -sf ctags.txt tags)
    ADD_CUSTOM_TARGET(tags DEPENDS ctags.txt)
    MESSAGE(STATUS "Found ctags: ${CTAGS_PATH}")
    ADD_DEPENDENCIES(piclas tags)
  ENDIF(CTAGS_PATH)
ENDIF(PICLAS_CTAGS)

# =========================================================================
# Code Coverage
# =========================================================================
OPTION(PICLAS_CODE_COVERAGE "Generate additional files for code coverage" OFF)
MARK_AS_ADVANCED(FORCE PICLAS_CODE_COVERAGE)
# Get environment variable, only strings so use "ON"
IF("$ENV{PICLAS_CODE_COVERAGE}" STREQUAL "ON")
  SET(PICLAS_CODE_COVERAGE "$ENV{PICLAS_CODE_COVERAGE}")
ENDIF()
# set coverage flag for compiler
IF(PICLAS_CODE_COVERAGE)
  SET (CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} --coverage")
  MESSAGE(STATUS "Compiling for code coverage")
ENDIF()