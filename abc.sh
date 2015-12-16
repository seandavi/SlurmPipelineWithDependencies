#!/bin/bash

STEP1=`sbatch hostname.sh`
echo "${STEP1} submitted--step1"
STEP2=`sbatch --dependency=afterok:${STEP1} hostname.sh`
echo "${STEP2} submitted--step2"
STEP3=`sbatch --dependency=afterok:${STEP2} hostname.sh`
echo "${STEP3} submitted--step3"
STEP4=`sbatch --dependency=afterok:${STEP3} hostname.sh`
echo "${STEP3} submitted--step4"

echo "${STEP1}, ${STEP2}, ${STEP3} and ${STEP4} submitted"
echo "These jobs will run in order and each step will wait for the previous one to complete"
