module irf_route_module

!numeric type
USE nrtype
! data type
USE dataTypes,          only : STRFLX         ! fluxes in each reach
USE dataTypes,          only : RCHTOPO        ! Network topology
! global parameters
USE public_var,         only : realMissing    ! missing value for real number
USE public_var,         only : integerMissing ! missing value for integer number
! utilities
USE time_utils_module,  only : elapsedSec     ! calculate the elapsed time
USE nr_utility_module,  only : arth

! privary
implicit none
private

public::irf_route

contains

  ! *********************************************************************
  ! subroutine: perform network UH routing
  ! *********************************************************************
  subroutine irf_route(&
                       iEns,         &  ! input: index of runoff ensemble to be processed
                       ixDesire,     &  ! input: reachID to be checked by on-screen pringing
                       NETOPO_in,    &  ! input: reach topology data structure
                       RCHFLX_out,   &  ! inout: reach flux data structure
                       ierr, message,&  ! output: error control
                       ixSubRch)        ! optional input: subset of reach indices to be processed
  ! ----------------------------------------------------------------------------------------
  ! Purpose:
  !
  !   Convolute routed basisn flow volume at top of each of the upstream segment at one time step and at each segment
  !
  ! ----------------------------------------------------------------------------------------

  implicit none
  ! Input
  integer(I4B), intent(in)                  :: iEns                 ! runoff ensemble to be routed
  integer(I4B), intent(in)                  :: ixDesire             ! index of the reach for verbose output
  type(RCHTOPO),intent(in),    allocatable  :: NETOPO_in(:)         ! River Network topology
  ! inout
  TYPE(STRFLX), intent(inout), allocatable  :: RCHFLX_out(:,:)      ! Reach fluxes (ensembles, space [reaches]) for decomposed domains
  ! Output
  integer(i4b), intent(out)                 :: ierr                 ! error code
  character(*), intent(out)                 :: message              ! error message
  ! input (optional)
  integer(i4b), intent(in),   optional      :: ixSubRch(:)          ! subset of reach indices to be processed
  ! Local variables to
  INTEGER(I4B)                              :: nSeg                 ! number of reach segments in the network
  INTEGER(I4B)                              :: iSeg, jSeg           ! reach segment index
  logical(lgt), allocatable                 :: doRoute(:)           ! logical to indicate which reaches are processed
  character(len=strLen)                     :: cmessage             ! error message from subroutine
  integer*8                                 :: cr,startTime,endTime ! date/time for the start and end of the initialization
  real(dp)                                  :: elapsedTime          ! elapsed time for the process

  ! initialize error control
  ierr=0; message='irf_route/'

  call system_clock(count_rate=cr)
  call system_clock(startTime)

  ! check
  if (size(NETOPO_in)/=size(RCHFLX_out(iens,:))) then
   ierr=20; message=trim(message)//'sizes of NETOPO and RCHFLX mismatch'; return
  endif

  ! Initialize CHEC_IRF to False.
  RCHFLX_out(iEns,:)%CHECK_IRF=.False.

  nSeg = size(RCHFLX_out(iens,:))

  allocate(doRoute(nSeg), stat=ierr)

  if (present(ixSubRch))then
   doRoute(:)=.false.
   doRoute(ixSubRch) = .true. ! only subset of reaches are on
  else
   doRoute(:)=.true. ! every reach is on
  endif

  ! route streamflow through the river network
  do iSeg=1,nSeg

   jSeg = NETOPO_in(iSeg)%RHORDER

   if (.not. doRoute(jSeg)) cycle

   call segment_irf(iEns, jSeg, ixDesire, NETOPO_IN, RCHFLX_out, ierr, message)
   if(ierr/=0)then; message=trim(message)//trim(cmessage); return; endif

  end do

  call system_clock(endTime)
  elapsedTime = real(endTime-startTime, kind(dp))/real(cr)
!   write(*,"(A,1PG15.7,A)") '  elapsed [route/irf] = ', elapsedTime, ' s'

 end subroutine irf_route


 ! *********************************************************************
 ! subroutine: perform one segment route UH routing
 ! *********************************************************************
 subroutine segment_irf(&
                        ! input
                        iEns,       &    ! input: index of runoff ensemble to be processed
                        segIndex,   &    ! input: index of runoff ensemble to be processed
                        ixDesire,   &    ! input: reachID to be checked by on-screen pringing
                        NETOPO_in,  &    ! input: reach topology data structure
                        ! inout
                        RCHFLX_out, &    ! inout: reach flux data structure
                        ! output
                        ierr, message)   ! output: error control

 implicit none
 ! Input
 INTEGER(I4B), intent(IN)                 :: iEns           ! runoff ensemble to be routed
 INTEGER(I4B), intent(IN)                 :: segIndex       ! segment where routing is performed
 INTEGER(I4B), intent(IN)                 :: ixDesire       ! index of the reach for verbose output
 type(RCHTOPO),intent(in),    allocatable :: NETOPO_in(:)   ! River Network topology
 ! inout
 TYPE(STRFLX), intent(inout), allocatable :: RCHFLX_out(:,:)   ! Reach fluxes (ensembles, space [reaches]) for decomposed domains
 ! Output
 integer(i4b), intent(out)                :: ierr           ! error code
 character(*), intent(out)                :: message        ! error message
 ! Local variables to
 type(STRFLX), allocatable                :: uprflux(:)     ! upstream Reach fluxes
 INTEGER(I4B)                             :: nUps           ! number of upstream segment
 INTEGER(I4B)                             :: iUps           ! upstream reach index
 INTEGER(I4B)                             :: iRch_ups       ! index of upstream reach in NETOPO
 INTEGER(I4B)                             :: ntdh           ! number of time steps in IRF
 character(len=strLen)                    :: cmessage       ! error message from subroutine

 ! initialize error control
 ierr=0; message='segment_irf/'

 ! route streamflow through the river network
  if (.not.allocated(RCHFLX_out(iens,segIndex)%QFUTURE_IRF))then

   ntdh = size(NETOPO_in(segIndex)%UH)

   allocate(RCHFLX_out(iens,segIndex)%QFUTURE_IRF(ntdh), stat=ierr, errmsg=cmessage)
   if(ierr/=0)then; message=trim(message)//trim(cmessage)//': RCHFLX_out(iens,segIndex)%QFUTURE_IRF'; return; endif

   RCHFLX_out(iens,segIndex)%QFUTURE_IRF(:) = 0._dp

  end if

  ! identify number of upstream segments of the reach being processed
  nUps = size(NETOPO_in(segIndex)%UREACHI)

  allocate(uprflux(nUps), stat=ierr, errmsg=cmessage)
  if(ierr/=0)then; message=trim(message)//trim(cmessage)//': uprflux'; return; endif

  if (nUps>0) then
    do iUps = 1,nUps
      iRch_ups = NETOPO_in(segIndex)%UREACHI(iUps)      !  index of upstream of segIndex-th reach
      uprflux(iUps) = RCHFLX_out(iens,iRch_ups)
    end do
  endif

  ! perform river network UH routing
  call conv_upsbas_qr(NETOPO_in(segIndex)%UH,    &    ! input: reach unit hydrograph
                      uprflux,                   &    ! input: upstream reach fluxes
                      RCHFLX_out(iens,segIndex), &    ! inout: updated fluxes at reach
                      ierr, message)                  ! output: error control
  if(ierr/=0)then; message=trim(message)//trim(cmessage); return; endif

  ! Check True since now this reach now routed
  RCHFLX_out(iEns,segIndex)%CHECK_IRF=.True.

  ! check
  if(NETOPO_in(segIndex)%REACHIX == ixDesire)then
   print*, 'RCHFLX_out(iens,segIndex)%BASIN_QR(1),RCHFLX_out(iens,segIndex)%REACH_Q_IRF = ', &
            RCHFLX_out(iens,segIndex)%BASIN_QR(1),RCHFLX_out(iens,segIndex)%REACH_Q_IRF
  endif

 end subroutine segment_irf


 ! *********************************************************************
 ! subroutine: Compute delayed runoff from the upstream segments
 ! *********************************************************************
 subroutine conv_upsbas_qr(&
                           ! input
                           reach_uh,   &    ! input: reach unit hydrograph
                           rflux_ups,  &    ! input: upstream reach fluxes
                           rflux,      &    ! input: input flux at reach
                           ierr, message)   ! output: error control
 ! ----------------------------------------------------------------------------------------
 ! Purpose:
 !
 !   Convolute routed basisn flow volume at top of each of the upstream segment at one time step and at each segment
 !
 ! ----------------------------------------------------------------------------------------

 implicit none
 ! Input
 real(dp),     intent(in)               :: reach_uh(:)  ! reach unit hydrograph
 type(STRFLX), intent(in)               :: rflux_ups(:) ! upstream Reach fluxes
 ! inout
 type(STRFLX), intent(inout)            :: rflux        ! current Reach fluxes
 ! Output
 integer(i4b), intent(out)              :: ierr         ! error code
 character(*), intent(out)              :: message      ! error message
 ! Local variables to
 real(dp)                               :: q_upstream   ! total discharge at top of the reach being processed
 INTEGER(I4B)                           :: nTDH         ! number of UH data
 INTEGER(I4B)                           :: iTDH         ! index of UH data (i.e.,future time step)
 INTEGER(I4B)                           :: nUps         ! number of all upstream segment
 INTEGER(I4B)                           :: iUps         ! loop indices for u/s reaches

 ! initialize error control
 ierr=0; message='conv_upsbas_qr/'

 ! identify number of upstream segments of the reach being processed
 nUps = size(rflux_ups)

 q_upstream = 0.0_dp
 if(nUps>0)then
   do iUps = 1,nUps
     ! Find out total q at top of a segment
     q_upstream = q_upstream + rflux_ups(iUps)%REACH_Q_IRF
   end do
 endif

 ! place a fraction of runoff in future time steps
 nTDH = size(reach_uh) ! identify the number of future time steps of UH for a given segment
 do iTDH=1,nTDH
   rflux%QFUTURE_IRF(iTDH) = rflux%QFUTURE_IRF(iTDH) &
                             + reach_uh(iTDH)*q_upstream
 enddo

 ! Add local routed flow
 rflux%REACH_Q_IRF = rflux%QFUTURE_IRF(1) + rflux%BASIN_QR(1)

 ! move array back   use eoshift
 rflux%QFUTURE_IRF=eoshift(rflux%QFUTURE_IRF,shift=1)

 end subroutine conv_upsbas_qr

end module irf_route_module

