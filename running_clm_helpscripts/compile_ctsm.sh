#! /bin/bash

# Script to compile CLM with case-specific settings
# For standalone CLM5.0 or CTSM development version
# Domain can be global or regional (set DOMAIN=eur, requires domain and mapping files)

# based on compile script from Petra Sieber (https://github.com/pesieber/CTSM/blob/release-clm5.0/compile_cclm2.sh)
# adjusted by Inne Vanderkelen

set -e # failing commands will cause the shell script to exit


#==========================================
# Case settings
#==========================================

echo "*** Setting up case ***"

date=`date +'%Y%m%d-%H%M'` # get current date and time
startdate=`date +'%Y-%m-%d %H:%M:%S'`

COMPSET=I2000Clm51Sp # I2000Clm50SpGs for release-clm5.0 
RES=hcru_hcru_mt13 #f09_g17 for test glob
DOMAIN=glob # eur for CCLM2 (EURO-CORDEX), sa for South-America, glob for global 

CODE=CTSMdev # clm5.0 for official release, CTSMdev for latest master branch (requires ESMF installation)

COMPILER=gnu # gnu for gnu/gcc
COMPILERNAME=gcc # gcc for gnu/gcc

EXP=test_${date} # custom case name
CASENAME=$CODE.$COMPILER.$COMPSET.$RES.$DOMAIN.$EXP

DRIVER=nuopc # mct for clm5.0, mct or nuopc for CTSMdev, using nuopc requires ESMF installation (at least 8.4.1)
MACH=pizdaint
QUEUE=normal # USER_REQUESTED_QUEUE, overrides default JOB_QUEUE
WALLTIME="03:00:00" # USER_REQUESTED_WALLTIME, overrides default JOB_WALLCLOCK_TIME
PROJ=$(basename "$(dirname "${PROJECT}")") # extract project name (sm61/s1207)
NTASKS=2 # will be nr of NODES (was 24)
let "NCORES = $NTASKS * 12" # this will be nr of CPUS

NSUBMIT=0 # partition into smaller chunks, excludes the first submission
STARTDATE="2004-01-01"
NYEARS=1

# Set directories
export CLMROOT=$PWD # CLM code base directory  where this script is located
export CASEDIR=$SCRATCH/cases/$CASENAME # case directory on scratch
export CESMDATAROOT=$SCRATCH/CCLM2_inputdata # inputdata directory on scratch (to reuse, includes downloads and preprocessed EURO-CORDEX files)
#export CESMOUTPUTROOT=$SCRATCH/archive/$CASENAME # output directory on scratch

# Log output (use "tee" to send output to both screen and $outfile)
logfile=$CASEDIR/${CASENAME}_mylogfile.log
print_log() {
    output="$1"
    echo -e "${output}" | tee -a $logfile
}

print_log "*** Case at: ${CASEDIR} ***"
print_log "*** Case settings: compset ${COMPSET}, resolution ${RES}, domain ${DOMAIN}, compiler ${COMPILER} ***"
print_log "*** Logfile at: ${logfile} ***"

# Sync inputdata on scratch because scratch will be cleaned every month (change inputfiles on $PROJECT!)
print_log "\n*** Syncing inputdata on scratch  ***"
#rsync -av /project/$PROJ/shared/CCLM2_inputdata/ $CESMDATAROOT/ | tee -a $logfile # also check for updates in file content
sbatch --account=$PROJ --export=ALL,PROJ=$PROJ transfer_clm_inputdata.sh # xfer job to prevent overflowing the loginnode


#==========================================
# Load modules and find spack packages
#==========================================

# Find spack_esmf installation  (used in .cime/config_machines.xml and env_build.xml) and path of netcdf files
if [ $DRIVER == nuopc ]; then
    print_log "\n *** Finding spack_esmf ***"
    export ESMF_PATH=$(spack location -i esmf@8.4.1) # e.g. /project/s1207/ivanderk/spack-install/cray-cnl7-haswell/gcc-9.3.0/esmf-8.4.1-esftqomee2sllfsmjevw3f7cet6tbeb4/
    print_log "ESMF at: ${ESMF_PATH}"

    # direct to spack installation of ESMF (also in .cime/config_compilers.xml - but doesn't work yet for Inne)
    #export ESMFMKFILE=${ESMF_PATH}/lib/esmf.mk
    print_log "*** ESMFMKFILE: ${ESMFMKFILE} ***"


    # add the netcdf_c and netcdf_fortran libraries to LD_LIBRARY_PATH so that cesm can find them during execution -- this can be done in cmake_macros or .cime/config_compilers.xml, but this file does not yet include specific settings for the gnu compiler.

    # soft coded defenition -- not working yet, instead use hard coded copy below
    #export NETCDF_LIB_PATH=$(spack location -i netcdf-c@4.9.0%gcc@9.3.0)/lib/:$(spack location -i netcdf-c@4.9.0%gcc@9.3.0)/lib/
    #export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${NETCDF_LIB_PATH}

    # hard codedlibary path to NETCDF libraries on daint

    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(spack location -i netcdf-c@4.9.0)/lib/:$(spack location -i netcdf-fortran@4.6.1)/lib/


    print_log "*** LD_LIBRARY_PATH: ${LD_LIBRARY_PATH} ***"

fi


#==========================================
# Create case
#==========================================

print_log "\n*** Creating CASE: ${CASENAME} ***"

cd $CLMROOT/cime/scripts
./create_newcase --case $CASEDIR --compset $COMPSET --res $RES --mach $MACH --compiler $COMPILER --driver $DRIVER --project $PROJ --run-unsupported | tee -a $logfile


#==========================================
# Configure CLM
# Settings will appear in namelists and have precedence over user_nl_xxx
#==========================================

print_log "\n*** Modifying env_*.xml  ***"
cd $CASEDIR

# Set directory structure
./xmlchange RUNDIR="$CASEDIR/run" # by defaut, RUNDIR is $SCRATCH/$CASENAME/run
./xmlchange EXEROOT="$CASEDIR/bld"

# Change job settings (env_batch.xml or env_workflow.xml). Do this here to change for both case.run and case.st_archive
./xmlchange JOB_QUEUE=$QUEUE --force
./xmlchange JOB_WALLCLOCK_TIME=$WALLTIME
./xmlchange PROJECT=$PROJ

# Set run start/stop options and DATM forcing (env_run.xml)
./xmlchange RUN_TYPE=startup
./xmlchange RESUBMIT=$NSUBMIT
./xmlchange RUN_STARTDATE=$STARTDATE
./xmlchange STOP_OPTION=nyears,STOP_N=$NYEARS
./xmlchange NCPL_BASE_PERIOD="day",ATM_NCPL=48 # coupling freq default 30min = day,48

if [ $CODE == CTSMdev ] && [ $DRIVER == nuopc ]; then
    ./xmlchange DATM_YR_START=2004,DATM_YR_END=2004,DATM_YR_ALIGN=2004 # new variable names in CTSMdev with nuopc driver
else
    ./xmlchange DATM_CLMNCEP_YR_START=2004,DATM_CLMNCEP_YR_END=2004,DATM_CLMNCEP_YR_ALIGN=2004 # in clm5.0 and CLM_features, with any driver
fi

# Set the number of cores and nodes (env_mach_pes.xml)
./xmlchange COST_PES=$NCORES
./xmlchange NTASKS_CPL=-$NTASKS
./xmlchange NTASKS_ATM=-$NTASKS
./xmlchange NTASKS_OCN=-$NTASKS
./xmlchange NTASKS_WAV=-$NTASKS
./xmlchange NTASKS_GLC=-$NTASKS
./xmlchange NTASKS_ICE=-$NTASKS
./xmlchange NTASKS_ROF=-$NTASKS
./xmlchange NTASKS_LND=-$NTASKS


# Domain and mapping files for limited spatial extent
if [ $DOMAIN == eur ]; then
    ./xmlchange LND_DOMAIN_PATH="$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/domain"
    ./xmlchange LND_DOMAIN_FILE="domain_EU-CORDEX_0.5_lon360.nc"
fi

if [ $DOMAIN == sa ]; then
    ./xmlchange LND_DOMAIN_PATH="$CESMDATAROOT/cesm_inputdata/CCLM2_SA_inputdata/domain"
    ./xmlchange LND_DOMAIN_FILE="domain.lnd.360x720_SA-CORDEX_cruncep.100429.nc"
fi

if [ $DOMAIN == eur ] || [ $DOMAIN == sa ]; then
    ./xmlchange LND2ROF_FMAPNAME="$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/mapping/map_360x720_nomask_to_0.5x0.5_nomask_aave_da_c130103.nc"
    ./xmlchange ROF2LND_FMAPNAME="$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/mapping/map_0.5x0.5_nomask_to_360x720_nomask_aave_da_c120830.nc"
    ./xmlchange LND2GLC_FMAPNAME="$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/mapping/map_360x720_TO_gland4km_aave.170429.nc"
    ./xmlchange LND2GLC_SMAPNAME="$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/mapping/map_360x720_TO_gland4km_aave.170429.nc"
    ./xmlchange GLC2LND_FMAPNAME="$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/mapping/map_gland4km_TO_360x720_aave.170429.nc"
    ./xmlchange GLC2LND_SMAPNAME="$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/mapping/map_gland4km_TO_360x720_aave.170429.nc"
    ./xmlchange MOSART_MODE=NULL # turn off MOSART for the moment because it runs globally
fi

# ESMF interface and time manager (env_build.xml)
./xmlchange --file env_build.xml --id COMP_INTERFACE --val $DRIVER # mct is default in clm5.0, nuopc is default in CTSMdev (requires ESMF installation); adding --driver mct to create_newcase adds everything needed

if [ $DRIVER == mct ]; then
    ./xmlchange --file env_build.xml --id USE_ESMF_LIB --val "FALSE" # FALSE is default in clm5.0; since cesm1_2 ESMF is no longer necessary to run with calendar=gregorian
elif [ $DRIVER == nuopc ]; then
    ./xmlchange --file env_build.xml --id USE_ESMF_LIB --val "TRUE" # using the ESMF library specified by env var ESMFMKFILE (config_machines.xml), or ESMF_LIBDIR (not found in env_build.xml)
fi


#==========================================
# Set up the case (creates user_nl_xxx)
#==========================================

print_log "\n*** Running case.setup ***"
./case.setup -r | tee -a $logfile


#==========================================
# User namelists (use cat >> to append)
# Surface data: domain-specific
# Paramfile: can be exchanged for newer versions
# Domainfile: has to be provided to DATM
#==========================================
print_log "\n*** Modifying user_nl_*.xml  ***"

if [ $DOMAIN == eur ]; then
cat >> user_nl_clm << EOF
fsurdat = "$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/surfdata/surfdata_0.5x0.5_hist_16pfts_Irrig_CMIP6_simyr2000_c190418.nc"
paramfile = "$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/CLM5params/clm5_params.cpbiomass.c190103.nc"
EOF
cat >> user_nl_datm << EOF
domainfile = "$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/domain/domain_EU-CORDEX_0.5_lon360.nc"
EOF
fi

if [ $DOMAIN == sa ]; then
cat >> user_nl_clm << EOF
fsurdat = "$CESMDATAROOT/cesm_inputdata/CCLM2_SA_inputdata/surfdata/surfdata_360x720cru_SA-CORDEX_16pfts_Irrig_CMIP6_simyr2000_c170824.nc"
paramfile = "$CESMDATAROOT/cesm_inputdata/CCLM2_EUR_inputdata/CLM5params/clm5_params.cpbiomass.c190103.nc"
EOF
cat >> user_nl_datm << EOF
domainfile = "$CESMDATAROOT/cesm_inputdata/CCLM2_SA_inputdata/domain/domain.lnd.360x720_SA-CORDEX_cruncep.100429.nc"
EOF
fi

# For global domain keep the defaults (downloaded from svn trunc)
if [ $DOMAIN == glob ]; then
cat >> user_nl_clm << EOF
fsurdat = "$CESMDATAROOT/cesm_inputdata/CTSM_hcru_inputdata/surfdata_360x720cru_16pfts_Irrig_CMIP6_simyr2000_c170824.nc"
EOF
fi


#==========================================
# Build
#==========================================

print_log "\n*** Building case ***"
./case.build --clean-all | tee -a $logfile


print_log "\n*** Finished building new case in ${CASEDIR} ***"


#==========================================
# Check and download input data
#==========================================

print_log "\n*** Downloading missing inputdata (if needed) ***"
print_log "Consider transferring new data to PROJECT, e.g. rsync -av ${SCRATCH}/CCLM2_inputdata /project/${PROJ}/shared/CCLM2_inputdata"
./check_input_data --download


#==========================================
# Preview and submit job
#==========================================

print_log "\n*** Preview the run ***"
./preview_run | tee -a $logfile

print_log "\n*** Submitting job ***"
./case.submit -a "-C gpu" | tee -a $logfile

squeue --user=$USER | tee -a $logfile
#less CaseStatus

enddate=`date +'%Y-%m-%d %H:%M:%S'`
duration=$SECONDS
print_log "Started at: $startdate"
print_log "Finished at: $enddate"
print_log "Duration to create, setup, build, submit: $(($duration / 60)) min $(($duration % 60)) sec"

print_log "\n*** Check the job: squeue --user=${USER} ***"
print_log "*** Check the case: in ${CASEDIR}, run less CaseStatus ***"


#==========================================
# Copy final CaseStatus to logs
#==========================================

# Notes:
#env_case = model version, components, resolution, machine, compiler [do not modify]
#env_mach_pes = NTASKS, number of MPI tasks (or nodes if neg. values) [modify before setup]
#env_mach_specific = controls machine specific environment [modify before setup]
#env_build = component settings [modify before build]
#env_batch = batch job settings [modify any time]
#env_run = run settings incl runtype, coupling, pyhsics/sp/bgc and output [modify any time]
#env_workflow = wallt
