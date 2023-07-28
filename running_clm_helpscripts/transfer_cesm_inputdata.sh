#!/bin/bash -l
#SBATCH --job-name="transfer"
#SBATCH --account="s1207"
#SBATCH --time=06:00:00
#SBATCH --partition=xfer
#SBATCH --hint=nomultithread
#SBATCH --nodes=1
#SBATCH --job-name="store"
#SBATCH --output=transfer_cesm_inputdata.out
#SBATCH --error=transfer_cesm_inputdata.err

ORIGIN=$SCRATCH/CCLM2_inputdata/
TARGET=/project/s1207/CCLM2_inputdata/


# sync local downloaded input to project
print *** Transferring ${ORIGIN} to ${TARGET}

rsync -avr --progress ${ORIGIN} ${TARGET}



# transfer project input data to scratch

print *** Transferring ${TARGET} to ${ORIGIN}
rsync -avr --progress ${TARGET} ${ORIGIN}


