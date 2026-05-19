# =========================================================================
# DMD tool
# =========================================================================
SET(TOOL_NAME "dmd")
SET(TOOL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/posti/dmd")

MESSAGE(STATUS "Posti: building ${TOOL_NAME} tool.")
INCLUDE_DIRECTORIES( ${TOOL_DIR})

FILE(GLOB ${TOOL_NAME}F90 ${TOOL_DIR}/dmd_main.f90
                          ${TOOL_DIR}/dmd_vars.f90
                          ${TOOL_DIR}/maxwell/equationDmd.f90
                          ${TOOL_DIR}/maxwell/equationDmd_vars.f90)

ADD_LIBRARY(${TOOL_NAME}libF90 OBJECT ${${TOOL_NAME}F90})
SET_TARGET_PROPERTIES(${TOOL_NAME}libF90 PROPERTIES COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS}
                                                    COMPILE_OPTIONS "-fPIC"
                                                    CMAKE_POSITION_INDEPENDENT_CODE ON)
ADD_LIBRARY(${TOOL_NAME}lib STATIC $<TARGET_OBJECTS:${TOOL_NAME}libF90>)
ADD_DEPENDENCIES(${TOOL_NAME}libF90 libpiclasshared)

# When using Ninja, CMake tries to parallelize the build resulting in missing module files. Add a dummy target to ensure synchronization
ADD_CUSTOM_TARGET(${TOOL_NAME}target)
ADD_DEPENDENCIES(${TOOL_NAME}target libpiclasshared)
ADD_DEPENDENCIES(${TOOL_NAME}libF90 ${TOOL_NAME}target)

# Standalone Posti executable
# Windows/MinGW linker order fix (two constraints must hold simultaneously):
#  (1) mpi_f08.o BEFORE liblibpiclas.dll.a: the DLL import stub contains thunk stubs for every
#      exported symbol, including __mpi_f08_MOD_*. If liblibpiclas.dll.a is processed first and
#      dmdlib references any MPI-f08 symbol, the thunk is pulled in. mpi_f08.o then redefines the
#      same symbol -> "multiple definition" error. Placing mpi_f08.o first prevents the thunk from
#      being pulled in (symbol already defined).
#  (2) libdmdlib.a BEFORE libopenblas.dll.a: dmd_main.f90 calls dgesdd_, zgeev_, zgesv_ (LAPACK).
#      GNU ld resolves archive symbols only when a pending reference exists; if openblas precedes
#      dmdlib, no references are pending yet and the symbols are not extracted -> undefined.
# Achieved order: mpi_f08.o -> dmdlib -> libpiclasshared -> libmsmpi -> libhdf5* -> libopenblas
# ${linkedlibs} = mpi_f08.o libmsmpi libhdf5* libopenblas  (mpi_f08.o always first; see SetLibraries.cmake)
ADD_EXECUTABLE(${TOOL_NAME} ${TOOL_DIR}/dmd.f90)
IF(WIN32)
  LIST(GET linkedlibs 0 _dmd_mpi_f08_obj)
  LIST(SUBLIST linkedlibs 1 -1 _dmd_linkedlibs_tail)
  TARGET_LINK_LIBRARIES(${TOOL_NAME} ${_dmd_mpi_f08_obj} ${TOOL_NAME}lib libpiclasshared ${_dmd_linkedlibs_tail})
  SET_TARGET_PROPERTIES(${TOOL_NAME} PROPERTIES COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS}
                                                CMAKE_POSITION_INDEPENDENT_CODE ON
                                                LINKER_LANGUAGE Fortran)
ELSE()
  TARGET_LINK_LIBRARIES(${TOOL_NAME} ${TOOL_NAME}lib libpiclasshared)
  SET_TARGET_PROPERTIES(${TOOL_NAME} PROPERTIES COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS}
                                                COMPILE_OPTIONS "-fPIC"
                                                CMAKE_POSITION_INDEPENDENT_CODE ON
                                                LINKER_LANGUAGE Fortran)
ENDIF()
ADD_DEPENDENCIES(${TOOL_NAME} ${TOOL_NAME}lib libpiclasshared)
