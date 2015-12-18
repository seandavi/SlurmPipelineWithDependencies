#! /bin/bash

function usage() {
    cat <<EOF
SYNOPSIS
  chipseq.sh - run chipseq pipeline
DESCRIPTION
  Look for fastq files in './fastq/'. Align them, call
  peaks, merge all peaks, and then count reads
  against the merged peak set for each sample
  Expects a single control sample called control.fastq

  Of course this is just a contrived example showing
  some common patterns of using dependencies to build
  pipelines. The pipeline will run but all processing 
  is fake.

AUTHOR
  Wolfgang Resch

EOF
}

# short id to make sure job names are unique for diffenrent pipeline runs
run=$(uuidgen | tr '-' ' ' | awk '{print $1}')

################################################################################
#                          find samples and controls                           #
################################################################################

fastq_files=( $(ls fastq/*.{fastq,fq}* 2>/dev/null) )
declare -a samples controls
for f in ${fastq_files[@]}; do
    if [[ "$f" =~ .*control.* ]]; then
        controls+=($f)
    else
        samples+=($f)
    fi
done 
if [[ ${#samples[@]} -eq 0 ]]; then
    echo "no samples in fastq/"
    exit 1
fi
if [[ ${#controls[@]} -ne 1 ]]; then
    echo "no control found in fastq/"
fi
control=${controls[0]}

echo "samples:" 
for sample in ${samples[@]}; do
    echo "    $sample"
done
echo "control:"
echo "    $control"


################################################################################
#                               run the pipeline                               #
################################################################################
mkdir -p bam peaks log counts

# STEP1: ALIGNMENT. All alignments will start in parallel since they don't
#        have any dependencies
aln_jobids=()
bam_files=()
for f in ${samples[@]}; do
    n=$(basename ${f%%.*})
    bam_files+=(bam/$n.bam)
    aln_jobids+=($(sbatch --mem=1g --time=5 --job-name=$run.align --out=log/$run.align.$n \
        bin/align.sh $f bam/$n.bam))
done

# align the control separately and record jobid since all peak calls depend
# on the sample alignment and the control alignment
ctrln=$(basename ${control%%.*})
bam_files+=(bam/$ctrln.bam)
ctrlaln_jobid=$(sbatch --mem=1g --time=5 --job-name=$run.align --out=log/$run.align.$ctrln \
    bin/align.sh $control bam/$ctrln.bam)

echo "Alignment jobids: ${aln_jobids[@]} ${ctrlaln_jobid}"

# STEP2: PEAK CALLS. Each peak call will start when the corresponding alignments
#        finish sucessfully. Note, if STEP1 fails, all jobs depending on
#        it will remain in the queue and need to be canceled explicitly.
peak_jobids=()
peak_files=()
for i in $(seq 1 ${#samples[@]}); do
    idx=$((i - 1))
    n=$(basename ${samples[$idx]%%.*})
    sbam=bam/$n.bam
    cbam=bam/$ctrln.bam
    peak_files+=(peaks/$n.xls)
    peak_jobids+=($(sbatch --mem=1g --time=5 --job-name=$run.peaks --out=log/$run.peaks.$n \
        --dependency=afterok:$ctrlaln_jobid:${aln_jobids[$idx]} \
        bin/peaks.sh $sbam $cbam peaks/$n.xls))
done
echo "peak calling jobids: ${peak_jobids[@]}"

# STEP3: MERGING PEAKS. This step needs *ALL* peak calls to finish. To do this,
#        use a singleton dependency and give the summary job the same name as the
#        jobs that need to finish first
merge_jobid=$(sbatch --mem=1g --time=5 --job-name=$run.peaks --out=log/$run.peaks_merge \
    --dependency=singleton \
    bin/merge_peaks.sh peaks/merged ${peak_files[@]})
echo "merge peaks jobid: $merge_jobid"

# STEP4: count reads of all bam files against the peaks after STEP3 finishes
count_jobids=()
for f in ${bam_files[@]}; do
    n=$(basename ${f%%.bam})
    count_jobids+=($(sbatch --mem=1g --time=5 --job-name=$run.count --out=log/$run.count.$n \
        --dependency=afterok:$merge_jobid \
        bin/count.sh $f peaks/merged counts/$n))
done
echo "count reads jobids: ${count_jobids[@]}"
echo "DONE submitting"
