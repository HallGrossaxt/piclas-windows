!*****************************************************************************
!*                        ANALYSIS PERFORMANCE TOOLS                         *
!*                                   Extrae                                  *
!*              Instrumentation package for parallel applications            *
!*****************************************************************************
!*     ___     This library is free software; you can redistribute it and/or *
!*    /  __         modify it under the terms of the GNU LGPL as published   *
!*   /  /  _____    by the Free Software Foundation; either version 2.1      *
!*  /  /  /     \   of the License, or (at your option) any later version.   *
!* (  (  ( B S C )                                                           *
!*  \  \  \_____/   This library is distributed in hope that it will be      *
!*   \  \__         useful but WITHOUT ANY WARRANTY; without even the        *
!*    \___          implied warranty of MERCHANTABILITY or FITNESS FOR A     *
!*                  PARTICULAR PURPOSE. See the GNU LGPL for more details.   *
!*                                                                           *
!* You should have received a copy of the GNU Lesser General Public License  *
!* along with this library; if not, write to the Free Software Foundation,   *
!* Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA          *
!* The GNU LEsser General Public License is contained in the file COPYING.   *
!*                                 ---------                                 *
!*   Barcelona Supercomputing Center - Centro Nacional de Supercomputacion   *
!*****************************************************************************

!* -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
!| @file: $HeadURL: https://svn.bsc.es/repos/ptools/extrae/branches/2.3/include/extrae_module.f $
!| @last_commit: $Date: 2013-05-16 12:34:14 +0200 (dj, 16 mai 2013) $
!| @version:     $Revision: 1724 $
!* -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

      module EXTRAE_MODULE
      USE MOD_Globals_Vars, ONLY: i4,i8

      integer(kind=i4) :: extrae_disable_all_options
      parameter (extrae_disable_all_options=0)

      integer(kind=i4) :: extrae_caller_option
      parameter (extrae_caller_option=1)

      integer(kind=i4) :: extrae_hwc_option
      parameter (extrae_hwc_option=2)

      integer(kind=i4) :: extrae_mpi_hwc_option
      parameter (extrae_mpi_hwc_option=4)

      integer(kind=i4) :: extrae_mpi_option
      parameter (extrae_mpi_option=8)

      integer(kind=i4) :: extrae_omp_option
      parameter (extrae_omp_option=16)

      integer(kind=i4) :: extrae_omp_hwc_option
      parameter (extrae_omp_hwc_option=32)

      integer(kind=i4) :: extrae_uf_hwc_option
      parameter (extrae_uf_hwc_option=64)

      integer(kind=i4) :: extrae_sampling_option
      parameter (extrae_sampling_option=128)

      integer(kind=i4) :: extrae_enable_all_options
      parameter (extrae_enable_all_options=255)

      interface

         subroutine extrae_init
         end subroutine extrae_init

         subroutine extrae_fini
         end subroutine extrae_fini

         subroutine extrae_flush
         end subroutine extrae_flush

         subroutine extrae_version (major, minor, revision)
         integer(kind=i4), intent (out) :: major
         integer(kind=i4), intent (out) :: minor
         integer(kind=i4), intent (out) :: revision
         end subroutine extrae_version

         subroutine extrae_shutdown
         end subroutine extrae_shutdown

         subroutine extrae_restart
         end subroutine extrae_restart

         subroutine extrae_event (extrae_type, extrae_value)
         integer(kind=i4), intent(in) :: extrae_type
         integer(kind=i8), intent(in) :: extrae_value
         end subroutine extrae_event

         subroutine extrae_eventandcounters (extrae_type, extrae_value)
         integer(kind=i4), intent(in) :: extrae_type
         integer(kind=i8), intent(in) :: extrae_value
         end subroutine extrae_eventandcounters


         subroutine extrae_nevent (num, extrae_types, extrae_values)
         integer(kind=i4), intent(in) :: num
         integer(kind=i4), intent(in) :: extrae_types
         integer(kind=i8), intent(in) :: extrae_values
         end subroutine extrae_nevent

         subroutine extrae_neventandcounters (num, extrae_types, &
           extrae_value)
         integer(kind=i4):: num
         integer(kind=i4):: extrae_types
         integer(kind=i8):: extrae_values
         end subroutine extrae_neventandcounters

         subroutine extrae_counters
         end subroutine extrae_counters

         subroutine extrae_previous_hwc_set
         end subroutine extrae_previous_hwc_set

         subroutine extrae_next_hwc_set
         end subroutine extrae_next_hwc_set

         subroutine extrae_set_options (options)
         integer(kind=i4), intent(in) :: options
         end subroutine extrae_set_options

         subroutine extrae_set_tracing_tasks (task_from, task_to)
         integer(kind=i4), intent(in) :: task_from
         integer(kind=i4), intent(in) :: task_to
         end subroutine extrae_set_tracing_tasks

         subroutine extrae_user_function (enter)
         integer(kind=i4), intent(in) :: enter
         end subroutine extrae_user_function

      end interface

      end module EXTRAE_MODULE
