# BWuniCluster Fluent Job Submission Script

## Introduction

This project aims to automate the submission of Ansys Fluent jobs on the BWunicluster 2.0.

As of October 2024, this package is no longer supported by updates and is published to GitHub for public access.


## Script Functionality and Capabilities

1. __Environment setup:__
    To manage Fluent simulations on the cluster, this scipt must be located in the root folder where the individual simulation folders are present. Topology:
    - Root folder or Workspace
        - Simulation folders
        - This script
        - Status file simulation_status.txt created by this scipt.
2. __Simulation folder setup:__
    In order for the script to recognize the folder as a simulation folder, it has to be set up like the reference provided in this repository (S000-1ref). __The maximum allowed simulation name length is 16 characters!__
    - Within the simulation folder, a folder called "simulation" must exist. Fluent has to be configured to save the simulation data to that directory. This can be done in the Calculation Activities > Autosave tab in Fluent, where the location has to be configured like __simulation/S000-1ref__. __The part after the / must match the simulation name! Additionally, set the autosave interval to "every flow time", rounded to 6 digits.__
    - One case file .cas.h5 with the name of the simulation + "-1" (S000-1ref-1.cas.h5 in the reference simulation folder)
    - 2 shell scripts for job submission set up like the ones in the reference folder (one for an initial simulation run and one for all consecutive runs). 
        - For your simulation, change the #sbatch lines to suit your simulation and user info. 
        - The line
            ```
            time fluent 3ddp -mpi=openmpi -g -t40 -cnf=fluent.hosts -i initial-parallel.jou > log1.txt
            ```
            must be configured as well. Set your dimensions (2D/3D -> 2ddp/3ddp) and thread count (-t40) here. The latter must match the product of the number of nodes and the number of tasks as configured in the #sbatch lines. __Do not remove the "> log*.txt" output!__
        - Retaining the names of these files is recommended. If you would like to change these names, edit the respective entries in the init_fluent.sh file as well!
    - 2 Fluent journal files set up like the ones in the reference folder (one for an initial simulation run and one for all consecutive runs). 
        - For your simulation, change the lines where the case and data files are being read according to your simulation name. For consecutive runs, the filename of the most recent data file will set automatically by the script. 
        - Retaining the names of these files is recommended. If you would like to change these names, edit the respective entries in the init_fluent.sh and in the shell scripts file as well!
    - Running simulations will create slurm-*.out in the simulation folder. __Do not delete these files!__
    - Running simulations will create log*.out in the simulation folder. __Do not delete these files!__
3. __Execute the script through CLI in the root folder:__
    ```
    bash init_fluent.sh
    ```
4. __Script Output:__
    - The script will list all folders found in the root folder and classify them based on their properties:
        - other: folder does not meet the requirements to be recognized as a simulation. These requirements are given in step 2.
        - running: simulation is currently running.
        - ended: simulation has reached its specified maximum flow time.
        - initial: simulation can be started for its initial run. Requires additional user input.
        - consecutive: simulation can be started for a consecutive run. Requires additional user input.
        - queued: simulation has been priorly submitted as a cluster job but has not started yet.
    - In case of simulations eligible for initial or consecutive runs, the user will be prompted to separately start all initial and consecutive simulations. If entering "yes", the script will submit all simulations of the respective type (initial/consecutive) as cluster jobs. Starting simulations individually is not possible!
    - Status file simulation_status.txt.
5. __Contents of simulation_status.txt:__
    This file gives an overview over all simulations found in the root folder.
    - Simulation name
    - Simulation status (running/ended/initial/consecutive/queued)
    - Number of current run
    - Simulated time/total time
    - Number of cluster nodes used
        To use more than a single node, change "single" to "multiple" the first #sbatch line in the shell scripts and specify the desired number of nodes in the line below. Increasing node count may lead to significantly longer wait times for jobs in queue.
    - Number of CPU cores per node (max. 40)
    - Total CPU time, meaning the combined total runtime of all jobs based on the slurm-*.out created during simulation runs and the output of the shell command "squeue".


## Remarks, Limitations

- __User environment:__ the use of WinSCP is recommended for data transfer and file management on the cluster.
- __User environment:__ the use of Putty or any other SSH client is recommended to execute the shell script init_fluent.sh. 
- __Cluster environment:__ running the shell command "squeue" will give an overview over all currently submitted and running simulations without creating or changing the file simulation_status.txt
- __File setup:__ taking a look at the script init_fluent.sh may give additional information on the scripts functionality and limitations not described in this README.
- __File setup:__ the requirements for the script to work properly are fairly tight. Ensure that you have set up you root and simulation folders as described in steps 1 and 2.
- __File setup:__ the files *.cas.h5 and *.dat.h5 are just included to provide references for the correct naming of the files. Do not run them and use the Fluent settings as reference.
- __Fluent setup:__ setting the autosave frequency and the frequency of the report file outputs (*.out files) to the same value is recommended (default 0.01 s for total runtime of 1.5 s). Meshes with cell counts higher than ~10 million may require a higher autosave frequency for running efficient simulations. 