program p2f
    use eqdsk
    use gc_terms
    use interp
    use gc_integrate 
    use read_particle_list
    use rzvv_grid
    use init_mpi
    use constants
    use write_f_rzvv
    use read_namelist
 
    implicit none
    
    integer(kind=LONG) :: i,j,k
    real :: T1, T2
    integer :: mpi_count_
    integer :: nP_wall_total, nP_bad_total, &
        nP_off_vGrid_total, nP_badWeight_total, nP_badEnergy_total, &
        nP_TookMaxStepsBeforeBounce_total, nP_mpiSum_total, &
        nP_OutsideTheBox_total
    real :: tmpDensity, TotalNumberOfParticles 

    call init_namelist () 
    call set_constants ()
    call read_geqdsk ( eqdsk_fileName, plot = .false. )
    call bCurvature ()
    call bGradient ()
    call init_interp ()
    call start_mpi ()
    call read_pl ()    
    call init_rzvv_grid ()
    call SetNormFac()

    call cpu_time (T1)

    do i=mpi_start_,mpi_end_
 
        if ( mod ( i, 100 ) == 0 .and. mpi_pId == 0 ) &
            write(*,*) nP, mpi_nP, i, p_R(i), p_z(i), p_vPer(i), p_vPar(i)

        if ( p_weight(i) > 0 ) &
            call gc_orbit ( p_R(i), p_z(i), p_vPer(i),&
                p_vPar(i), p_weight(i) , plot = plotOrbit )

    end do

#if PARALLEL==1
    call mpi_barrier ( MPI_COMM_WORLD, mpi_iErr )
#endif
    mpi_count_   = R_nBins * z_nBins * vPer_nBins * vPar_nBins

    allocate ( f_rzvv_global ( R_nBins, z_nBins, vPer_nBins, vPar_nBins ) )
#if PARALLEL==1
    call mpi_reduce ( f_rzvv, f_rzvv_global, mpi_count_, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
#else
    f_rzvv_global = f_rzvv
#endif

    f_rzvv = f_rzvv_global
    deallocate(f_rzvv_global)

#if PARALLEL==1
    call mpi_reduce ( nP_wall, nP_wall_total, 1, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
    call mpi_reduce ( nP_bad, nP_bad_total, 1, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
    call mpi_reduce ( nP_off_vGrid, nP_off_vGrid_total, 1, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
    call mpi_reduce ( nP_badWeight, nP_badWeight_total, 1, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
    call mpi_reduce ( nP_badEnergy, nP_badEnergy_total, 1, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
    call mpi_reduce ( nP_TookMaxStepsBeforeBounce, &
            nP_TookMaxStepsBeforeBounce_total, 1, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
    call mpi_reduce ( nP_mpiSum, nP_mpiSum_total, 1, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
    call mpi_reduce ( nP_OutsideTheBox, nP_OutsideTheBox_total, 1, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_WORLD, mpi_iErr )
#else
    nP_wall_total = nP_wall
    nP_bad_total = nP_bad
    nP_off_vGrid_total = nP_off_vGrid
    nP_badWeight_total = nP_badWeight
    nP_badEnergy_total = nP_badEnergy
    nP_TookMaxStepsBeforeBounce_total = nP_TookMaxStepsBeforeBounce
    nP_mpiSum_total = nP_mpiSum
    nP_OutsideTheBox_total = nP_OutsideTheBox
#endif

    ! Test the reduction operation
    if(mpi_pId==0) write (*,*) 'Stopping MPI' 
#if PARALLEL==1
    call stop_mpi () 
#endif
    if(mpi_pId==0) write(*,*) 'Getting CPU time'   
    call cpu_time (T2)
 
    if(mpi_pId==0) then

        write (*,*) 'Time taken: ', T2-T1 
        write (*,*) 'Total number of particles: ', nP_mpiSum_total
        write (*,'(a,f5.2,a)') 'Outside the rbbbs/zbbbs box: ', real(nP_OutsideTheBox_total) / real ( nP ) * 100.0, '%'
        write (*,'(a,f5.2,a)') 'TookMaxStepsBeforeBounce:      ', &
                real ( nP_TookMaxStepsBeforeBounce_total ) / real ( nP ) * 100.0, '%', &
                '   *** this means you need a larger MaxSteps'
        write (*,'(a,f5.2,a)') 'Wall:      ', real ( nP_wall_total ) / real ( nP ) * 100.0, '%'
        write (*,'(a,f5.2,a)') 'Bad:       ', real ( nP_bad_total ) / real ( nP ) * 100.0, '%'
        write (*,'(a,f7.3,a,a)') 'off_vGrid: ', real ( nP_off_vGrid_total ) / real ( nP ) * 100.0, '%', &
            '   *** only applicable for gParticle = .false.'
        write (*,'(a,f5.2,a)') 'badWeight: ', real ( nP_badWeight_total ) / real ( nP ) * 100.0, '%'
        write (*,'(a,f5.2,a)') 'badEnergy: ', real ( nP_badEnergy_total ) / real ( nP ) * 100.0, '%'
        write (*,'(a,f5.1,a)') 'Suggested eNorm: ', &
            real ( maxVal ( vPer_binCenters )**2 * 0.5 * mi / e_ / 1e3 ), ' keV'

        !   Integrate over velocity space to get a number for
        !   density for sanity check ;-)

        density = 0
        TotalNumberOfParticles = 0
        do i = 1, R_nBins
            do j = 1, z_nBins
    
                tmpDensity  = 0
                do k = 1, vPer_nBins

                    tmpDensity = tmpDensity + &
                        sum ( f_rzvv(i,j,k,:) ) * vPer_binCenters(k)

                end do
                
                density(i,j)    = tmpDensity * &
                    2.0 * pi * vPer_binSize * vPar_binSize

                TotalNumberOfParticles = TotalNumberOfParticles + density(i,j)*r_binSize*z_binSize*2*pi*r_binCenters(i) 

            end do
        end do

        write(*,'(a,e8.2)') 'max ( density ): ', maxVal ( density )
        write(*,'(a,e8.2)') 'TotalNumberOfParticles: ', TotalNumberOfParticles 

        call write_f ()

    end if

end program p2f
