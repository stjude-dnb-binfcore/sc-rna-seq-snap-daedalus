#!/usr/bin/env bash
set -euo pipefail

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

echo "==> Using static WDL: ${WORKFLOW}"

echo "==> Estimating downstream resources"
Rscript "${SCRIPT_DIR}/estimate-daedalus-downstream-resources.R" \
  --daedalus-root "${DAEDALUS_ROOT}" \
  --output "${GENERATED}" \
  "${UPDATE_FLAG[@]}"

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

NOTIFY_EMAIL="$(
  grep -o '"daedalus_from_cellranger.notify_email"[[:space:]]*:[[:space:]]*"[^"]*"' "${INPUTS}" \
    | sed -n '1s/.*"\([^"]*\)"$/\1/p'
)"

send_workflow_email() {
  local subject="$1"
  local body="$2"
  bash "${NOTIFY_SCRIPT}" --to "${NOTIFY_EMAIL}" --subject "${subject}" --body "${body}" || true
}

echo "==> Checking WDL"
sprocket check "${WORKFLOW}"

echo "==> Validating inputs (${INPUTS})"
sprocket validate "${WORKFLOW}" @"${INPUTS}" --config "${CONFIG}"

[[ "${DRY_RUN}" -eq 1 ]] && { echo "Dry run complete."; exit 0; }

echo "==> Submitting downstream workflow"
send_workflow_email "[daedalus] workflow: submitted" \
  "Daedalus downstream workflow submitted at $(date -Is)\nProject: ${DAEDALUS_ROOT}\nConfig: ${CONFIG}"

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
set -e

if [[ "${COLLECT_RESOURCES}" -eq 1 ]]; then
  echo "==> Collecting per-module resource usage (requested vs actual)"
  bash "${RESOURCE_SCRIPT}" --daedalus-root "${DAEDALUS_ROOT}" --latest --json || true
fi

if [[ "${RUN_EXIT}" -eq 0 ]]; then
  send_workflow_email "[daedalus] workflow: completed" \
    "Daedalus downstream workflow completed successfully at $(date -Is)\nProject: ${DAEDALUS_ROOT}"
else
  send_workflow_email "[daedalus] workflow: failed" \
    "Daedalus downstream workflow failed (exit ${RUN_EXIT}) at $(date -Is)\nProject: ${DAEDALUS_ROOT}\nCheck: ${DAEDALUS_ROOT}/out/runs/${WORKFLOW_NAME}/"
fi
exit "${RUN_EXIT}"
