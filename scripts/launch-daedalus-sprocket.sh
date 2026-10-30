#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/local/bin:${PATH:-}"

# Launch the static daedalus_from_cellranger workflow (upstream onwards) via Sprocket.
#
# Usage:
#   bash scripts/launch-daedalus-sprocket.sh [--daedalus-root PATH] [--no-update-yaml] [--yaml-in-place] [--dry-run] [--no-resource-report]
#
# Sprocket call caching is always disabled so each launch runs the selected modules.
#
# --update-yaml (default): writes inputs/project_parameters.generated.yaml;
#   resolves root_dir/data_dir/metadata_dir from the master config and reads Cell Ranger metrics;
#   project_parameters.Config.yaml (your master template) is not modified.
# --yaml-in-place: overwrite master YAML (creates project_parameters.Config.yaml.orig first).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEDALUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UPDATE_YAML=1
YAML_IN_PLACE=0
DRY_RUN=0
COLLECT_RESOURCES=1
INPUTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --daedalus-root) DAEDALUS_ROOT="$2"; shift 2 ;;
    --inputs) INPUTS="$2"; shift 2 ;;
    --update-yaml) UPDATE_YAML=1; shift ;;
    --no-update-yaml) UPDATE_YAML=0; shift ;;
    --yaml-in-place) YAML_IN_PLACE=1; UPDATE_YAML=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-resource-report) COLLECT_RESOURCES=0; shift ;;
    -h|--help)
      echo "Usage: bash scripts/launch-daedalus-sprocket.sh [--daedalus-root PATH] [--no-update-yaml] [--yaml-in-place] [--dry-run] [--no-resource-report]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

WORKFLOW_NAME="daedalus_from_cellranger"
WORKFLOW="${DAEDALUS_ROOT}/workflows/${WORKFLOW_NAME}.wdl"
CONFIG="${DAEDALUS_ROOT}/sprocket.toml"
GENERATED_CONFIG="${DAEDALUS_ROOT}/inputs/sprocket.generated.toml"
GENERATED="${DAEDALUS_ROOT}/inputs/generated_downstream.json"
SPROCKET_INPUTS="${DAEDALUS_ROOT}/inputs/sprocket_inputs.json"
NOTIFY_SCRIPT="${SCRIPT_DIR}/daedalus-notify-email.sh"

mkdir -p "${DAEDALUS_ROOT}/inputs"

if [[ ! -f "${WORKFLOW}" ]]; then
  echo "Missing static WDL: ${WORKFLOW}" >&2
  exit 1
fi

if ! command -v sprocket >/dev/null 2>&1; then
  echo "sprocket not found. On St. Jude HPC: module load sprocket"
  exit 1
fi

if ! command -v apptainer >/dev/null 2>&1 && ! command -v singularity >/dev/null 2>&1; then
  echo "apptainer/singularity not found. On St. Jude HPC: module load singularity"
  exit 1
fi

UPDATE_FLAG=()
[[ "${UPDATE_YAML}" -eq 1 ]] && UPDATE_FLAG=(--update-yaml)
[[ "${YAML_IN_PLACE}" -eq 1 ]] && UPDATE_FLAG+=(--yaml-in-place)

PREPROCESS_SCRIPT="${SCRIPT_DIR}/launch-daedalus-preprocessing-lsf.sh"
# shellcheck source=daedalus-read-config.sh
source "${SCRIPT_DIR}/daedalus-read-config.sh"
export DAEDALUS_ROOT

RUN_FASTQC="$(daedalus_yaml_workflow_toggle run_fastqc)"
RUN_CELLRANGER="$(daedalus_yaml_workflow_toggle run_cellranger)"
DOWNSTREAM_ENABLED=0
if daedalus_any_downstream_module_enabled; then
  DOWNSTREAM_ENABLED=1
fi

NOTIFY_EMAIL="$(daedalus_yaml_get CONTACT_EMAIL 2>/dev/null || true)"
if [[ -z "${NOTIFY_EMAIL}" ]]; then
  NOTIFY_EMAIL="user.name@stjude.org"
  echo "WARN: CONTACT_EMAIL not set in project_parameters.Config.yaml; notifications go to ${NOTIFY_EMAIL}" >&2
fi

send_workflow_email() {
  local subject="$1"
  local body="$2"
  bash "${NOTIFY_SCRIPT}" --to "${NOTIFY_EMAIL}" --subject "${subject}" --body "${body}" || true
}

echo "==> Using static WDL: ${WORKFLOW}"

if [[ "${DRY_RUN}" -eq 0 ]]; then
  send_workflow_email "[daedalus] pipeline: submit started" \
    "Daedalus launch started at $(date -Is)
Project: ${DAEDALUS_ROOT}
Preprocessing: run_fastqc=${RUN_FASTQC} run_cellranger=${RUN_CELLRANGER}
Downstream (Sprocket): enabled=$([[ "${DOWNSTREAM_ENABLED}" -eq 1 ]] && echo true || echo false)"
fi

if [[ "${RUN_FASTQC}" == "TRUE" || "${RUN_CELLRANGER}" == "TRUE" ]]; then
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    bash "${PREPROCESS_SCRIPT}" --dry-run
  else
    if ! command -v bsub >/dev/null 2>&1; then
      echo "bsub not found; required when workflow_profile.run_fastqc or run_cellranger is true" >&2
      exit 1
    fi
    echo "==> Preprocessing (FastQC / Cell Ranger via static LSF scripts)"
    PREPROCESS_OUT="$(bash "${PREPROCESS_SCRIPT}" --submit)"
    echo "${PREPROCESS_OUT}"
    CELLRANGER_WAITER_JOB="$(echo "${PREPROCESS_OUT}" | sed -n 's/^CELLRANGER_WAITER_JOB=//p' | tail -n 1)"
    if [[ "${RUN_CELLRANGER}" == "TRUE" && -n "${CELLRANGER_WAITER_JOB}" ]]; then
      echo "==> Waiting for Cell Ranger LSF chain (waiter job ${CELLRANGER_WAITER_JOB})"
      if ! bwait -w "done(${CELLRANGER_WAITER_JOB})"; then
        echo "Cell Ranger waiter job ${CELLRANGER_WAITER_JOB} did not complete successfully" >&2
        exit 1
      fi
      echo "==> Cell Ranger complete"
      send_workflow_email "[daedalus] Cell Ranger: complete" \
        "Cell Ranger LSF chain finished at $(date -Is). Planning downstream resources and Sprocket submit next.
Project: ${DAEDALUS_ROOT}"
      DATA_DIR="$(daedalus_yaml_get data_dir 2>/dev/null || true)"
      if [[ -z "${DATA_DIR}" ]] || ! compgen -G "${DATA_DIR}/*/outs/metrics_summary.csv" >/dev/null 2>&1; then
        echo "Cell Ranger waiter finished but no metrics_summary.csv under data_dir:" >&2
        echo "  ${DATA_DIR:-<unset>}" >&2
        echo "Check analyses/cellranger-analysis/j1.err and j2.err" >&2
        exit 1
      fi
    fi
  fi
fi

if [[ "${DOWNSTREAM_ENABLED}" -eq 0 ]]; then
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "Dry run complete (no downstream modules enabled in workflow_profile)."
  else
    echo "Preprocessing submitted; no downstream modules enabled in workflow_profile."
    send_workflow_email "[daedalus] pipeline: preprocessing only" \
      "Preprocessing jobs submitted at $(date -Is). No downstream Sprocket modules enabled in workflow_profile.
Project: ${DAEDALUS_ROOT}"
  fi
  exit 0
fi

echo "==> Estimating downstream resources"
ESTIMATE_EXTRA=()
if [[ "${DRY_RUN}" -eq 1 && "${RUN_CELLRANGER}" == "TRUE" ]]; then
  ESTIMATE_EXTRA=(--allow-pending-cellranger)
fi
Rscript "${SCRIPT_DIR}/estimate-daedalus-downstream-resources.R" \
  --daedalus-root "${DAEDALUS_ROOT}" \
  --output "${GENERATED}" \
  "${UPDATE_FLAG[@]}" \
  "${ESTIMATE_EXTRA[@]}"

[[ -z "${INPUTS}" ]] && INPUTS="${SPROCKET_INPUTS}"

if [[ ! -f "${INPUTS}" ]]; then
  echo "Missing Sprocket inputs: ${INPUTS}" >&2
  echo "Re-run resource estimation or pass --inputs PATH" >&2
  exit 1
fi

echo "==> Rendering Sprocket config"
bash "${SCRIPT_DIR}/render-sprocket-config.sh" "${DAEDALUS_ROOT}" "${INPUTS}"
CONFIG="${GENERATED_CONFIG}"
MONITOR_SCRIPT="${SCRIPT_DIR}/monitor-daedalus-task-emails.sh"
RESOURCE_SCRIPT="${SCRIPT_DIR}/collect-resource-usage.sh"

if [[ -z "${NOTIFY_EMAIL}" ]]; then
  NOTIFY_EMAIL="$(
    grep -o '"daedalus_from_cellranger.notify_email"[[:space:]]*:[[:space:]]*"[^"]*"' "${INPUTS}" \
      | sed -n '1s/.*"\([^"]*\)"$/\1/p'
  )"
fi

echo "==> Checking WDL"
sprocket check "${WORKFLOW}"

SKIP_VALIDATE=0
if [[ "${DRY_RUN}" -eq 1 && "${RUN_CELLRANGER}" == "TRUE" && -f "${GENERATED}" ]]; then
  if grep -q '"pending_cellranger"[[:space:]]*:[[:space:]]*true' "${GENERATED}" 2>/dev/null; then
    SKIP_VALIDATE=1
    echo "==> Skipping sprocket validate (Cell Ranger outputs not on disk yet; planned via run_cellranger)"
    echo "    Run bash launch-daedalus-downstream.sh --submit to align, wait, then validate and run downstream."
  fi
fi

if [[ "${SKIP_VALIDATE}" -eq 0 ]]; then
  echo "==> Validating inputs (${INPUTS})"
  sprocket validate "${WORKFLOW}" @"${INPUTS}" --config "${CONFIG}"
fi

[[ "${DRY_RUN}" -eq 1 ]] && { echo "Dry run complete."; exit 0; }

echo "==> Submitting downstream workflow"
send_workflow_email "[daedalus] Daedalus downstream: submitted" \
  "Daedalus downstream workflow submitted at $(date -Is)
Project: ${DAEDALUS_ROOT}
Config: ${CONFIG}
Per-module start/complete emails follow via monitor-daedalus-task-emails.sh."

set +e
# Shared directories are passed as String paths, so call caching cannot detect changes to their contents.
SPROCKET_RUN_FLAGS=(run "${WORKFLOW}" @"${INPUTS}" --config "${CONFIG}" --output-dir "${DAEDALUS_ROOT}/out" --no-call-cache)
sprocket "${SPROCKET_RUN_FLAGS[@]}" &
SPROCKET_PID=$!

bash "${MONITOR_SCRIPT}" \
  --daedalus-root "${DAEDALUS_ROOT}" \
  --to "${NOTIFY_EMAIL}" \
  --watch-pid "${SPROCKET_PID}" &
MONITOR_PID=$!

wait "${SPROCKET_PID}"
RUN_EXIT=$?

wait "${MONITOR_PID}" 2>/dev/null || true
bash "${MONITOR_SCRIPT}" \
  --daedalus-root "${DAEDALUS_ROOT}" \
  --to "${NOTIFY_EMAIL}" \
  --finalize-only || true
set -e

if [[ "${COLLECT_RESOURCES}" -eq 1 ]]; then
  echo "==> Collecting per-module resource usage (requested vs actual)"
  bash "${RESOURCE_SCRIPT}" --daedalus-root "${DAEDALUS_ROOT}" --latest --json || true
fi

VALIDATION_EXIT=0
if [[ "${RUN_EXIT}" -eq 0 && "${DOWNSTREAM_ENABLED}" -eq 1 ]]; then
  if [[ "$(daedalus_yaml_workflow_toggle run_biological_validation)" == "TRUE" ]]; then
    echo "==> Biological validation (output consistency checks)"
    VALIDATION_JSON="${DAEDALUS_ROOT}/out/validation/biological_validation.json"
    send_workflow_email "[daedalus] biological validation: started" \
      "Biological output validation started at $(date -Is)
Project: ${DAEDALUS_ROOT}
Report (when finished): ${VALIDATION_JSON}"
    mkdir -p "${DAEDALUS_ROOT}/out/validation"
    set +e
    bash "${SCRIPT_DIR}/daedalus-apptainer-rscript.sh" --daedalus-root "${DAEDALUS_ROOT}" -- \
      "${SCRIPT_DIR}/daedalus_validate_outputs.R" \
      --daedalus-root "${DAEDALUS_ROOT}" \
      --json "${VALIDATION_JSON}"
    VALIDATION_EXIT=$?
    set -e
    if [[ "${VALIDATION_EXIT}" -ne 0 ]]; then
      send_workflow_email "[daedalus] biological validation: failed" \
        "Biological validation reported errors at $(date -Is)
Project: ${DAEDALUS_ROOT}
Report: ${VALIDATION_JSON}"
    else
      send_workflow_email "[daedalus] biological validation: completed" \
        "Biological validation passed at $(date -Is)
Project: ${DAEDALUS_ROOT}
Report: ${VALIDATION_JSON}"
    fi
  fi
fi

if [[ "${RUN_EXIT}" -eq 0 && "${VALIDATION_EXIT:-0}" -eq 0 ]]; then
  send_workflow_email "[daedalus] Daedalus downstream: completed" \
    "Daedalus downstream workflow completed successfully at $(date -Is)
Project: ${DAEDALUS_ROOT}
(Preprocessing modules FastQC/Cell Ranger, if enabled, run separately before this phase.)"
else
  send_workflow_email "[daedalus] Daedalus downstream: failed" \
    "Daedalus downstream workflow failed (Sprocket exit ${RUN_EXIT}) at $(date -Is)
Project: ${DAEDALUS_ROOT}
Check: ${DAEDALUS_ROOT}/out/runs/${WORKFLOW_NAME}/"
fi
if [[ "${RUN_EXIT}" -eq 0 && "${VALIDATION_EXIT:-0}" -ne 0 ]]; then
  exit "${VALIDATION_EXIT}"
fi
exit "${RUN_EXIT}"
