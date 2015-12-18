# BASH-based SLURM pipeline

This pipeline does something very silly and runs the `hostname`
program multiple times with each subsequent `hostname.sh` depending
on the previous one.

To "run" the pipeline:

1. type `bash master.sh`
2. See each job get submitted based on dependencies on the previous job

