! SUMMA - Structure for Unifying Multiple Modeling Alternatives
! Copyright (C) 2014-2015 NCAR/RAL
!
! This file is part of SUMMA
!
! For more information see: http://www.ral.ucar.edu/projects/summa
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

module read_attrb_module
USE nrtype
implicit none
private
public::read_dimension
public::read_attrb
contains

 ! ************************************************************************************************
 ! public subroutine read_dimension: read HRU and GRU dimension information on local attributes
 ! ************************************************************************************************
 subroutine read_dimension(maxGRU,maxHRU,err,message)
 USE netcdf
 USE netcdf_util_module,only:nc_file_open          ! open netcdf file
 USE netcdf_util_module,only:netcdf_err            ! netcdf error handling function 
 USE summaFileManager,only:SETNGS_PATH             ! path for metadata files
 USE summaFileManager,only:LOCAL_ATTRIBUTES        ! file containing information on local attributes 
 implicit none 
 integer(i4b),intent(out)             :: maxGRU             ! maximum number of GRUs in the input file
 integer(i4b),intent(out)             :: maxHRU             ! maximum number of HRUs in the input file
 integer(i4b),intent(out)             :: err             ! error code
 character(*),intent(out)             :: message         ! error message
 ! define variables for NetCDF file operation
 integer(i4b)                         :: mode               ! netCDF file open mode
 integer(i4b)                         :: ncid               ! integer variables for NetCDF IDs
 integer(i4b)                         :: gruDimId           ! variable id of GRU dimension from netcdf file
 integer(i4b)                         :: hruDimId           ! variable id of HRU dimension from netcdf file
 character(len=256)                   :: cmessage           ! error message for downwind routine
 ! Start procedure here
 err=0; message="inq_ncdim/" 
 ! open nc file
 mode=nf90_noWrite
 call nc_file_open(trim(SETNGS_PATH)//trim(LOCAL_ATTRIBUTES), mode, ncid, err, cmessage)
 if(err/=0)then; message=trim(message)//trim(cmessage); return; endif
 
 ! get gru dimension length
 err = nf90_inq_dimid(ncid, "gru", gruDimId);                if(err/=nf90_noerr)then; message=trim(message)//'problem finding gru dimension/'//trim(nf90_strerror(err)); return; endif
 err = nf90_inquire_dimension(ncid, gruDimId, len = maxGRU); if(err/=nf90_noerr)then; message=trim(message)//'problem reading gru dimension/'//trim(nf90_strerror(err)); return; endif
 
 ! get hru dimension length
 err = nf90_inq_dimid(ncid, "hru", hruDimId);                if(err/=nf90_noerr)then; message=trim(message)//'problem finding hru dimension/'//trim(nf90_strerror(err)); return; endif
 err = nf90_inquire_dimension(ncid, hruDimId, len = maxHRU); if(err/=nf90_noerr)then; message=trim(message)//'problem reading hru dimension/'//trim(nf90_strerror(err)); return; endif  
 
 ! close the HRU_ATTRIBUTES netCDF file
 err = nf90_close(ncid)
 if(err/=0)then; err=20; message=trim(message)//'error closing LocalAttributes file'; return; endif
 
 end subroutine read_dimension
 
 ! ************************************************************************************************
 ! public subroutine read_attrb: read information on local attributes
 ! ************************************************************************************************
 subroutine read_attrb(nGRU,maxHRU,attrStruct,typeStruct,err,message,checkHRU)
 ! provide access to subroutines
 USE netcdf
 USE netcdf_util_module,only:nc_file_open          ! open netcdf file
 USE netcdf_util_module,only:netcdf_err            ! netcdf error handling function
 USE nr_utility_module,only:arth
 USE ascii_util_module,only:file_open              ! open ascii file
 USE ascii_util_module,only:split_line             ! extract the list of variable names from the character string
 USE ascii_util_module,only:get_vlines             ! read a vector of non-comment lines from an ASCII file
 ! provide access to derived data types
 USE data_types,only:gru_hru_int                   ! x%gru(:)%hru(:)%var(:)     (i4b)
 USE data_types,only:gru_hru_double                ! x%gru(:)%hru(:)%var(:)     (dp)
 ! provide access to global data
 USE summaFileManager,only:SETNGS_PATH             ! path for metadata files
 USE summaFileManager,only:LOCAL_ATTRIBUTES        ! file containing information on local attributes
 USE globalData,only:gru_struc                     ! gru-hru mapping structure
 USE globalData,only:index_map                     ! hru-gru mapping structure
 USE globalData,only:attr_meta,type_meta           ! metadata structures
 USE var_lookup,only:iLookATTR,iLookTYPE           ! named variables for elements of the data structures
 USE get_ixname_module,only:get_ixAttr,get_ixType  ! access function to find index of elements in structure
 implicit none
 ! define input
 integer(i4b),intent(in)              :: nGRU            ! number of grouped response units
 integer(i4b),intent(in)              :: maxHRU          ! number of HRUs in the netCDF file
 integer(i4b),intent(in),optional     :: checkHRU        ! index of the HRU for single-HRU run
 ! define output
 type(gru_hru_double),intent(inout)   :: attrStruct      ! local attributes for each HRU
 type(gru_hru_int),intent(inout)      :: typeStruct      ! local classification of soil veg etc. for each HRU
 integer(i4b),intent(out)             :: err             ! error code
 character(*),intent(out)             :: message         ! error message
 ! define general variables
 real(dp),parameter                   :: missingDouble=-9999._dp  ! missing data
 integer(i4b),parameter               :: missingInteger=-9999     ! missing data
 character(len=256)                   :: cmessage        ! error message for downwind routine
 character(LEN=256)                   :: infile          ! input filename
 integer(i4b)                         :: ivars            ! loop through varibles in the netcdf file
 ! define local variables
 integer(i4b)                         :: ncid            ! netcdf file id
 integer(i4b)                         :: numDims         ! number of dimensions for netcdf variable
 integer(i4b)                         :: mode            ! netCDF file open mode
 integer(i4b)                         :: var_type        ! type of netcdf variable (e.g. integer, double, float)
 integer(i4b)                         :: varid           ! netcdf variable id
 character(LEN=nf90_max_name)         :: var_name        ! character array of netcdf variable name
 integer(i4b),parameter               :: categorical=101 ! named variable to denote categorical data
 integer(i4b),parameter               :: numerical=102   ! named variable to denote numerical data
 integer(i4b),allocatable             :: varType(:)      ! type of variable (categorical or numerical)
 integer(i4b),allocatable             :: varIndx(:)      ! index of variable within its data structure
 integer(i4b)                         :: nvar            ! number of variables in netcdf local attribute file
 integer(i4b)                         :: iAtt            ! index of an attribute name
 integer(i4b)                         :: ixSubset        ! index of the starting HRU of a GRU in global domain
 integer(i4b)                         :: localHRU        ! index of an HRU within a GRU
 integer(i4b)                         :: hruCount        ! index of an HRU within a GRU
 integer(i4b)                         :: iGRU            ! index of an GRU
 integer(i4b)                         :: nAtt            ! number of model attributes
 integer(i4b)                         :: nVar_attr       ! number of variables in the model attribute structure
 integer(i4b)                         :: nVar_type       ! number of variables in the model category structure
 logical(lgt),allocatable             :: checkType(:)    ! vector to check if we have all desired categorical values
 logical(lgt),allocatable             :: checkAttr(:)    ! vector to check if we have all desired local attributes
 ! define mapping variables
 integer(i4b),allocatable             :: hru_id(:)          ! unique id of hru over entire domain
 integer(i4b),allocatable             :: hru2gru_id(:)      ! unique GRU ids at each HRU
 integer(i4b),allocatable             :: hru_ix(:)          ! hru index for search
 integer(i4b)                         :: categorical_var(1) ! temporary categorical variable from local attributes netcdf file
 real(dp)                             :: numeric_var(1)     ! temporary numeric variable from local attributes netcdf file
 ! define indicators for different data structures
 integer(i4b),parameter               :: ixType=1           ! indicator for type_gru structure
 integer(i4b),parameter               :: ixAttr=2           ! indicator for attr_gru structure 
 integer(i4b), parameter              :: imiss = -999       ! missing value for variable id

 ! Start procedure here
 err=0; message="read_attrb/"

 ! **********************************************************************************************
 ! (0) get number of variables in each data structure
 ! **********************************************************************************************
 nVar_attr = size(attr_meta)
 nVar_type = size(type_meta)
 ! allocate space for the check vectors
 allocate(checkType(nVar_type),checkAttr(nVar_attr),stat=err)
 if(err/=0)then; err=20; message=trim(message)//'problem allocating space for variable check vectors'; return; endif
 checkType(:) = .false.
 checkAttr(:) = .false.

 ! total number of local attributes
 nAtt = nVar_attr + nVar_type

 ! **********************************************************************************************
 ! (1) open files, etc.
 ! **********************************************************************************************
 ! build filename
 infile = trim(SETNGS_PATH)//trim(LOCAL_ATTRIBUTES)
 ! open file
 mode=nf90_NoWrite
 call nc_file_open(trim(infile), mode, ncid, err, cmessage)
 if(err/=0)then; message=trim(message)//trim(cmessage); return; endif

 ! allocate space for hru-gru mapping vectors 
 allocate(hru_id(maxHRU),hru2gru_id(maxHRU),hru_ix(maxHRU),stat=err)
 if(err/=0)then; err=20; message=trim(message)//'problem allocating space for gru-hru mapping vectors'; return; endif

 ! **********************************************************************************************
 ! (2) read mapping vectors and populate mapping structures
 ! **********************************************************************************************

 ! read hruIndex from netcdf file
 err = nf90_inq_varid(ncid, "hruId", varid); if(err/=nf90_noerr)then; message=trim(message)//'problem finding hruId/'//trim(nf90_strerror(err)); return; endif
 err = nf90_get_var(ncid,varid,hru_id);      if(err/=nf90_noerr)then; message=trim(message)//'problem reading hruId/'//trim(nf90_strerror(err)); return; endif

 ! fill global mapping structures
 ! gru_struc contains the HRU index for HRUs in GRUs and the unique HRU id for each HRU in each GRU
 if (present(checkHRU)) then   
  ! single-HRU run 
  gru_struc(1)%hruInfo(1)%hru_id = hru_id(checkHRU)
  gru_struc(1)%hruInfo(1)%hru_ix = 1
  gru_struc(1)%hruInfo(1)%hru_nc = checkHRU
  index_map(1)%gru_ix   = 1      
  index_map(1)%localHRU = 1  
  
 else
  ! non-single HRU run
  
  ! read hru2gru_id from netcdf files
  err = nf90_inq_varid(ncid, "hru2gruId", varid); if(err/=nf90_noerr)then; message=trim(message)//'problem finding hru2gruId/'//trim(nf90_strerror(err)); return; endif
  err = nf90_get_var(ncid,varid,hru2gru_id);      if(err/=nf90_noerr)then; message=trim(message)//'problem reading hru2gruId/'//trim(nf90_strerror(err)); return; endif
  
  ixSubset=1              ! index of the starting HRU of a GRU in the global model domian
  hru_ix=arth(1,1,maxHRU) ! an array from 1 to maxHRU
  gruLoop: do iGRU=1,nGRU
   ! err check
   hruCount = count(hru2gru_id==gru_struc(iGRU)%gruId)
   if(hruCount/=gru_struc(iGRU)%hruCount)then
    write(message,'(3(a,i0))') trim(message)//'Expecting ',gru_struc(iGRU)%hruCount,' HRUs for GRU ',gru_struc(iGRU)%gruId,' but only found ',hruCount
    err=20; return
   endif
   ! get the mapping between local HRUs and global HRUs
   ! NOTE: gets the index in the NetCDF file (hru_nc) and the domain subset (hru_ix) for each HRU within a given GRU
   gru_struc(iGRU)%hruInfo(:)%hru_nc = pack(hru_ix,hru2gru_id == gru_struc(iGRU)%gruId)        ! indexes of HRUs in the netCDF file
   gru_struc(iGRU)%hruInfo(:)%hru_id = hru_id(gru_struc(iGRU)%hruInfo(:)%hru_nc)               ! HRU Ids
   gru_struc(iGRU)%hruInfo(:)%hru_ix = arth(ixSubset,1,gru_struc(iGRU)%hruCount)               ! indexes of HRUs in the global model domain
   ! get the mapping between global HRUs and the GRUs and local HRUs
   index_map(gru_struc(iGRU)%hruInfo(:)%hru_ix)%gru_ix = iGRU               ! mapping between global HRUs and the GRUs
   index_map(gru_struc(iGRU)%hruInfo(:)%hru_ix)%localHRU = hru_ix(1:hruCount) ! mapping between global HRUs and local HRUs
   ! increment index
   ixSubset = ixSubset + hruCount
  end do gruLoop
 end if

 ! **********************************************************************************************
 ! (3) read local attributes
 ! **********************************************************************************************

 ! run through netcdf file
 ! how many variables are there?
 err = nf90_inquire(ncid, nvariables=nvar)
 call netcdf_err(err,message); if (err/=0) return

 allocate(varType(nAtt),varIndx(nAtt), stat=err)
 if(err/=0)then; err=20; message=trim(message)//'unable to allocate space for the variable type and index'; return; endif
 ! initialize variables as missing
 varType(:) = missingInteger
 varIndx(:) = missingInteger

 ! allocate space for attributes
 if(err/=0)then; err=20; message=trim(message)//'unable to allocate space for netcdf attributes'; return; endif

 ! loop through variables in netcdf file and pull out local attributes
 iAtt = 1
 do ivars=1,nvar

  ! inqure about current variable name, type, number of dimensions
  err = nf90_inquire_variable(ncid,ivars,name=var_name,xtype=var_type,ndims=numDims)
  if(err/=nf90_noerr)then; message=trim(message)//'problem inquiring variable: '//trim(var_name)//'/'//trim(nf90_strerror(err)); return; endif

  ! find attribute name
  select case(trim(var_name))

   ! ** categorical data
   case('hruId','vegTypeIndex','soilTypeIndex','slopeTypeIndex','downHRUindex')

    ! get the index of the variable
    varType(iAtt) = categorical
    if(trim(var_name) == "hruId") then
     varIndx(iAtt) = get_ixType("hruIndex")
    else
     varIndx(iAtt) = get_ixType(var_name)
    end if
    checkType(varIndx(iAtt)) = .true.

    ! check that the variable could be identified in the data structure
    if(varIndx(iAtt) < 1)then; err=20; message=trim(message)//'unable to find variable ['//trim(var_name)//'] in data structure'; return; endif

    if(err/=0)then; err=20; message=trim(message)//'unable to allocate space for netcdf variable ['//trim(var_name)//']'; return; endif


    ! set attribute to GRU & HRU
    do iGRU=1,nGRU
     do localHRU = 1, gru_struc(iGRU)%hruCount
      ! grab variable from netcdf file
      err = nf90_get_var(ncid,ivars,categorical_var,start=(/gru_struc(iGRU)%hruInfo(localHRU)%hru_nc/),count=(/1/))
      if(err/=nf90_noerr)then; message=trim(message)//'problem reading: '//trim(var_name); return; endif
      typeStruct%gru(iGRU)%hru(localHRU)%var(varIndx(iAtt)) = categorical_var(1)
     end do
    end do
    iAtt = iAtt + 1

   ! ** numerical data
   case('latitude','longitude','elevation','tan_slope','contourLength','HRUarea','mHeight')

    ! get the index of the variable
    varType(iAtt) = numerical
    varIndx(iAtt) = get_ixAttr(var_name)
    checkAttr(varIndx(iAtt)) = .true.

    ! check that the variable could be identified in the data structure
    if(varIndx(iAtt) < 1)then; err=20; message=trim(message)//'unable to find variable ['//trim(var_name)//'] in data structure'; return; endif


    ! set attribute to GRU & HRU
    do iGRU=1,nGRU
     do localHRU = 1, gru_struc(iGRU)%hruCount      
      ! grab variable from netcdf file
      err = nf90_get_var(ncid,ivars,numeric_var,start=(/gru_struc(iGRU)%hruInfo(localHRU)%hru_nc/),count=(/1/))
      if(err/=nf90_noerr)then; message=trim(message)//'problem reading: '//trim(var_name)//'/'//trim(nf90_strerror(err)); return; endif
      attrStruct%gru(iGRU)%hru(localHRU)%var(varIndx(iAtt)) = numeric_var(1)
     end do
    end do
    iAtt = iAtt + 1

   ! for mapping varibles, do nothing (information read above)
   case('hru2gruId','gruId'); cycle

   ! check that variables are what we expect
   case default; message=trim(message)//'unknown variable ['//trim(var_name)//'] in local attributes file'; err=20; return

  end select ! select variable

 end do ! (looping through netcdf local attribute file)

 ! check that we have all desired categorical variables
 if(any(.not.checkType))then
  do iAtt=1,nVar_type
   if(.not.checkType(iAtt))then; err=20; message=trim(message)//'missing variable ['//trim(type_meta(iAtt)%varname)//'] in local attributes file'; return; endif
  end do
 endif

 ! check that we have all desired local attributes
 if(any(.not.checkAttr))then
  do iAtt=1,nVar_attr
   if(.not.checkAttr(iAtt))then; err=20; message=trim(message)//'missing variable ['//trim(attr_meta(iAtt)%varname)//'] in local attributes file'; return; endif
  end do
 endif

 ! **********************************************************************************************
 ! (5) deallocate space
 ! **********************************************************************************************
 deallocate(varType,varIndx,checkType,checkAttr, stat=err)
 if(err/=0)then; err=20; message=trim(message)//'problem deallocating space'; return; endif

 end subroutine read_attrb

end module read_attrb_module
