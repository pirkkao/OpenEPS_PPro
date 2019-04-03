#!/bin/bash
#
# Post-process OEPS run output.
#
# This scripts collects the PP_ctrl, PP_ensmean, and PP_stddev files
# produced by OEPS runs, or the individual PP files from each ens member. 
# The output is concatenated and turned into nc-format.
#

item=${1:-"ctrl"}
verbose=${2:-"none"}
ncdo=${3:-1} # CDO openMP does not save any time on the tests 
             # I've made, don't implement this now

if [ $verbose == full ]; then
    # Print all
    v1=""
    v2=""
    date | awk '{print $4}'
elif [ $verbose == half ]; then
    # Silence non-time critical jobs
    v1=-s
    v2=""
    date | awk '{print $4}'
else
    # Silence all
    v1=-s
    v2=-s
fi

module load cdo

# Different treatment for ensemble member and ensemble statistics
if [ $item != ctrl ] && [ $item != ensmean ] && [ $item != ensstd ]; then 
    printf '\n%s\n' "Processing member number $item"

    # Merge all PP files found in the member dir
    rm -f $ddir/grib/PP_pert$item.grib

    cdo $v1 -mergetime $pathtoexp/$date/pert$item/PP_pl* $ddir/grib/PP_pert$item.grib

    # Copy to nc
    cdo $v2 -f nc copy $ddir/grib/PP_pert$item.grib $ddir/p$item.nc

else
    printf '\n%s\n' "Processsing $item"
	
    rm -f $ddir/grib/PP_$item.grib

    # Merge all PP files found in the date folder
    cdo $v1 -mergetime $pathtoexp/$date/PP_pl_$item+* $ddir/grib/PP_$item.grib

    # Copy to nc
    cdo $v2 -f nc copy $ddir/grib/PP_$item.grib $ddir/$item.nc
fi

