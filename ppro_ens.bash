#!/bin/bash

# Post-processing script for ensemble mean and spread calculation
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

SUBDIR_NAME=pert

module load cdo

# Process all steps
#
for step in $steps; do
   if [ $verbose != "none" ]; then printf '%s\n' "    processing step $step"; fi

   # Constuct namelist for statistics calculations
   enslist=""
   srflist=""
   for imem in $(seq 0 $nmem); do
      imem=$(printf "%03d" $imem)
      enslist="$enslist $SUBDIR_NAME${imem}/PP_pl+00$step "
      srflist="$srflist $SUBDIR_NAME${imem}/PP_srf+00$step "
   done
	
   # Calculate ensemble mean
   cdo $v2 -ensmean ${enslist} PP_pl_ensmean+00$step
   cdo $v1 -ensmean ${srflist} PP_srf_ensmean+00$step
	
   # Calculate ensemble stdev
   cdo $v2 -ensstd ${enslist} PP_pl_ensstd+00$step
   cdo $v1 -ensstd ${srflist} PP_srf_ensstd+00$step

   # Copy the ctrl pp to date-folder
   cp -f ${SUBDIR_NAME}000/PP_pl+00${step}  PP_pl_ctrl+00$step
   cp -f ${SUBDIR_NAME}000/PP_srf+00${step} PP_srf_ctrl+00$step
done
