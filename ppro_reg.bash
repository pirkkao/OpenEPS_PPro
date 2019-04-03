#!/bin/bash

# Post-processing script for individual ensemble member treatment
# REQUIRES CDO

steps=${1:-"0000"}
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

# Load eccodes and cdo
module load intel/18.0.1 >/dev/null 2>&1
module load intelmpi/18.0.1
module load eccodes/2.9.2
module load cdo

# Process all steps
#
for step in $steps; do
    if [ $verbose != "none" ]; then printf '%s\n' "    processing step $step"; fi

    # convert to GRIB1
    grib_set -s edition=1 ICMSH${EXPS}+00${step} temp1_$step.grb1
    grib_set -s edition=1 ICMGG${EXPS}+00${step} temp2_$step.grb1

    # Select pressure and surface level variables
    cdo $v1 -selzaxis,pressure temp1_$step.grb1 temp1_$step.grb
    cdo $v1 -selzaxis,pressure temp2_$step.grb1 temp2_$step.grb
    cdo $v1 -selzaxis,surface  temp2_$step.grb1 temp_srf_$step.grb
    
    # Do a spectral transform to gg
    if [ $RES -eq 21 ] || [ $RES -eq 42 ] ; then
	cdo $v2 -sp2gp  temp1_$step.grb temp_gg_$step.grb
    else
	cdo $v2 -sp2gpl temp1_$step.grb temp_gg_$step.grb
    fi

    # Transform reduced GG to regular gaussian
    cdo $v1 -R copy temp2_$step.grb temp3_$step.grb

    # Merge
    cdo $v1 -merge temp_gg_$step.grb temp3_$step.grb temp4_$step.grb 

    # Regularize to 1*/1* lat-lon grid
    cdo $v2    -remapbil,r360x181 temp4_$step.grb     PP_pl+00${step}
    cdo $v2 -R -remapbil,r360x181 temp_srf_$step.grb  PP_srf+00${step}


    rm -f temp*_$step.grb temp*_$step.grb1
done
