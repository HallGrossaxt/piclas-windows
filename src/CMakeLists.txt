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
# GPU acceleration — CUDA shared library (libpiclasGPU.dll)
#
# Built as SHARED so it can be loaded explicitly via LoadLibrary() from
# gpu_loader.c after main() has started.  Embedding CUDA objects in
# libpiclas.dll caused a Windows DLL loader deadlock: the fat-binary
# registration static initialiser ran during libpiclas.dll's DllMain
# (loader lock held) and CUDA's driver threads also needed the loader
# lock → process hung before main() ever ran.
# =========================================================================
IF(PICLAS_USE_GPU)
  FILE(GLOB gpuCU ./src/gpu/*.cu)
  # On Windows+MinGW, CMake's CUDA SHARED link rule uses MSVC linker syntax:
  #   ld.exe /nologo /out:<TARGET> /implib:<IMPLIB> /dll /MANIFEST:EMBED,ID=2 kernel32.lib ...
  # because nvcc uses cl.exe as host compiler and CMake picks the MSVC link template.
  # ld.exe does not understand MSVC flags → fatal errors on every option.
  # Override the link rule to use MinGW gcc, which generates correct GNU ld flags.
  # This override only affects piclasGPU (the sole CUDA SHARED target).
  IF(WIN32 AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    # Linking MSVC-compiled CUDA objects with MinGW ld.exe fails in two ways:
    #   1. MSVC CRT (printf, __local_stdio_printf_options ...) is ABI-incompatible with
    #      MinGW UCRT64 wrappers → "undefined reference to printf/fprintf" at link.
    #   2. CUDA inline host functions (sin, cos, dim3::...) appear in .drectve as DLL
    #      exports but live only in cudart64_13.dll — MinGW ld reports "cannot export:
    #      symbol not defined" because it cannot create forwarder re-exports.
    # Fix: use nvcc as the GPU-DLL linker.  nvcc calls MSVC link.exe which:
    #   - resolves MSVC CRT (printf etc.) correctly;
    #   - creates forwarder re-exports from cudart64_13.dll for math overloads;
    #   - handles COMDAT correctly (no .bss ACCESS VIOLATION at DLL load time).
    # "-cudart shared" → cudart64_13.dll imported via the PE IAT; nvcc resolves
    # cudart.lib automatically from the CUDA toolkit.  No <LINK_LIBRARIES> or
    # <LINK_FLAGS> in the template so MinGW-format archives and -Wl, options
    # do not reach MSVC link.exe.
    SET(CMAKE_CUDA_STANDARD_LIBRARIES "")
    SET(CMAKE_CUDA_IMPLICIT_LINK_LIBRARIES "")
    # -ccbin tells nvcc where cl.exe lives so it can locate link.exe and MSVC libs.
    # CMake adds -ccbin automatically for compile rules but not for our custom link
    # template, so we must supply it explicitly using CMAKE_CUDA_HOST_COMPILER.
    #
    # "-cudart none": do NOT let nvcc auto-add cudadevrt.lib / cudart.lib; some
    # of those libraries force /DEFAULTLIB:LIBCMT (static CRT) which conflicts with
    # our /MD objects and causes link.exe to switch to libucrt.lib (static UCRT).
    # Static UCRT does not define __imp_fminf/__imp_cbrtf/... DLL-import stubs, so
    # all C99 float math functions become unresolved (LNK2019).
    # Instead we add cudart.lib explicitly and suppress the static CRT default libs.
    #
    # /NODEFAULTLIB:LIBCMT   — suppress static MSVC main CRT (forced by cudadevrt)
    # /NODEFAULTLIB:libucrt  — suppress static UCRT    (forces libucrt instead of ucrt.lib)
    # /DEFAULTLIB:ucrt       — add dynamic UCRT import lib (provides __imp_fminf etc.)
    # cudart.lib             — MSVC import library for cudart64_13.dll
    #
    # LIBPATH spaces problem: CUDAToolkit_LIBRARY_DIR is usually under
    # "C:/Program Files/NVIDIA GPU Computing Toolkit/..." which contains spaces.
    # When Ninja wraps the link command in  cmd.exe /C "..."  the inner quotes
    # around  /LIBPATH:"..."  are consumed by cmd.exe's quote parser; nvcc then
    # receives the argument with its quotes stripped and passes it to link.exe
    # without re-quoting → link.exe splits the path at the first space and
    # reports LNK1181 "Files\NVIDIA.obj" (stray object file name).
    # Fix: copy cudart.lib from the CUDA toolkit into the build dir at configure
    # time.  The build dir path (CMAKE_BINARY_DIR) is assumed to have no spaces.
    # No quoting is needed for the resulting /LIBPATH: argument.
    SET(_CUDA_LOCAL_LIB_DIR "${CMAKE_BINARY_DIR}/lib/cuda")
    FILE(MAKE_DIRECTORY "${_CUDA_LOCAL_LIB_DIR}")
    FILE(COPY "${CUDAToolkit_LIBRARY_DIR}/cudart.lib"
         DESTINATION "${_CUDA_LOCAL_LIB_DIR}")
    MESSAGE(STATUS "  CUDA cudart.lib staged: ${_CUDA_LOCAL_LIB_DIR}/cudart.lib")
    #
    # CACHE INTERNAL "" FORCE is required: ENABLE_LANGUAGE(CUDA) loads the CUDA
    # platform module which stores CMAKE_CUDA_CREATE_SHARED_LIBRARY as a CACHE
    # INTERNAL variable (with FORCE).  A plain SET() cannot override a cached
    # value — it is silently ignored — so the platform default "-cudart shared"
    # survives into the generated Ninja rule, omitting all /DEFAULTLIB flags and
    # causing LNK2019 on __imp_fminf/__imp_cbrtf/... (31 symbols).
    # Using CACHE INTERNAL FORCE here runs after the platform SET and wins.
    SET(CMAKE_CUDA_CREATE_SHARED_LIBRARY
        "<CMAKE_CUDA_COMPILER> -shared -cudart none -ccbin \"${CMAKE_CUDA_HOST_COMPILER}\" -o <TARGET> <OBJECTS> -Xlinker /LIBPATH:${_CUDA_LOCAL_LIB_DIR} -Xlinker cudart.lib -Xlinker /NODEFAULTLIB:LIBCMT -Xlinker /NODEFAULTLIB:LIBCMTD -Xlinker /NODEFAULTLIB:libucrt -Xlinker /DEFAULTLIB:ucrt"
        CACHE INTERNAL "CUDA SHARED library link rule (Windows MinGW+MSVC host — overrides platform default)" FORCE)
  ENDIF()
  ADD_LIBRARY(piclasGPU SHARED ${gpuCU})
  SET_TARGET_PROPERTIES(piclasGPU PROPERTIES
    OUTPUT_NAME              "piclasGPU"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    CUDA_SEPARABLE_COMPILATION  OFF
    # Prevent CMake from adding an automatic device-link step for SHARED targets.
    # All .cu TUs are self-contained (no inter-TU __device__ calls), so device
    # symbols are resolved at compile time.  Without this, CMake generates
    # cmake_device_link.obj whose .drectve sections (MSVC-style library refs) are
    # processed by MinGW ld.exe and cause "cannot find comdlg32.lib" fatal errors.
    CUDA_RESOLVE_DEVICE_SYMBOLS OFF
    CUDA_ARCHITECTURES          "${CMAKE_CUDA_ARCHITECTURES}"
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
  IF(WIN32 AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    # cl.exe compile flags (passed to the MSVC host compiler via nvcc's -Xcompiler).
    # /GS-                : disable buffer security check (__security_check_cookie not emitted).
    # /MD                 : use MSVC DLL CRT (ucrtbase.dll / msvcrt.dll).
    # /Zc:threadSafeInit- : disable thread-safe static init (avoids _Init_thread_header refs).
    # Comma-list keeps flags as one nvcc token (spaces make nvcc treat /MD as an input file).
    TARGET_COMPILE_OPTIONS(piclasGPU PRIVATE
      $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=/GS-,/MD,/Zc:threadSafeInit->)
    # Trigger PICLAS_GPU_API = __declspec(dllexport) in piclas_gpu.h for our 5 API functions.
    TARGET_COMPILE_DEFINITIONS(piclasGPU PRIVATE PICLAS_BUILDING_GPU_DLL)

    # Locate cudart64_13.dll for the POST_BUILD copy.
    # libpiclasGPU.dll imports cudart64_13.dll via its PE IAT ("-cudart shared" in the
    # link template); Windows must find it when LoadLibraryA("libpiclasGPU.dll") runs.
    SET(_CUDART_DLL "${CUDAToolkit_BIN_DIR}/cudart64_13.dll")
    IF(NOT EXISTS "${_CUDART_DLL}")
      SET(_CUDART_DLL "${CUDAToolkit_BIN_DIR}/x64/cudart64_13.dll")
    ENDIF()
    IF(NOT EXISTS "${_CUDART_DLL}")
      MESSAGE(FATAL_ERROR "cudart64_13.dll not found; searched ${CUDAToolkit_BIN_DIR} and x64/")
    ENDIF()
    ADD_CUSTOM_COMMAND(TARGET piclasGPU POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_CUDART_DLL}" "${CMAKE_BINARY_DIR}/bin/"
      COMMENT "Copying cudart64_13.dll to bin/")

    # piclasGPULoader: MinGW-compiled C stub library linked into libpiclas.dll.
    # Provides piclas_gpu_load_library() + forwarding stubs (piclas_gpu_init etc.)
    # that resolve to libpiclasGPU.dll via GetProcAddress after explicit LoadLibrary.
    # No CUDA symbols or MSVC CRT dependencies — plain Windows API only.
    ADD_LIBRARY(piclasGPULoader STATIC ./src/gpu/gpu_loader.c)
    SET_TARGET_PROPERTIES(piclasGPULoader PROPERTIES LINKER_LANGUAGE C)

    # Do NOT add GPU libs to the global linkedlibs variable — see comment below.
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
  # libpiclas.dll does NOT link CUDA objects or cudart — those are in libpiclasGPU.dll,
  # which is loaded explicitly by gpu_loader.c via LoadLibrary() after main() starts.
  # Only the forwarding-stub loader is linked here; no CUDA IAT entries in libpiclas.dll.
  ADD_DEPENDENCIES(libpiclasshared piclasGPULoader piclasGPU)
  TARGET_LINK_LIBRARIES(libpiclasshared PRIVATE piclasGPULoader)
ELSEIF(PICLAS_USE_GPU)
  # Non-Windows GPU: link piclasGPU and CUDA runtime directly into libpiclasshared.
  TARGET_LINK_LIBRARIES(libpiclasshared PRIVATE piclasGPU CUDA::cudart_static)
ENDIF()
ADD_EXEC(piclas ./src/piclas.f90)
ADD_DEPENDENCIES(piclas libpiclasstatic userblocklib stacksizelib globlib memusagelib ${INTERNALLIBS})
# piclas-win: this is an unofficial, modified Windows port of PICLas (GPLv3 §5a — mark the
# modified work and avoid confusion with the official upstream "piclas" binary). Build the
# executable as "piclas-win" (piclas-win.exe on Windows). The CMake target stays "piclas".
SET_TARGET_PROPERTIES(piclas PROPERTIES OUTPUT_NAME "piclas-win")
# GPU on Windows: piclas.exe does not link CUDA objects or cudart directly.
# libpiclasGPU.dll is loaded via LoadLibrary in gpu_loader.c (part of libpiclas.dll).
# No CUDA symbols in piclas.exe's IAT — no loader deadlock.
IF(NOT WIN32 AND PICLAS_USE_GPU)
  # Non-Windows: link CUDA runtime directly into the executable.
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