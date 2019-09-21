module module_fv3gfs_ncio
! module for reading/writing netcdf global lat/lon grid files output by FV3GFS

! ifort -I${NETCDF}/include -c -traceback module_fv3gfs_ncio.f90
  use netcdf

  implicit none
  private

  type Variable
     integer varid
     integer ndims
     integer dtype
     integer natts
     integer deflate_level
     logical shuffle
     character(len=nf90_max_name) :: name
     integer, allocatable, dimension(:) :: dimids 
     character(len=nf90_max_name), allocatable, dimension(:) :: dimnames 
     integer, allocatable, dimension(:) :: dimlens
  end type Variable   
  type Dimension 
     integer dimid
     integer len
     logical isunlimited
     character(len=nf90_max_name) :: name
  end type Dimension
  type Dataset
     integer :: ncid
     integer :: nvars
     integer :: ndims
     integer :: natts
     integer :: nunlimdim
     character(len=500) filename
     type(Variable), allocatable, dimension(:) :: variables
     type(Dimension), allocatable, dimension(:) :: dimensions
  end type Dataset

  interface read_vardata
      module procedure read_vardata_1d_r4, read_vardata_2d_r4, read_vardata_3d_r4,&
      read_vardata_4d_r4, read_vardata_1d_r8, read_vardata_2d_r8, read_vardata_3d_r8,&
      read_vardata_4d_r8, read_vardata_1d_int, read_vardata_2d_int, &
      read_vardata_3d_int, read_vardata_4d_int
  end interface

  interface write_vardata
      module procedure write_vardata_1d_r4, write_vardata_2d_r4, write_vardata_3d_r4,&
      write_vardata_4d_r4, write_vardata_1d_r8, write_vardata_2d_r8, write_vardata_3d_r8,&
      write_vardata_4d_r8, write_vardata_1d_int, write_vardata_2d_int, &
      write_vardata_3d_int, write_vardata_4d_int
  end interface

  interface read_attribute
      module procedure read_attribute_r4_scalar, read_attribute_int_scalar,&
      read_attribute_r8_scalar, read_attribute_r4_1d,&
      read_attribute_int_1d, read_attribute_r8_1d
  end interface

  public :: open_dataset, create_dataset, close_dataset, Dataset, Variable, Dimension
  public :: read_vardata, read_attribute, get_vardim, get_dimlen

  contains

  subroutine nccheck(status)
    ! check return code, print error message 
    implicit none
    integer, intent (in) :: status
    if (status /= nf90_noerr) then
      write(0,*) status, trim(nf90_strerror(status))
      stop "stopped"
    end if
  end subroutine nccheck

  integer function get_vardim(dset, varname)
    ! return number of dimensions associated with variable
    type(Dataset), intent(in) :: dset
    character(len=*), intent(in) :: varname
    integer nvar
    do nvar=1,dset%nvars
       if (trim(dset%variables(nvar)%name) == trim(varname)) then 
          exit
       endif
    enddo
    get_vardim = dset%variables(nvar)%ndims
  end function get_vardim

  integer function get_dimlen(dset, dimname)
    ! return length of dimension
    type(Dataset), intent(in) :: dset
    character(len=*), intent(in) :: dimname
    integer ndim
    do ndim=1,dset%ndims
       if (trim(dset%dimensions(ndim)%name) == trim(dimname)) then 
          exit
       endif
    enddo
    get_dimlen = dset%dimensions(ndim)%len
  end function get_dimlen
    
  subroutine open_dataset(filename, dset)
    ! open existing dataset, create dataset object for netcdf file 
    implicit none
    character(len=*), intent(in) :: filename
    character(len=nf90_max_name) :: dimname
    type(Dataset), intent(out) :: dset
    integer ncerr,ncid,nunlimdim
    integer ndim,nvar,n
    ! open netcdf file, get info, populate Dataset object.
    ncerr = nf90_open(trim(filename), NF90_NOWRITE, ncid=dset%ncid)
    call nccheck(ncerr)
    ncerr = nf90_inquire(dset%ncid, dset%ndims, dset%nvars, dset%natts, nunlimdim)
    call nccheck(ncerr)
    dset%filename = trim(filename)
    allocate(dset%variables(dset%nvars))
    allocate(dset%dimensions(dset%ndims))
    do ndim=1,dset%ndims
       dset%dimensions(ndim)%dimid = ndim
       ncerr = nf90_inquire_dimension(dset%ncid, ndim, name=dset%dimensions(ndim)%name, &
                                      len=dset%dimensions(ndim)%len)
       call nccheck(ncerr)
       if (ndim == nunlimdim) then
          dset%dimensions(ndim)%isunlimited = .true.
       else
          dset%dimensions(ndim)%isunlimited = .false.
       endif
    enddo
    do nvar=1,dset%nvars
       dset%variables(nvar)%varid = nvar
       ncerr = nf90_inquire_variable(dset%ncid, nvar,&
                                     name=dset%variables(nvar)%name,&
                                     natts=dset%variables(nvar)%natts,&
                                     xtype=dset%variables(nvar)%dtype,&
                                     ndims=dset%variables(nvar)%ndims)
       call nccheck(ncerr)
       allocate(dset%variables(nvar)%dimids(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimlens(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimnames(dset%variables(nvar)%ndims))
       ncerr = nf90_inquire_variable(dset%ncid, nvar,&
                                     dimids=dset%variables(nvar)%dimids,&
                                     deflate_level=dset%variables(nvar)%deflate_level,&
                                     shuffle=dset%variables(nvar)%shuffle)
       call nccheck(ncerr)
       do ndim=1,dset%variables(nvar)%ndims
          do n=1,dset%ndims
            if (dset%variables(nvar)%dimids(ndim) == dset%dimensions(n)%dimid) then
               exit
            endif
          enddo
          dset%variables(nvar)%dimlens(ndim) = dset%dimensions(n)%len
          dset%variables(nvar)%dimnames(ndim) = dset%dimensions(n)%name
       enddo
    enddo
  end subroutine open_dataset

  subroutine create_dataset(dsetin, filename, dset, copy_vardata)
    ! create new dataset, using an existing dataset object to define
    ! variables and dimensions.  
    implicit none
    character(len=*), intent(in) :: filename
    character(len=nf90_max_name) :: dimname, attname, varname
    logical, intent(in), optional :: copy_vardata
    type(Dataset), intent(out) :: dset
    type(Dataset), intent(in) :: dsetin
    integer ncerr,ncid,nunlimdim
    integer ndim,nvar,n,ishuffle,natt
    logical copyd
    real(8), allocatable, dimension(:) :: values_1d
    real(8), allocatable, dimension(:,:) :: values_2d
    real(8), allocatable, dimension(:,:,:) :: values_3d
    real(8), allocatable, dimension(:,:,:,:) :: values_4d
    integer, allocatable, dimension(:) :: ivalues_1d
    integer, allocatable, dimension(:,:) :: ivalues_2d
    integer, allocatable, dimension(:,:,:) :: ivalues_3d
    integer, allocatable, dimension(:,:,:,:) :: ivalues_4d
    if (present(copy_vardata)) then
       copyd = copy_vardata
    else
       copyd = .false.
    endif
    ! create netcdf file
    ncerr = nf90_create(trim(filename), &
            cmode=IOR(IOR(NF90_CLOBBER,NF90_NETCDF4),NF90_CLASSIC_MODEL), &
            ncid=dset%ncid)
    call nccheck(ncerr)
    ! copy global attributes
    do natt=1,dsetin%natts
       ncerr = nf90_inq_attname(dsetin%ncid, NF90_GLOBAL, natt, attname)
       call nccheck(ncerr)
       ncerr = nf90_copy_att(dsetin%ncid, NF90_GLOBAL, attname, dset%ncid, NF90_GLOBAL)
       call nccheck(ncerr)
    enddo
    dset%natts = dsetin%natts
    dset%filename = trim(filename)
    dset%ndims = dsetin%ndims
    dset%nvars = dsetin%nvars
    allocate(dset%variables(dsetin%nvars))
    allocate(dset%dimensions(dsetin%ndims))
    ! create dimensions
    do ndim=1,dsetin%ndims
       if (dsetin%dimensions(ndim)%isunlimited) then
          ncerr = nf90_def_dim(dset%ncid, trim(dsetin%dimensions(ndim)%name), &
                  NF90_UNLIMITED, &
                  dset%dimensions(ndim)%dimid)
          call nccheck(ncerr)
          dset%dimensions(ndim)%isunlimited = .true.
          dset%nunlimdim = ndim
          dset%dimensions(ndim)%len = 0
          dset%dimensions(ndim)%name = trim(dsetin%dimensions(ndim)%name)
       else
          ncerr = nf90_def_dim(dset%ncid, trim(dsetin%dimensions(ndim)%name),&
                  dsetin%dimensions(ndim)%len, &
                  dset%dimensions(ndim)%dimid)
          call nccheck(ncerr)
          dset%dimensions(ndim)%len = dsetin%dimensions(ndim)%len
          dset%dimensions(ndim)%isunlimited = .false.
          dset%dimensions(ndim)%name = trim(dsetin%dimensions(ndim)%name)
       endif
    enddo
    ! create variables
    do nvar=1,dsetin%nvars
       dset%variables(nvar)%ndims = dsetin%variables(nvar)%ndims
       allocate(dset%variables(nvar)%dimids(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimnames(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimlens(dset%variables(nvar)%ndims))
       do ndim=1,dset%variables(nvar)%ndims
          do n=1,dset%ndims
            if (trim(dsetin%variables(nvar)%dimnames(ndim)) == &
                trim(dset%dimensions(n)%name)) then
               exit
            endif
          enddo
          dset%variables(nvar)%dimids(ndim) = dset%dimensions(n)%dimid
          dset%variables(nvar)%dimlens(ndim) = dset%dimensions(n)%len
          dset%variables(nvar)%dimnames(ndim) = dset%dimensions(n)%name
       enddo
       dset%variables(nvar)%name = dsetin%variables(nvar)%name
       dset%variables(nvar)%dtype = dsetin%variables(nvar)%dtype
       ncerr = nf90_def_var(dset%ncid, &
                            trim(dset%variables(nvar)%name),&
                            dset%variables(nvar)%dtype, &
                            dset%variables(nvar)%dimids, &
                            dset%variables(nvar)%varid)
       call nccheck(ncerr)
       if (dsetin%variables(nvar)%deflate_level > 0) then
          if (dsetin%variables(nvar)%shuffle) then
            ishuffle=1
          else
            ishuffle=0
          endif
          ncerr = nf90_def_var_deflate(dset%ncid, dset%variables(nvar)%varid,&
                  ishuffle,1,dsetin%variables(nvar)%deflate_level)
          call nccheck(ncerr)
          dset%variables(nvar)%shuffle = dsetin%variables(nvar)%shuffle
          dset%variables(nvar)%deflate_level = &
          dsetin%variables(nvar)%deflate_level
       endif
       ! copy variable attributes
       do natt=1,dsetin%variables(nvar)%natts
          ncerr = nf90_inq_attname(dsetin%ncid, dsetin%variables(nvar)%varid, natt, attname)
          call nccheck(ncerr)
          ncerr = nf90_copy_att(dsetin%ncid, dsetin%variables(nvar)%varid, attname, dset%ncid, dset%variables(nvar)%varid)
          call nccheck(ncerr)
       enddo
    enddo
    ncerr = nf90_enddef(dset%ncid)
    call nccheck(ncerr)
    if (copyd) then
       ! if desired, copy variable data
       ! assumes data is real (32 or 64 bit), or integer (16 or 32 bit) and 1-4d.
       do nvar=1,dsetin%nvars
          varname = trim(dsetin%variables(nvar)%name)
          if (dsetin%variables(nvar)%dtype == NF90_FLOAT .or.&
              dsetin%variables(nvar)%dtype == NF90_DOUBLE) then
             if (dsetin%variables(nvar)%ndims == 1) then
                call read_vardata(dsetin, varname, values_1d)
                call write_vardata(dset, varname, values_1d)
             else if (dsetin%variables(nvar)%ndims == 2) then
                call read_vardata(dsetin, varname, values_2d)
                call write_vardata(dset, varname, values_2d)
             else if (dsetin%variables(nvar)%ndims == 3) then
                call read_vardata(dsetin, varname, values_3d)
                call write_vardata(dset, varname, values_3d)
             else if (dsetin%variables(nvar)%ndims == 4) then
                call read_vardata(dsetin, varname, values_4d)
                call write_vardata(dset, varname, values_4d)
             endif
          elseif (dsetin%variables(nvar)%dtype == NF90_INT .or.&
                  dsetin%variables(nvar)%dtype == NF90_SHORT) then
             if (dsetin%variables(nvar)%ndims == 1) then
                call read_vardata(dsetin, varname, ivalues_1d)
                call write_vardata(dset, varname, ivalues_1d)
             else if (dsetin%variables(nvar)%ndims == 2) then
                call read_vardata(dsetin, varname, ivalues_2d)
                call write_vardata(dset, varname, ivalues_2d)
             else if (dsetin%variables(nvar)%ndims == 3) then
                call read_vardata(dsetin, varname, ivalues_3d)
                call write_vardata(dset, varname, ivalues_3d)
             else if (dsetin%variables(nvar)%ndims == 4) then
                call read_vardata(dsetin, varname, ivalues_4d)
                call write_vardata(dset, varname, ivalues_4d)
             endif
          else
             print *,'not copying variable ',trim(adjustl(varname)),&
                     ' (unsupported data type)'
          endif
       enddo
    endif
  end subroutine create_dataset
 
  subroutine close_dataset(dset)
    ! deallocate members of dataset object
    type(Dataset), intent(inout) :: dset
    integer ncerr, nvar
    ncerr = nf90_close(ncid=dset%ncid)
    call nccheck(ncerr)
    do nvar=1,dset%nvars
       deallocate(dset%variables(nvar)%dimids)
       deallocate(dset%variables(nvar)%dimlens)
       deallocate(dset%variables(nvar)%dimnames)
    enddo
    deallocate(dset%variables,dset%dimensions)
  end subroutine close_dataset

  integer function nvar_(dset,varname)
    ! private function to get variable index given name
    type(Dataset), intent(in) :: dset
    character(len=*), intent(in) :: varname
    logical foundit
    integer nvar
    foundit = .false.
    do nvar=1,dset%nvars
       if (trim(dset%variables(nvar)%name) == trim(varname)) then 
          foundit = .true.
          exit
       endif
    enddo
    if (.not. foundit) then
       print *,'no variable named ',varname
       stop "stopped"
    endif
    nvar_ = nvar
  end function nvar_

  subroutine read_vardata_1d_r4(dset, varname, values)
    real(4), allocatable, dimension(:), intent(inout) :: values
    include "read_vardata_code_1d.f90"
  end subroutine read_vardata_1d_r4

  subroutine read_vardata_2d_r4(dset, varname, values)
    real(4), allocatable, dimension(:,:), intent(inout) :: values
    include "read_vardata_code_2d.f90"
  end subroutine read_vardata_2d_r4

  subroutine read_vardata_3d_r4(dset, varname, values)
    real(4), allocatable, dimension(:,:,:), intent(inout) :: values
    include "read_vardata_code_3d.f90"
  end subroutine read_vardata_3d_r4

  subroutine read_vardata_4d_r4(dset, varname, values)
    real(4), allocatable, dimension(:,:,:,:), intent(inout) :: values
    include "read_vardata_code_4d.f90"
  end subroutine read_vardata_4d_r4

  subroutine read_vardata_1d_r8(dset, varname, values)
    real(8), allocatable, dimension(:), intent(inout) :: values
    include "read_vardata_code_1d.f90"
  end subroutine read_vardata_1d_r8

  subroutine read_vardata_2d_r8(dset, varname, values)
    real(8), allocatable, dimension(:,:), intent(inout) :: values
    include "read_vardata_code_2d.f90"
  end subroutine read_vardata_2d_r8

  subroutine read_vardata_3d_r8(dset, varname, values)
    real(8), allocatable, dimension(:,:,:), intent(inout) :: values
    include "read_vardata_code_3d.f90"
  end subroutine read_vardata_3d_r8

  subroutine read_vardata_4d_r8(dset, varname, values)
    real(8), allocatable, dimension(:,:,:,:), intent(inout) :: values
    include "read_vardata_code_4d.f90"
  end subroutine read_vardata_4d_r8

  subroutine read_vardata_1d_int(dset, varname, values)
    integer, allocatable, dimension(:), intent(inout) :: values
    include "read_vardata_code_1d.f90"
  end subroutine read_vardata_1d_int

  subroutine read_vardata_2d_int(dset, varname, values)
    integer, allocatable, dimension(:,:), intent(inout) :: values
    include "read_vardata_code_2d.f90"
  end subroutine read_vardata_2d_int

  subroutine read_vardata_3d_int(dset, varname, values)
    integer, allocatable, dimension(:,:,:), intent(inout) :: values
    include "read_vardata_code_3d.f90"
  end subroutine read_vardata_3d_int

  subroutine read_vardata_4d_int(dset, varname, values)
    integer, allocatable, dimension(:,:,:,:), intent(inout) :: values
    include "read_vardata_code_4d.f90"
  end subroutine read_vardata_4d_int

  subroutine write_vardata_1d_r4(dset, varname, values)
    real(4),  dimension(:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_1d_r4

  subroutine write_vardata_2d_r4(dset, varname, values)
    real(4),  dimension(:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_2d_r4

  subroutine write_vardata_3d_r4(dset, varname, values)
    real(4),  dimension(:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_3d_r4

  subroutine write_vardata_4d_r4(dset, varname, values)
    real(4),  dimension(:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_4d_r4

  subroutine write_vardata_1d_r8(dset, varname, values)
    real(8),  dimension(:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_1d_r8

  subroutine write_vardata_2d_r8(dset, varname, values)
    real(8),  dimension(:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_2d_r8

  subroutine write_vardata_3d_r8(dset, varname, values)
    real(8),  dimension(:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_3d_r8

  subroutine write_vardata_4d_r8(dset, varname, values)
    real(8),  dimension(:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_4d_r8

  subroutine write_vardata_1d_int(dset, varname, values)
    integer,  dimension(:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_1d_int

  subroutine write_vardata_2d_int(dset, varname, values)
    integer,  dimension(:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_2d_int

  subroutine write_vardata_3d_int(dset, varname, values)
    integer,  dimension(:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_3d_int

  subroutine write_vardata_4d_int(dset, varname, values)
    integer,  dimension(:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_4d_int

  subroutine read_attribute_int_scalar(dset, attname, values, varname)
    integer, intent(inout) :: values
    include "read_scalar_attribute_code.f90"
  end subroutine read_attribute_int_scalar

  subroutine read_attribute_r4_scalar(dset, attname, values, varname)
    real(4), intent(inout) :: values
    include "read_scalar_attribute_code.f90"
  end subroutine read_attribute_r4_scalar

  subroutine read_attribute_r8_scalar(dset, attname, values, varname)
    real(8), intent(inout) :: values
    include "read_scalar_attribute_code.f90"
  end subroutine read_attribute_r8_scalar

  subroutine read_attribute_r4_1d(dset, attname, values, varname)
    real(4), intent(inout), allocatable, dimension(:) :: values
    include "read_attribute_code.f90"
  end subroutine read_attribute_r4_1d

  subroutine read_attribute_r8_1d(dset, attname, values, varname)
    real(8), intent(inout), allocatable, dimension(:) :: values
    include "read_attribute_code.f90"
  end subroutine read_attribute_r8_1d

  subroutine read_attribute_int_1d(dset, attname, values, varname)
    integer, intent(inout), allocatable, dimension(:) :: values
    include "read_attribute_code.f90"
  end subroutine read_attribute_int_1d

end module module_fv3gfs_ncio
