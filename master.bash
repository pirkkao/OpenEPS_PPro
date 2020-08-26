#!/bin/bash
#SBATCH -p serial
#SBATCH -J t639_eda+sv
#SBATCH -t 14:00:00
#SBATCH -n 11
#SBATCH --mem-per-cpu=4000

# Get CONFIG
source ${1:-config}

#*********************************************************************************
# Construct timestep list
#*********************************************************************************

# Performance
start=$SECONDS

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

# Create job folder
test -d tmp_${exp} || mkdir tmp_${exp}

# NEW formulation 
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
	imem=$smem
	while [ $imem -le $nmem ]; do
	    fmem=$(printf '%03d' $imem) 

            # Loop over step blocks
	    for item in $(seq 0 $((${#steplist3[*]}-1))); do
		fitem=$(printf '%02d' $item)

		cat > tmp_${exp}/task_${fmem}_$fitem <<EOF
#!/bin/bash
printf '\n%.70s%s\n' "  Processing member $fmem for time steps ${steplist3[$item]}" "..."
printf '%s\n'   "  $(date | awk '{print $4}')"

cd $pathtoexp/$date/pert$fmem
$cpath/ppro_reg.bash "${steplist3[$item]}" $verbose

EOF
	        # parallel requires wider user rights
		chmod 755 tmp_${exp}/task_${fmem}_$fitem

	        # create a task list for parallel
		tasklist="$tasklist $cpath/tmp_${exp}/task_${fmem}_$fitem"

	    done
	    imem=$(($imem + 1))
	done

	# Use GNU parallel to go through the task list
	parallel -j $SLURM_NTASKS ::: $tasklist

	rm -f tmp_${exp}/task*
    fi


    #****************************************************************************
    # Calculate ensemble statistics
    #
    if $pp_ens; then
	printf '\n%s\n' "PROCESSING ENSEMBLE STATISTICS"

	rm -f $pathtoexp/$date/PP_*

	# Loop over step blocks and create sub tasks for parallel
	tasklist=""
	for item in $(seq 0 $((${#steplist3[*]}-1))); do
	    fitem=$(printf '%02d' $item)
	    cat > tmp_${exp}/ens_$fitem <<EOF
#!/bin/bash
printf '\n%.70s%s\n' "  Processing ensemble statistics for steps ${steplist3[$item]}" "..."
printf '%s\n'   "  $(date | awk '{print $4}')"

cd $pathtoexp/$date
$cpath/ppro_ens.bash "${steplist3[$item]}" $verbose

EOF
	    # parallel requires wider user rights
	    chmod 755 tmp_${exp}/ens_$fitem
	    
	    # create a task list for parallel
	    tasklist="$tasklist $cpath/tmp_${exp}/ens_$fitem"
	done

	# Use GNU parallel to go through the task list
	parallel -j $SLURM_NTASKS ::: $tasklist

	rm -f tmp_${exp}/ens*
    fi


    #****************************************************************************
    # Collect steps
    #
    if $pp_steps; then
	printf '\n%s\n' "COLLECTING STEPS"

        # Make date dir
	export ddir=$basepath/$exp/$date
	test -d $ddir      || mkdir -p $ddir
	test -d $ddir/grib || mkdir -p $ddir/grib

	tasklist=""
	# Loop over ensemble members
	imem=$smem
	while [ $imem -le $nmem ]; do
	    fmem=$(printf '%03d' $imem) 
	    
	    cat > tmp_${exp}/steps_$fmem <<EOF
#!/bin/bash
printf '\n%s\n' " Collecting time steps for member $fmem"
printf '%s\n'   "  $(date | awk '{print $4}')"

$cpath/ppro_collect_steps.bash $fmem $verbose

EOF
            # parallel requires wider user rights
            chmod 755 tmp_${exp}/steps_${fmem}

	    # create a task list for parallel
	    tasklist="$tasklist $cpath/tmp_${exp}/steps_${fmem}"
	    
	    imem=$(($imem + 1))
	done

	# Loop over ctrl, ensmean and ensstd
	for item in "ctrl" "ensmean" "ensstd"; do

	    cat > tmp_${exp}/steps_$item <<EOF
#!/bin/bash
printf '\n%s\n' " Collecting time steps for $item"
printf '%s\n'   "  $(date | awk '{print $4}')"

$cpath/ppro_collect_steps.bash "$item" $verbose

EOF
            # parallel requires wider user rights
            chmod 755 tmp_${exp}/steps_${item}

	    # create a task list for parallel
	    tasklist="$tasklist $cpath/tmp_${exp}/steps_${item}"
	done

	# Use GNU parallel to go through the task list
	parallel -j $SLURM_NTASKS ::: $tasklist

	rm -f tmp_${exp}/steps*
    fi

    date=$($mandtg $date + $dstep)
done

duration=$(( SECONDS - start ))

printf '\n%s\n' "FINISHED with config pbash: $parallel_bash and pstep: $parallel_step in $duration"
