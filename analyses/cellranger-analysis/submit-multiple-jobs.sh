#!/bin/bash

#BSUB -P run_cellranger
#BSUB -J submit-multiple-jobs
#BSUB -q standard
#BSUB -n 1
#BSUB -R "rusage[mem=2500]"
#BSUB -o submit-multiple-jobs.out
#BSUB -e submit-multiple-jobs.err
#BSUB -cwd "."

########################################################################
# Submit Cell Ranger count (j1) and summary waiter chain on LSF.
#
# Three ways to run (same underlying submissions; pick one):
#
#   1) Standalone / interactive (original — no Sprocket or daedalus launcher)
#        cd analyses/cellranger-analysis
#        bsub < submit-multiple-jobs.sh
#      LSF runs this script on a compute node (#BSUB lines above apply).
#
#   2) Pipeline launcher from a login node (daedalus or launch_full_pipeline)
#        DAEDALUS_LSF_LAUNCHER_MODE=1 bash submit-multiple-jobs.sh [upstream_dep] [jobname]
#      Submits j1 + waiter from the login node; prints Job <id> lines for bwait/deps.
#
#   3) Legacy pipeline call (login node, no env var)
#        bash submit-multiple-jobs.sh [upstream_dep] [jobname]
#      Same as (2) without requiring the env var (used by launch_full_pipeline.sh).
########################################################################

daedalus_submit_cellranger_jobs() {
  local upstream_dep="${1:-}"

  rootdir=$(realpath "./../..")
  echo "$rootdir"

  prefix="${rootdir}/analyses/cellranger-analysis"
  mkdir -p "${prefix}/results"

  output_file="output.txt"

  print_job() {
    local outfile=${1}
    local delay_seconds=${2}
    echo "#!/bin/bash"
    echo "time=\`date\`"
    echo "name=\${LSB_JOBNAME}"
    echo "echo \"Online: name=\${name} time=\${time}\" >> ${outfile}"
    echo "sleep ${delay_seconds}"
    echo "echo \"Done: name=\${name}\" >> ${outfile}"
  }

  for ((i=1; i<=2; i++)); do
    jobname="j${i}"
    print_job "${prefix}/${output_file}" 10 > "${prefix}/${jobname}.bsub"
    echo "bash ${prefix}/${jobname}.sh" >> "${prefix}/${jobname}.bsub"
  done

  local j1_dep=()
  if [[ -n "${upstream_dep}" ]]; then
    j1_dep=(-w "${upstream_dep}")
  fi

  bsub -P run_CellRanger -q standard -n 1 -R "rusage[mem=2GB]" -R "span[hosts=1]" \
    -J j1 -o "${prefix}/j1.out" -e "${prefix}/j1.err" \
    "${j1_dep[@]}" "bash ${prefix}/j1.bsub"

  sleep 60
  bsub < "${prefix}/waiter.sh"
}

run_from_module_dir() {
  # bsub < submit-multiple-jobs.sh: LSF executes a *copy* in the job spool, so
  # BASH_SOURCE[0] is not the repo path. Use the submission cwd (-cwd ".").
  if [[ -n "${LSB_JOBID:-}" ]]; then
    cd "${LSB_JOBCWD:-${PWD}}"
  else
    cd "$(dirname "${BASH_SOURCE[0]}")"
  fi
  daedalus_submit_cellranger_jobs "${1:-}"
}

# --- Mode 2: explicit pipeline launcher (login node) ---
if [[ "${DAEDALUS_LSF_LAUNCHER_MODE:-}" == "1" ]]; then
  set -euo pipefail
  run_from_module_dir "${1:-}"
  exit 0
fi

# --- Mode 1: submitted via "bsub < submit-multiple-jobs.sh" (compute node) ---
if [[ -n "${LSB_JOBID:-}" ]]; then
  set -e
  run_from_module_dir ""
  exit 0
fi

# --- Mode 3: bash submit-multiple-jobs.sh on login node (legacy / launch_full_pipeline) ---
set -e
run_from_module_dir "${1:-}"
