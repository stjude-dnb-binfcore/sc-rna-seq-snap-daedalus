#!/usr/bin/env bash
set -euo pipefail

# Root launcher for daedalus: optional FastQC / Cell Ranger (static LSF) plus
# downstream workflow (upstream-analysis onwards) via WDL + Sprocket.
#
# Prerequisites:
#   - Cell Ranger outputs under analyses/cellranger-analysis/ (or set
#     workflow_profile.run_cellranger: true to align on submit)
#   - module load sprocket R singularity   (on St. Jude HPC)
#   - Apptainer/Singularity image at rstudio_4.4.0_seurat_4.4.0_latest.sif
#
# Usage (from this directory):
#   bash launch-daedalus-downstream.sh              # dry-run: validate static WDL + refresh YAML/inputs
#   bash launch-daedalus-downstream.sh --submit     # submit preprocessing (if enabled) then Sprocket
#
# What happens automatically:
#   0. If workflow_profile.run_fastqc / run_cellranger: submit static LSF jobs
#      (parallel); on --submit, wait for Cell Ranger's waiter job before downstream
#   1. Counts samples from project_metadata.tsv (or Cell Ranger output dirs)
#   2. Reads Cell Ranger metrics_summary.csv for cells/sample
#   3. Scales LSF CPU and memory per downstream module (baseline: 8 samples x 50k cells)
#   4. Writes <root_dir>/inputs/project_parameters.generated.yaml (master Config.yaml unchanged)
#   5. Writes inputs/generated_downstream.json for Sprocket
#   6. After a successful submit, writes out/resource_usage/resource_usage_<run_id>.{csv,json}
#
# Edit project_parameters.Config.yaml for biology parameters and workflow_profile toggles.

DAEDALUS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMIT=0
EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --submit) SUBMIT=1; shift ;;
    --dry-run) EXTRA+=(--dry-run); shift ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

if [[ "${SUBMIT}" -eq 0 && " ${EXTRA[*]:-} " != *" --dry-run "* ]]; then
  EXTRA+=(--dry-run)
fi

exec bash "${DAEDALUS_ROOT}/scripts/launch-daedalus-sprocket.sh" \
  --daedalus-root "${DAEDALUS_ROOT}" \
  --update-yaml \
  "${EXTRA[@]}"
