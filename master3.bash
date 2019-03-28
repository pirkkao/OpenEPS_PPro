#!/bin/bash
#SBATCH -p serial
#SBATCH -J p7
#SBATCH -t 0:10:00
#SBATCH -n 4
#SBATCH --mem-per-cpu=3000


#*********************************************************************************
# CONFIG
#*********************************************************************************

# Basic settings
#
export EXPS=eps2
export RES=159
#export exp=prod_t399_eda+sv_sisu
export exp=prod_t159_sv_sisu


# Parallelism
#
# Number of bash tasks for individual members
parallel_bash=2
# Number of bash tasks for forecast step processing
parallel_step=2


# Define start and end dates and hours between two dates
#
 date=2017120100
edate=2017120100
dstep=192

# Forecast length and time interval, both in [hours]
fclen=240 
fcstep=6 


# Number of ens members (fetch data for 0...nmem)
#
export nmem=2


# Data output frequency; 1h in model steps
# TL159: 1
# TL399: 3
if [ $RES -eq 159 ]; then
    dfcstep=1
elif [ $RES -eq 399 ]; then
    dfcstep=3
fi


# Post-processing options
#
# individual member pp
pp_mem=true
# ensemble pp (ensmean and std)
pp_ens=true
# collect steps
pp_steps=true


#*********************************************************************************
# Setup paths
#*********************************************************************************
export pathtoexp=$WRKDIR/openEPS
export basepath=$WRKDIR/DONOTREMOVE/oeps_pp

cpath=`pwd`
mandtg=$cpath/mandtg

test -d $basepath/$exp || mkdir -p $basepath/$exp


#*********************************************************************************
# Construct timestep list
#*********************************************************************************

## Old formulation without parallel
#istep=0
#step=$(printf '%04d' $istep)
#
#steplist=""
#while [ -e $pathtoexp/$exp/data/$date/pert000/ICMSH${EXPS}+00${step} ]; do
#
#    steplist="$steplist $step"
#    
#    istep=$(($istep + $dfcstep))
#    step=$(printf '%04d' $istep)
#done

# NEW formulation 
#
# fclen in model timesteps
fclen=$(($fclen * $dfcstep))

# Formulate a list containing all asked forecast steps
istep=0
steplist2=()

while [ $istep -le $fclen ]; do
    sstep=$(printf '%04d' $istep)

    steplist2+=($sstep)
    
    istep=$(($istep + $fcstep * $dfcstep))
done

# Setup a bash array
steplist3=()
step_blocks=$parallel_step

# Calculate total need of blocks
steps_per_block=$((${#steplist2[*]} / ${step_blocks}))

# Loop over parallel step blocks
for block in $(seq 1 ${step_blocks}); do
    tmp_list=""

    # Construct step list for given block
    #
    # Add zeroeth element to first array
    if [ $block -eq 1 ]; then
	tmp_list="$tmp_list ${steplist2[0]}"
    fi
	
    # Loop over steps
    for step in $(seq 1 ${steps_per_block}); do

	# Construct index list for splitting the timesteps
	index1=$((($block - 1) * ${steps_per_block}))
	index2=$(($index1 + $step))

	# Add to temporary list
	tmp_list="$tmp_list ${steplist2[$index2]}"
    done

    # Expand last block to encompass last elements
    if [ $block -eq ${step_blocks} ]; then
	while [ $index2 -lt ${#steplist2[*]} ]; do
	    index2=$(($index2 + 1))
	    tmp_list="$tmp_list ${steplist2[$index2]}"
	done
    fi

    # Concatenate to master array
    steplist3+=("$tmp_list")

done

printf '\n%s\n' "Splitting time steps as"
for item in $(seq 0 $((${#steplist3[*]}-1))); do
    printf '%s\n' "Block $(($item+1)), steps ${steplist3[$item]}"
done


#*********************************************************************************
# COMPUTATIONS
#*********************************************************************************

# Loop over dates
#
while [ $date -le $edate ]; do

    printf '\n%s\n' "ON DATE $date"
    export date

    #****************************************************************************
    # Post-process task for each individual ensemble member and time step
    #
    if $pp_mem; then
	printf '\n%s\n' "PROCESSING ENSEMBLE MEMBERS"
       
	# Create parallel tasks
	#
	tasklist=""
	
	# Loop over members
	imem=0
	while [ $imem -le $nmem ]; do
	    fmem=$(printf '%03d' $imem) 

            # Loop over step blocks
	    for item in $(seq 0 $((${#steplist3[*]}-1))); do
		fitem=$(printf '%02d' $item)

		cat > tmp/task${fmem}_$fitem <<EOF
#!/bin/bash
printf '\n%s\n' " Processing member $fmem for time steps ${steplist3[$item]}"
date

cd $pathtoexp/$exp/data/$date/pert$fmem
$cpath/ppro_reg.bash "${steplist3[$item]}"

EOF
	        # parallel requires wider user rights
		chmod 755 tmp/task${fmem}_$fitem

	        # create a task list for parallel
		tasklist="$tasklist $cpath/tmp/task${fmem}_$fitem"

	    done
	    imem=$(($imem + 1))
	done
	echo $(($parallel_bash * $step_blocks)) $tasklist

	# Use GNU parallel to go through the task list
	parallel -j $(($parallel_bash * $step_blocks)) ::: $tasklist

	#rm -f tmp/task*
    fi


    #****************************************************************************
    # Calculate ensemble statistics
    #
    if $pp_ens; then
	printf '\n%s\n' "PROCESSING ENSEMBLE STATISTICS"

	rm -f $pathtoexp/$exp/data/$date/PP_*

	# Loop over step blocks and create sub tasks for parallel
	tasklist=""
	for item in $(seq 0 $((${#steplist3[*]}-1))); do
	    fitem=$(printf '%02d' $item)
	    cat > tmp/ens_$fitem <<EOF
#!/bin/bash
printf '\n%s\n' " Processing ensemble statistics for steps ${steplist3[$item]}"
date

cd $pathtoexp/$exp/data/$date
$cpath/ppro_ens.bash "${steplist3[$item]}"

EOF
	    # parallel requires wider user rights
	    chmod 755 tmp/ens_$fitem
	    
	    # create a task list for parallel
	    tasklist="$tasklist $cpath/tmp/ens_$fitem"
	done

	# Use GNU parallel to go through the task list
	parallel -j $step_blocks ::: $tasklist

	#rm -f tmp/ens*
    fi


    #****************************************************************************
    # Collect steps
    #
    if $pp_steps; then
	printf '\n%s\n' "COLLECTING STEPS"

        # Make date dir
	ddir=$basepath/$exp/$date
	test -d $ddir      || mkdir -p $ddir
	test -d $ddir/grib || mkdir -p $ddir/grib


	tasklist=""

	# Loop over ensemble members
	imem=0
	while [ $imem -le $nmem ]; do
	    fmem=$(printf '%03d' $imem) 
	    
	    cat > tmp/steps_$fmem <<EOF
#!/bin/bash
printf '\n%s\n' " Collecting time steps for member $fmem"
date

EOF
	    
	    imem=$(($imem + 1))
	done

	# Loop over ctrl, ensmean and ensstd
	for item in "ctrl ensmean ensstd"; do
	    echo $item
	done

	#$cpath/ppro_collect_steps.bash
    fi

    date=$($mandtg $date + $dstep)
done

printf '\n%s\n' "FINISHED"