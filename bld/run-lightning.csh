#! /bin/tcsh -f
#
#=======================================================================
#
#  run-lightning.csh
#
#  Generic batch submission script for lightning using LSF.  
#
#-----------------------------------------------------------------------
# Batch options for machine with LSF batch system. 
# Usage for PathScale compiler (default): 
#   bsub < run-lightning.csh
#-----------------------------------------------------------------------
#
#BSUB -a mpich_gm
#BSUB -x
#BSUB -n 2,4
#BSUB -R "span[ptile=2]"
#BSUB -o clm.o%J
#BSUB -e clm.e%J
#BSUB -q regular
#BSUB -W 0:10                   # wall clock limit
#BSUB -P xxxxxxxx               # Project number to charge to
#
#=======================================================================

setenv INC_NETCDF /contrib/2.6/netcdf/3.6.0-p1-pathscale-2.4-64/include
setenv LIB_NETCDF /contrib/2.6/netcdf/3.6.0-p1-pathscale-2.4-64/lib
set mpich=/contrib/2.6/mpich-gm/1.2.6..14a-pathscale-2.4-64
setenv INC_MPI ${mpich}/include
setenv LIB_MPI ${mpich}/lib
set ps=/contrib/2.6/pathscale/2.4
setenv PATH ${mpich}/bin:${ps}/bin:/usr/bin:/bin:${PATH}
setenv LD_LIBRARY_PATH ${ps}/lib/2.4:${LD_LIBRARY_PATH}

## ROOT OF CLM DISTRIBUTION - probably needs to be customized.
## Contains the source code for the CLM distribution.
## (the root directory contains the subdirectory "src")
set clmroot   = /fis/cgd/...

## ROOT OF CLM DATA DISTRIBUTION - needs to be customized unless running at NCAR.
## Contains the initial and boundary data for the CLM distribution.
setenv CSMDATA /fs/cgd/csm/inputdata/lnd/clm2

## Default configuration settings:
set spmd     = on       # settings are [on   | off       ] (default is off)
set maxpft   = 4        # settings are 4->17               (default is 4)
set bgc      = none     # settings are [none | cn | casa ] (default is none)
set supln    = off      # settings are [on   | off       ] (default is off)
set dust     = off      # settings are [on   | off       ] (default is off)   
set voc      = off      # settings are [on   | off       ] (default is off)   
set rtm      = off      # settings are [on   | off       ] (default is off)   

set res      = 48x96    # settings are [48x96, 64x128, 4x5, 10x15, 1.9x2.5, etc.]

## $wrkdir is a working directory where the model will be built and run.
## $blddir is the directory where model will be compiled.
## $rundir is the directory where the model will be run.
## $cfgdir is the directory containing the CLM configuration scripts.
set case     = clmrun
set wrkdir   = /ptmp/$LOGNAME
set blddir   = $wrkdir/$case/bld
set rundir   = $wrkdir/$case
set cfgdir   = $clmroot/bld
set usr_src  = $clmroot/bld/usr.src


## Ensure that run and build directories exist
mkdir -p $rundir                || echo "cannot create $rundir" && exit 1
mkdir -p $blddir                || echo "cannot create $blddir" && exit 1

## Build (or re-build) executable
set flags = "-fc pathf90 -linker mpif90 "
set flags = "$flags -maxpft $maxpft -bgc $bgc -supln $supln -voc $voc -rtm $rtm -dust $dust -usr_src $usr_src"
if ($spmd == on)  set flags = "$flags -spmd"
if ($spmd == off) set flags = "$flags -nospmd"

echo "cd $blddir"
cd $blddir                  || echo "cd $blddir failed" && exit 1
set config="$blddir/config_cache.xml"
if ( ! -f $config ) then
    echo "flags to configure are $flags"
    $cfgdir/configure $flags    || echo "configure failed" && exit 1
    echo "Building CLM in $blddir ..."
    gmake -j8 >&! MAKE.out      || echo "CLM build failed: see $blddir/MAKE.out" && exit 1
else
    echo "Re-building CLM in $blddir ..."
    rm -f Depends
    gmake -j8 >&! REMAKE.out      || echo "CLM build failed: see $blddir/REMAKE.out" && exit 1
endif

## Create the namelist
cd $rundir                      || echo "cd $blddir failed" && exit 1

set finidat        = `$cfgdir/queryDefaultNamelist.pl -res $res -silent -options "MASK=USGS" -config $config -csmdata $CSMDATA -var finidat`
set fsurdat        = `$cfgdir/queryDefaultNamelist.pl -res $res -silent -config $config -csmdata $CSMDATA -var fsurdat`
set fatmgrid       = `$cfgdir/queryDefaultNamelist.pl -res $res -silent -config $config -csmdata $CSMDATA -var fatmgrid`
set fatmlndfrc     = `$cfgdir/queryDefaultNamelist.pl -res $res -silent -options "MASK=USGS" -config $config -csmdata $CSMDATA -var fatmlndfrc`
set fpftcon        = `$cfgdir/queryDefaultNamelist.pl -res $res -silent -config $config -csmdata $CSMDATA -var fpftcon`
set fndepdat       = `$cfgdir/queryDefaultNamelist.pl -res $res -silent -config $config -csmdata $CSMDATA -var fndepdat`
set offline_atmdir = `$cfgdir/queryDefaultNamelist.pl -res $res -silent -config $config -csmdata $CSMDATA -var offline_atmdir`
set frivinp_rtm    = `$cfgdir/queryDefaultNamelist.pl -res $res -silent -config $config -csmdata $CSMDATA -var frivinp_rtm`

cat >! lnd.stdin << EOF
 &clm_inparm
 caseid         = '$case'
 ctitle         = '$case'
 $finidat
 $fsurdat
 $fatmgrid
 $fatmlndfrc
 $fpftcon
 $fndepdat
 $offline_atmdir
 $frivinp_rtm
 nsrest         =  0
 nelapse        =  48
 dtime          =  1800
 start_ymd      =  19980101
 start_tod      =  0
 irad           = -1
 wrtdia         = .true.
 mss_irt        =  0
 hist_dov2xy    = .true.
 hist_nhtfrq    =  -24
 hist_mfilt     =  1
 hist_crtinic   = 'MONTHLY'
 /
 &prof_inparm
 /
EOF

## Run CLM 
cd $rundir                              || echo "cd $rundir failed" && exit 1
echo "running CLM in $rundir"

if ($spmd == on) then
  mpirun.lsf -np 2 $blddir/clm  || echo "CLM run failed" && exit 1
else
  $blddir/clm                   || echo "CLM run failed" && exit 1
endif

exit 0
