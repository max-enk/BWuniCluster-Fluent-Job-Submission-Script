#!/bin/bash

#SBATCH --partition single
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=40
#SBATCH --time=72:00:00
#SBATCH --mem=85gb
#SBATCH --job-name=S000-1ref
#SBATCH --mail-type=ALL
#SBATCH --mail-user=cl1169@partner.kit.edu

module load cae/ansys/2022R2
source fluentinit
scontrol show hostname ${SLURM_JOB_NODELIST} > fluent.hosts

## start fluent
#3ddp = dreidimensionales Problem, doppelte Genauigkeit
#g = ohne graphische Oberflaeche
#i = Journal file wird eingelesen

time fluent 3ddp -mpi=openmpi -g -t40 -cnf=fluent.hosts -i consecutive-parallel.jou > log2.txt


