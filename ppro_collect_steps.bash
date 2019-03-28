#!/bin/bash
#
# Post-process OEPS run output.
#
# This scripts collects the PP_ctrl, PP_ensmean, and PP_stddev files
# produced by OEPS runs, or the individual PP files from each ens member. 
# The output is concatenated and turned into nc-format.
#

item=${1:-"ctrl"}

module load cdo

# Different treatment for ensemble member and ensemble statistics
if [ $item != "ctrl" ] || [ $item != "ensmean" ] || [ $item != "ensstd" ]; then 
    printf '\n%s\n' "Processing member number $item"

    # Merge all PP files found in the member dir
    rm -f $ddir/grib/PP_pert$item.grib

    cdo -mergetime $pathtoexp/$exp/data/$date/pert$item/PP_pl* $ddir/grib/PP_pert$item.grib

    # Copy to nc
    cdo -f nc copy $ddir/grib/PP_pert$item.grib $ddir/p$item.nc

else
    printf '\n%s\n' "Processsing $item"
	
    rm -f $ddir/grib/PP_$item.grib

    # Merge all PP files found in the date folder
    cdo -mergetime $pathtoexp/$exp/data/$date/PP_pl_$item+* $ddir/grib/PP_$item.grib

    # Copy to nc
    cdo -f nc copy $ddir/grib/PP_$item.grib $ddir/$item.nc
fi

