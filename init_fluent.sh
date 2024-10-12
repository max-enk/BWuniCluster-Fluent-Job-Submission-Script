#!/bin/bash

# This script can automatically start eligible simulations on the BWuniCluster
# Run it in the parent folder, where all simulations folders are located
# The script requires a certain folder topology to be set up for the simulations:
# parent folder
#   - this script
#   - simulation_status.txt (will be created)
#   - S000-1ref (exemplary simulation name, max. 16 characters)
#       - folder "simulation"
#           - *.dat.h5 files (in case of prior or current runs)   
#       - *-1.cas.h5 file of S000-1ref   
#       - all the scripts below (initial_start, ...)
#       - log*.txt files (in case of prior or current runs)     
#   - other folders
# The script assumes that start and config scripts are set up correctly. References are in this folder.
# The script creates a status file in the parent folder. Do not change the file while the script is running.

initial_start=run_initial_fluent.sh                         # Start script for initial run
initial_cfg=initial-parallel.jou                            # Initial Fluent configuration file 
consecutive_start=run_consecutive_fluent.sh                 # Start script for consecutive run
consecutive_cfg=consecutive-parallel.jou                    # Consecutive Fluent configuration file


# Do not edit below
########################################################################################################################################################################################################


# Change to the directory where the script is located
cd "$(dirname "$0")"

# Find all folders and store their names in an array
folders=($(find . -maxdepth 1 -type d ! -path . -exec basename {} \;))

# Sort the array of folder names by length first, then alphabetically
sorted_folders=($(printf '%s\n' "${folders[@]}" | awk '{ print length, $0 }' | sort -n -k1,1 -k2 | awk '{ $1=""; print $0 }'))

# Print the number of folders and their names to console
echo "Found ${#sorted_folders[@]} folder(s):"
echo "${sorted_folders[@]}"
echo ""

# Arrays to store simulations with different properties
simulations_initial=()          # Simulations to be run initially
simulations_consecutive=()      # Simulations to be run consecutively
simulations_queued=()           # Simulations already submitted but still in queue
simulations_running=()          # Simulations that are currently running
simulations_ended=()            # Simulations that have ended
other=()                        # Folders that are no simulation folders

# Write status file header 
echo "Simulation      Status          Run     Time/Total Time     Nodes   Cores/Node  CPU Time (DD-HH:MM:SS)  " > "simulation_status.txt"

# Classifying simulations based in their state
for sim in "${sorted_folders[@]}"; do
    
    cd "$sim"
    
    # check if folder is a simulation folder. Conditions: simulation folder, case file and starting scripts exist
    if [ -d "simulation" ] && [ -e *.cas.h5 ] && [ -f "$consecutive_cfg" ] && [ -f "$initial_cfg" ] && [ -f "$consecutive_start" ] && [ -f "$initial_start" ]; then
        
        # First entry of status line in simulation_status.txt is the simulation name. max. 16 characters for name
        sim_status="$(printf "%-16s" "$sim")"
        
        # Find log*.txt files in the simulation folder, indicating a previous run
        log_files=($(find . -name "log*.txt" -type f))

        # Check for previous run. Condition: at least one log*.txt file exists
        if [[ ${#log_files[@]} -gt 0 ]]; then

            # Get the number of total previous or current
            num_runs=${#log_files[@]}

            # Obtain the name of the newest *.dat.h5 file in the simulation folder
            cd "simulation"
            dat_count=$(find . -maxdepth 1 -type f -name "*.dat.h5" | wc -l)

            if [[ $dat_count -gt 0 ]]; then
                newest_data=$(ls -t | grep ".dat.h5" | head -n 1)
                newest_time=$(echo "$newest_data" | awk -F"-" '{print $NF}' | sed 's/\.dat\.h5//')
            else
                newest_time="0.000000"
            fi
            cd ..

            # Read the maximum simulation time from consecutive_cfg
            sim_time=$(grep "/solve/dual-time-iterate" $consecutive_cfg | awk '{print $2}')
            
            # Check if simulation is running. Condition: any log file is newer than one minute
            running=false
            for log_file in "${log_files[@]}"; do
                if [[ $(find "$log_file" -mmin -1) ]]; then
                    running=true
                    break
                fi
            done

            # Find and collect SLURM output files
            slurm_files=($(find . -maxdepth 1 -type f -name "slurm*.out" -printf '%P\n'))
            tot_days=
            tot_hrs=
            tot_min=
            tot_sec=

            # In case SLURM files exist, add up the runtimes 
            if [[ ${#slurm_files[@]} -gt 0 ]]; then
                for sfile in "${slurm_files[@]}"; do
                    # get current time in SLURM file, only if it includes that value 
                    if grep -q "Job Wall-clock time:" $sfile; then
                        # Total simulation runtime in file
                        jobtime="$(grep "Job Wall-clock time:" $sfile | awk '{print $4}')"
                        # Days, Hours, Minutes, Seconds in total time
                        if [[ $jobtime == *-* ]]; then
                            days=$(echo "$jobtime" | cut -d'-' -f1)
                            hms=$(echo "$jobtime" | cut -d'-' -f2)
                        else
                            days=0
                            hms=$jobtime
                        fi
                        hrs=${hms:0:2}
                        min=${hms:3:2}
                        sec=${hms:6:2}

                        # remove leading zeroes
                        if [[ $hrs == 0[0-9] ]]; then
                            hrs=${hrs:1} 
                        fi
                        if [[ $min == 0[0-9] ]]; then
                            min=${min:1} 
                        fi
                        if [[ $sec == 0[0-9] ]]; then
                            sec=${sec:1} 
                        fi

                        # Adding to total values
                        tot_sec=$(($tot_sec+$sec))
                        if (($tot_sec >= 60)); then
                            tot_sec=$(($tot_sec-60))
                            tot_min=$(($tot_min+1))
                        fi
                        tot_min=$(($tot_min+$min))
                        if (($tot_min >= 60)); then
                            tot_min=$(($tot_min-60))
                            tot_hrs=$(($tot_hrs+1))
                        fi
                        tot_hrs=$(($tot_hrs+$hrs))
                        if (($tot_hrs >= 24)); then
                            tot_hrs=$(($tot_hrs-24))
                            tot_days=$(($tot_days+1))
                        fi
                        tot_days=$(($tot_days+$days))
                    fi
                done
            fi

            if [[ $running == true ]]; then               
                # Add simulation to array of simulations currently running
                simulations_running+=("$sim")

                # Update status with state "running"
                sim_status+="$(printf "%-16s" "running")"

                # Total current simulation runtime in squeue
                jobtime="$(squeue -o "%.18i %.9P %.12j %.8u %.2t %.10M %.6D %R" | grep $sim | awk '{print $6}')"
                # Days, Hours, Minutes, Seconds in total time
                if [[ $jobtime == *-* ]]; then
                    days=$(echo "$jobtime" | cut -d'-' -f1)
                    hms=$(echo "$jobtime" | cut -d'-' -f2)
                else
                    days=0
                    hms=$jobtime
                fi

                # Accounting for hms being in different formats due to simulation runtime
                if [[ ${#hms} -eq 7 ]]; then
                    hms="0${hms}"
                    hrs=${hms:0:2}
                    min=${hms:3:2}
                    sec=${hms:6:2}
                else 
                    if [[ ${#hms} -eq 5 ]]; then
                        hrs="00"
                        min=${hms:0:2}
                        sec=${hms:3:2}
                    else
                        if [[ ${#hms} -eq 4 ]]; then
                            hms="0${hms}"
                            hrs="00"
                            min=${hms:0:2}
                            sec=${hms:3:2}
                        else
                            hrs=${hms:0:2}
                            min=${hms:3:2}
                            sec=${hms:6:2}
                        fi
                    fi
                fi

                # remove leading zeroes
                if [[ $hrs == 0[0-9] ]]; then
                    hrs=${hrs:1} 
                fi
                if [[ $min == 0[0-9] ]]; then
                    min=${min:1} 
                fi
                if [[ $sec == 0[0-9] ]]; then
                    sec=${sec:1} 
                fi

                # Adding to total values
                tot_sec=$(($tot_sec+$sec))
                if (($tot_sec >= 60)); then
                    tot_sec=$(($tot_sec-60))
                    tot_min=$(($tot_min+1))
                fi
                tot_min=$(($tot_min+$min))
                if (($tot_min >= 60)); then
                    tot_min=$(($tot_min-60))
                    tot_hrs=$(($tot_hrs+1))
                fi
                tot_hrs=$(($tot_hrs+$hrs))
                if (($tot_hrs >= 24)); then
                    tot_hrs=$(($tot_hrs-24))
                    tot_days=$(($tot_days+1))
                fi
                tot_days=$(($tot_days+$days))

            else   
                # Check if simulation has ended
                if (( $(bc <<< "$newest_time >= $sim_time - 0.005") )); then
                    # Add simulation to array of simulations that have ended
                    simulations_ended+=("$sim")
                    
                    # Update status with state "ended"
                    sim_status+="$(printf "%-16s" "ended")"
                else
                    # Check if simulation has been submitted before
                    if squeue -o "%.18i %.9P %.12j %.8u %.2t %.10M %.6D %R" | grep -q "$sim"; then
                        # Add simulation to array of simulations that are queued
                        simulations_queued+=("$sim")
                        
                        # Update status with state "queued"
                        sim_status+="$(printf "%-16s" "queued")"
                    else
                        # Add simulation to array of simulations to be run consecutively
                        simulations_consecutive+=("$sim")
                        
                        # Update status with state "consecutive"
                        sim_status+="$(printf "%-16s" "consecutive")"
                    fi             
                fi

                
            fi

            # Formatting CPU time
            if [[ ${#tot_sec} -eq 1 ]]; then
                tot_sec="0${tot_sec}"
            fi
            if [[ ${#tot_min} -eq 1 ]]; then
                tot_min="0${tot_min}"
            fi
            if [[ ${#tot_hrs} -eq 1 ]]; then
                tot_hrs="0${tot_hrs}"
            fi
            if [[ ${#tot_days} -eq 1 ]]; then
                tot_days="0${tot_days}"
            fi
            # set calculated CPU time
            CPU_time="$tot_days-$tot_hrs:$tot_min:$tot_sec"

            # Update status with the number of runs, simulation time and node values
            sim_status+="$(printf "%-8s" "$num_runs")"
            sim_status+="$(printf "%-20s" "$newest_time/$sim_time")"
            sim_status+="$(printf "%-8s" "$(grep "#SBATCH --nodes=" $consecutive_start | awk -F= '{print $2}')")"
            sim_status+="$(printf "%-12s" "$(grep "#SBATCH --ntasks-per-node=" $consecutive_start | awk -F= '{print $2}')")"
            sim_status+="$(printf "%-24s" "$CPU_time")"
            
        else
            # Check if simulation has been submitted before
            if squeue -o "%.18i %.9P %.12j %.8u %.2t %.10M %.6D %R" | grep -q "$sim"; then
                # Add simulation to array of simulations that are queued
                simulations_queued+=("$sim")
                
                # Update status with state "queued"
                sim_status+="$(printf "%-16s" "queued")"
            
            else
                # Add simulation to array of simulations for initial run
                simulations_initial+=("$sim")

                # Update status with state "initial"
                sim_status+="$(printf "%-16s" "initial")"
            fi
            

            # Read the simulation time from initial_cfg
            sim_time=$(grep "/solve/dual-time-iterate" $initial_cfg | awk '{print $2}')

            # Update status with run 0, simulation time and node values, and no runtime
            sim_status+="$(printf "%-8s" "0")"
            sim_status+="$(printf "%-20s" "0.000000/$sim_time")"
            sim_status+="$(printf "%-8s" "$(grep "#SBATCH --nodes=" $initial_start | awk -F= '{print $2}')")"
            sim_status+="$(printf "%-12s" "$(grep "#SBATCH --ntasks-per-node=" $initial_start | awk -F= '{print $2}')")"
            sim_status+="$(printf "%-24s" "00-00:00:00")"
        fi

        # Write simulation status
        cd ..
        echo "$sim_status" >> "simulation_status.txt"
        cd "$sim"
     
    else
        # Add other folders 
        other+=("$sim")
    fi

    cd ..
done

# Append timestamp to simulation_status.txt
echo " " >> "simulation_status.txt"
echo "Updated: $(date)" >> "simulation_status.txt"

# Print simulations currently running
if [ ${#simulations_running[@]} -gt 0 ]; then
    echo "${#simulations_running[@]} simulation(s) currently running:"
    echo "${simulations_running[@]}"
    echo ""
fi

# Print simulations that have ended
if [ ${#simulations_ended[@]} -gt 0 ]; then
    echo "${#simulations_ended[@]} simulation(s) that have ended:"
    echo "${simulations_ended[@]}"
    echo ""
fi

# Print simulations that are queued
if [ ${#simulations_queued[@]} -gt 0 ]; then
    echo "${#simulations_queued[@]} simulation(s) that are queued:"
    echo "${simulations_queued[@]}"
    echo ""
fi

# Print other folders
if [ ${#other[@]} -gt 0 ]; then
    echo "${#other[@]} other folder(s) found:"
    echo "${other[@]}"
    echo ""
fi

# Print simulations to be run initially
if [ ${#simulations_initial[@]} -gt 0 ]; then
    echo "${#simulations_initial[@]} simulation(s) for initial run:"
    echo "${simulations_initial[@]}"
    echo ""
fi

# Print simulations to be run consecutively
if [ ${#simulations_consecutive[@]} -gt 0 ]; then
    echo "${#simulations_consecutive[@]} simulation(s) for consecutive run:" 
    echo "${simulations_consecutive[@]}"
    echo ""
fi

# Starting initial simulations based on user input
if [ ${#simulations_initial[@]} -gt 0 ]; then
    while true; do
        read -p "Start all initial simulations? (y/n) " response
        case $response in
            [yY])
                echo "Starting all ${#simulations_initial[@]} initial simulations:"
                      
                for sim in "${simulations_initial[@]}"; do
                    cd "$sim"

                    # Starting initial simulation with sbatch
                    sbatch $initial_start
                
                    cd ..
                done
                break
            ;;
            [nN])
                echo "Skipping starting initial simulations."
                break
            ;;
            *)
                echo "Invalid response. Please enter 'y' or 'n'."
            ;;
        esac
    done
fi

# Starting consecutive simulations
if [ ${#simulations_consecutive[@]} -gt 0 ]; then
    while true; do
        read -p "Start all consecutive simulations? (y/n) " response
        case $response in
            [yY])
                echo "Starting all ${#simulations_consecutive[@]} consecutive simulations:"
            
                for sim in "${simulations_consecutive[@]}"; do
                    cd "$sim"
                    cd "simulation"
                    newest_data=$(ls -t *.dat.h5 | head -1)             # Getting name of newest data file
                    cd ..
                
                    # Update the consecutive_cfg to include the most recent file
                    sed -i "3s@/file/rd simulation/.*\.dat\.h5@/file/rd simulation/$newest_data@" $consecutive_cfg

                    cd ..
                    line=$(grep "^$sim " "simulation_status.txt")       # Finds current simulation in simulation_status.txt
                    run=$(echo $line | awk '{print $3}')                # Finds last run in simulation_status.txt
                    run=$((run+1))                                      # Set next run
                    cd "$sim"

                    # Update the consecutive_start to write a new log file
                    # sed -i "/^time/c\time fluent 3ddp -mpi=openmpi -g -t40 -cnf=fluent.hosts -i $consecutive_cfg > log$run.txt" $consecutive_start       # previous solution 
                    execline=$(grep "^time" "$consecutive_start")       # find fluent configuration line
                    IFS=' ' read -r -a parts <<< "$execline"            # read parts of line separated by a space
                    parts[8]=$consecutive_cfg                           # replace config file
                    parts[10]="log$run.txt"                             # replace log file
                    newline="${parts[*]}"                               # construct new line with replaced parts
                    sed -i "s|^time.*|$newline|" "$consecutive_start"   # copy new line to file

                    # Starting initial simulation with sbatch
                    sbatch $consecutive_start
                                    
                    cd ..
                done
                break
            ;;
            [nN])
                echo "Skipping starting consecutive simulations."
                break
            ;;
            *)
                echo "Invalid response. Please enter 'y' or 'n'."
            ;;
        esac
    done
fi