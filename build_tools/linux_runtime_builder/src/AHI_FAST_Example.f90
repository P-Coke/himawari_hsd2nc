program AHI_fast_example_f90

    use himawari
    use himawari_utils
    use himawari_readwrite
    use himawari_readheader
    use himawari_headerinfo
    use himawari_navigation

    implicit none

    logical :: do_solar
    logical :: do_solar_angles
    logical :: vis_res
    logical :: new_calib

    character(HIMAWARI_CHARLEN) :: filename
    character(HIMAWARI_CHARLEN) :: outname
    character(len=128) :: satposstr

    integer :: retval, nchans, ncmd, ios, i, write_flag
    character(len=1024) :: inarg
    character(len=16) :: vname
    integer, dimension(16) :: band_ids
    logical :: has_roi
    real(kind=ahi_dreal) :: roi_lon1, roi_lon2, roi_lat1, roi_lat2
    type(himawari_t_navdata) :: navdata

    type(himawari_t_data) :: ahi_data
    type(himawari_t_extent) :: ahi_extent

    logical :: verbose

    do_solar = .false.
    do_solar_angles = .false.
    vis_res = .false.
    new_calib = .true.
    verbose = .true.
    has_roi = .false.
    roi_lon1 = 0.0_8
    roi_lon2 = 0.0_8
    roi_lat1 = 0.0_8
    roi_lat2 = 0.0_8

    ahi_extent%x_min = 1
    ahi_extent%y_min = 1
    ahi_extent%x_max = HIMAWARI_IR_NLINES
    ahi_extent%y_max = HIMAWARI_IR_NCOLS
    ahi_extent%x_size = ahi_extent%x_max - ahi_extent%x_min + 1
    ahi_extent%y_size = ahi_extent%y_max - ahi_extent%y_min + 1

    ncmd = 1
    nchans = 0
    band_ids(:) = him_sint_fill_value

    do
        call get_command_argument(ncmd, inarg)
        if (len_trim(inarg) == 0) exit
        if (ncmd == 1) filename = trim(inarg)
        if (ncmd == 2) outname = trim(inarg)
        if (ncmd >= 3) then
            if (trim(inarg) == "ROI") then
                has_roi = .true.
                call get_command_argument(ncmd+1, inarg)
                read(inarg,*,iostat=ios) roi_lon1
                if (ios /= 0) stop "Bad ROI lon1"
                call get_command_argument(ncmd+2, inarg)
                read(inarg,*,iostat=ios) roi_lat1
                if (ios /= 0) stop "Bad ROI lat1"
                call get_command_argument(ncmd+3, inarg)
                read(inarg,*,iostat=ios) roi_lon2
                if (ios /= 0) stop "Bad ROI lon2"
                call get_command_argument(ncmd+4, inarg)
                read(inarg,*,iostat=ios) roi_lat2
                if (ios /= 0) stop "Bad ROI lat2"
                exit
            else
                read(inarg, '(i10)', iostat=ios) retval
                if (ios /= 0) then
                    write(*,*) "Incorrect channel specification:", trim(inarg)
                    stop
                endif
                nchans = nchans + 1
                if (nchans > 16) then
                    write(*,*) "Too many channels requested, maximum is 16."
                    stop
                endif
                band_ids(nchans) = retval
            endif
        endif
        ncmd = ncmd + 1
    enddo

    if (nchans <= 0) then
        write(*,*) "No channels requested. Usage: AHI_FAST <input> <output.nc> <band...>"
        stop
    endif

    if (has_roi) then
        call AHI_Init_Nav_From_File(filename, band_ids(1), navdata, verbose, retval)
        if (retval /= HIMAWARI_SUCCESS) stop "Failed to initialize navigation for ROI"
        call AHI_ROI_To_Extent(navdata, roi_lon1, roi_lat1, roi_lon2, roi_lat2, ahi_extent, retval)
        if (retval /= HIMAWARI_SUCCESS) stop "ROI does not overlap AHI grid"
        write(*,*) "ROI input (lon1,lat1,lon2,lat2):", roi_lon1, roi_lat1, roi_lon2, roi_lat2
        write(*,*) "ROI extent (x_min,x_max,y_min,y_max):", ahi_extent%x_min, ahi_extent%x_max, ahi_extent%y_min, ahi_extent%y_max
    endif

    ahi_extent%x_size = ahi_extent%x_max - ahi_extent%x_min + 1
    ahi_extent%y_size = ahi_extent%y_max - ahi_extent%y_min + 1

    retval = AHI_alloc_vals_data(ahi_data, ahi_extent, nchans, do_solar, verbose)
    if (retval /= HIMAWARI_SUCCESS) then
        write(*,*) "Error encountered in data allocation."
        stop
    endif

    retval = AHI_Main_Read(filename, &
                           "./AHI_141E_ANGLES.nc", &
                           ahi_data, &
                           ahi_extent, &
                           nchans, &
                           band_ids, &
                           1, &
                           1, &
                           .false., &
                           do_solar, &
                           vis_res, &
                           satposstr, &
                           do_solar_angles, &
                           new_calib, &
                           verbose)
    if (retval /= HIMAWARI_SUCCESS) then
        write(*,*) "Error encountered in data reading."
        stop
    endif

    write_flag = 1
    do i = 1, nchans
        write(vname, '("Band_", I2.2)') band_ids(i)
        retval = AHI_SavetoNCDF(ahi_data%indata(:,:,i), ahi_extent, outname, trim(vname), write_flag, verbose)
        write_flag = 0
    enddo
    retval = AHI_SavetoNCDF(ahi_data%lat, ahi_extent, outname, "Lat", 0, verbose)
    retval = AHI_SavetoNCDF(ahi_data%lon, ahi_extent, outname, "Lon", 0, verbose)

    retval = AHI_free_vals_data(ahi_data, verbose)

contains

subroutine AHI_Init_Nav_From_File(fname, band, nav, verbose, status)
    character(len=*), intent(in) :: fname
    integer, intent(in) :: band
    type(himawari_t_navdata), intent(out) :: nav
    logical, intent(in) :: verbose
    integer, intent(out) :: status
    integer :: filelun
    type(himawari_t_VIS_Header) :: hdrvis
    type(himawari_t_IR_Header) :: hdrir

    open(newunit=filelun, file=fname, form='unformatted', action='read', status='old', access='stream', convert='little_endian')
    if (band < 7) then
        status = AHI_readhdr_VIS(filelun, hdrvis, verbose)
        if (status /= HIMAWARI_SUCCESS) then
            close(filelun)
            return
        endif
        status = AHI_DefaultNav(nav, hdrvis%him_proj, verbose)
        if (status == HIMAWARI_SUCCESS) then
            ! Match the navigation scaling used in AHI_readchan when processing VIS at IR grid.
            nav%cfac = ceiling((nav%cfac) / 2.0_8)
            nav%lfac = ceiling((nav%lfac) / 2.0_8)
            nav%coff = (nav%coff - 0.5_8) / 2.0_8
            nav%loff = (nav%loff - 0.5_8) / 2.0_8
            if (band == 3) then
                nav%cfac = ceiling(nav%cfac / 2.0_8)
                nav%lfac = ceiling(nav%lfac / 2.0_8)
                nav%coff = nav%coff / 2.0_8
                nav%loff = nav%loff / 2.0_8
            endif
            nav%coff = nav%coff + 0.5_8
            nav%loff = nav%loff + 0.5_8
        endif
    else
        status = AHI_readhdr_IR(filelun, hdrir, verbose)
        if (status /= HIMAWARI_SUCCESS) then
            close(filelun)
            return
        endif
        status = AHI_DefaultNav(nav, hdrir%him_proj, verbose)
    endif
    close(filelun)
end subroutine AHI_Init_Nav_From_File

subroutine AHI_ROI_To_Extent(nav, lon1, lat1, lon2, lat2, ext, status)
    type(himawari_t_navdata), intent(in) :: nav
    real(kind=ahi_dreal), intent(in) :: lon1, lat1, lon2, lat2
    type(himawari_t_extent), intent(inout) :: ext
    integer, intent(out) :: status

    integer :: c1, l1, stepv, margin
    integer :: xmin, xmax, ymin, ymax
    real(kind=ahi_dreal) :: lon_min, lon_max, lat_min, lat_max
    real(kind=ahi_dreal) :: lon, lat
    logical :: ok, found, cross_dateline

    lon_min = normalize_lon180(min(lon1, lon2))
    lon_max = normalize_lon180(max(lon1, lon2))
    lat_min = min(lat1, lat2)
    lat_max = max(lat1, lat2)
    cross_dateline = ((lon_max - lon_min) > 180.0_8)

    xmin = HIMAWARI_IR_NLINES
    xmax = 1
    ymin = HIMAWARI_IR_NCOLS
    ymax = 1
    found = .false.
    stepv = 8
    margin = 24

    do c1 = 1, HIMAWARI_IR_NLINES, stepv
        do l1 = 1, HIMAWARI_IR_NCOLS, stepv
            call AHI_Pix2Geo_Single(nav, dble(c1), dble(l1), lat, lon, ok)
            if (.not. ok) cycle
            if (lat < lat_min .or. lat > lat_max) cycle
            if (.not. lon_in_roi(normalize_lon180(lon), lon_min, lon_max, cross_dateline)) cycle
            found = .true.
            if (c1 < xmin) xmin = c1
            if (c1 > xmax) xmax = c1
            if (l1 < ymin) ymin = l1
            if (l1 > ymax) ymax = l1
        enddo
    enddo

    if (.not. found) then
        status = HIMAWARI_FAILURE
        return
    endif

    ext%x_min = max(1, xmin - margin)
    ext%x_max = min(HIMAWARI_IR_NLINES, xmax + margin)
    ext%y_min = max(1, ymin - margin)
    ext%y_max = min(HIMAWARI_IR_NCOLS, ymax + margin)
    status = HIMAWARI_SUCCESS
end subroutine AHI_ROI_To_Extent

subroutine AHI_Pix2Geo_Single(nav, c, l, lat, lon, ok)
    type(himawari_t_navdata), intent(in) :: nav
    real(kind=ahi_dreal), intent(in) :: c, l
    real(kind=ahi_dreal), intent(out) :: lat, lon
    logical, intent(out) :: ok
    real(kind=ahi_dreal) :: x, y, sdv, sn, s1, s2, s3, sxy

    x = (c - nav%coff) / (HIMAWARI_SCLUNIT * nav%cfac)
    y = (l - nav%loff) / (HIMAWARI_SCLUNIT * nav%lfac)

    sdv = (nav%satDis * cos(x) * cos(y)) * (nav%satDis * cos(x) * cos(y)) - &
          (cos(y) * cos(y) + nav%projParam3 * sin(y) * sin(y)) * nav%projParamSd
    if (sdv <= 0.0_8) then
        ok = .false.
        lat = him_sreal_fill_value
        lon = him_sreal_fill_value
        return
    endif

    sdv = sqrt(sdv)
    sn = (nav%satDis * cos(x) * cos(y) - sdv) / (cos(y) * cos(y) + nav%projParam3 * sin(y) * sin(y))
    s1 = nav%satDis - (sn * cos(x) * cos(y))
    s2 = sn * sin(x) * cos(y)
    s3 = -sn * sin(y)
    sxy = sqrt(s1 * s1 + s2 * s2)

    lon = HIMAWARI_RADTODEG * atan(s2 / s1) + nav%subLon
    lat = atan(nav%projParam3 * s3 / sxy) * HIMAWARI_RADTODEG

    if (lon > 180.0_8) lon = lon - 360.0_8
    if (lon < -180.0_8) lon = lon + 360.0_8
    ok = (lon >= -180.0_8 .and. lon <= 180.0_8 .and. lat >= -90.0_8 .and. lat <= 90.0_8)
end subroutine AHI_Pix2Geo_Single

real(kind=ahi_dreal) function normalize_lon180(lon) result(out)
    real(kind=ahi_dreal), intent(in) :: lon
    out = modulo(lon + 180.0_8, 360.0_8) - 180.0_8
end function normalize_lon180

logical function lon_in_roi(lon, lon_min, lon_max, cross_dateline) result(ok)
    real(kind=ahi_dreal), intent(in) :: lon, lon_min, lon_max
    logical, intent(in) :: cross_dateline
    if (.not. cross_dateline) then
        ok = (lon >= lon_min .and. lon <= lon_max)
    else
        ok = (lon >= lon_max .or. lon <= lon_min)
    endif
end function lon_in_roi

end program AHI_fast_example_f90
