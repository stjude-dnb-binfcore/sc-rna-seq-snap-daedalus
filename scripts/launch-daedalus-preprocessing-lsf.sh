#!/usr/bin/env bash
# Submit optional FastQC and Cell Ranger LSF jobs (static module scripts only).
# Resource requests come from analyses/fastqc-analysis/lsf-script.txt and
# analyses/cellranger-analysis/submit-multiple-jobs.sh — not from the downstream estimator.
#
# Usage (from launch-daedalus-sprocket.sh):
#   bash scripts/launch-daedalus-preprocessing-lsf.sh --dry-run
#   bash scripts/launch-daedalus-preprocessing-lsf.sh --submit
#
# On --submit, prints two lines to stdout for the caller to parse:
#   FASTQC_JOB=<id or empty>
#   CELLRANGER_WAITER_JOB=<id or empty>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEDALUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE=dry-run; shift ;;
    --submit) MODE=submit; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${MODE}" ]]; then
  echo "Specify --dry-run or --submit" >&2
  exit 1
fi

# shellcheck source=daedalus-read-config.sh
source "${SCRIPT_DIR}/daedalus-read-config.sh"
export DAEDALUS_ROOT

RUN_FASTQC="$(daedalus_yaml_workflow_toggle run_fastqc)"
RUN_CELLRANGER="$(daedalus_yaml_workflow_toggle run_cellranger)"
NOTIFY_EMAIL="$(daedalus_yaml_get CONTACT_EMAIL 2>/dev/null || echo "user.name@stjude.org")"

FASTQC_DIR="${DAEDALUS_ROOT}/analyses/fastqc-analysis"
CELLRANGER_DIR="${DAEDALUS_ROOT}/analyses/cellranger-analysis"

extract_job_id() { awk '{print $2}' | sed 's/[<>]//g'; }

submit_job() {
  local _cwd="$1"
  local _in="$2"
  local _dep="${3:-}"
  local _label="${4:-job}"

  mkdir -p "${_cwd}"
  local out
  if ! out=$(bsub -cwd "${_cwd}" \
                  ${_dep:+-w "${_dep}"} \
                  -N -u "${NOTIFY_EMAIL}" \
                  < "${_in}" 2>&1); then
    echo "ERROR: bsub failed for ${_label} in ${_cwd}" >&2
    echo "${out}" >&2
    exit 1
  fi
  local jid
  jid="$(echo "${out}" | extract_job_id)"
  if [[ -z "${jid}" ]]; then
    echo "ERROR: Could not parse job ID for ${_label}. bsub output:" >&2
    echo "${out}" >&2
    exit 1
  fi
  echo "${jid}"
}

# Run submit-multiple-jobs.sh locally (DAEDALUS_LSF_LAUNCHER_MODE=1); return waiter job ID.
submit_job_cellranger() {
  local workdir="$1"
  local launcher="$2"
  local upstream_dep="$3"
  local jobname="$4"

  (
    set -euo pipefail
    cd "${workdir}"
    local raw
    raw="$(DAEDALUS_LSF_LAUNCHER_MODE=1 bash "${launcher}" "${upstream_dep}" "${jobname}" 2>&1)"
    local waiter_id
    waiter_id="$(echo "${raw}" | grep -Eo 'Job <[0-9]+>' | grep -Eo '[0-9]+' | tail -n 1)"
    if [[ -z "${waiter_id}" || ! "${waiter_id}" =~ ^[0-9]+$ ]]; then
      echo "ERROR: ${launcher} did not emit a numeric waiter job ID." >&2
      echo "${raw}" >&2
      exit 1
    fi
    echo "${waiter_id}"
  )
}

JOB_FASTQC=""
JOB_CELLRANGER=""

if [[ "${RUN_FASTQC}" == "TRUE" ]]; then
  if [[ "${MODE}" == "dry-run" ]]; then
    echo "==> Would submit FastQC: ${FASTQC_DIR}/lsf-script.txt"
  else
    echo "==> Submitting FastQC (static lsf-script.txt)..."
    JOB_FASTQC="$(submit_job "${FASTQC_DIR}" "${FASTQC_DIR}/lsf-script.txt" "" "FastQC")"
    echo "  FastQC job: ${JOB_FASTQC}"
  fi
else
  echo "==> FastQC: disabled (workflow_profile.run_fastqc)"
fi

if [[ "${RUN_CELLRANGER}" == "TRUE" ]]; then
  if [[ ! -x "${CELLRANGER_DIR}/submit-multiple-jobs.sh" && ! -f "${CELLRANGER_DIR}/submit-multiple-jobs.sh" ]]; then
    echo "Missing Cell Ranger launcher: ${CELLRANGER_DIR}/submit-multiple-jobs.sh" >&2
    exit 1
  fi
  if [[ "${MODE}" == "dry-run" ]]; then
    echo "==> Would submit Cell Ranger: ${CELLRANGER_DIR}/submit-multiple-jobs.sh (parallel with FastQC; waiter gates downstream)"
  else
    echo "==> Submitting Cell Ranger (submit-multiple-jobs.sh; parallel with FastQC)..."
    JOB_CELLRANGER="$(submit_job_cellranger "${CELLRANGER_DIR}" "${CELLRANGER_DIR}/submit-multiple-jobs.sh" "" "CellRanger")"
    echo "  Cell Ranger waiter job: ${JOB_CELLRANGER}"
    if command -v mail >/dev/null 2>&1; then
      echo "  Cell Ranger waiter = ${JOB_CELLRANGER}" | mail -s "Cell Ranger submitted (daedalus)" "${NOTIFY_EMAIL}" || true
    fi
  fi
else
  echo "==> Cell Ranger: disabled (workflow_profile.run_cellranger)"
fi

printf 'FASTQC_JOB=%s\n' "${JOB_FASTQC}"
printf 'CELLRANGER_WAITER_JOB=%s\n' "${JOB_CELLRANGER}"
