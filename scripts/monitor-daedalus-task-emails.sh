#!/usr/bin/env bash
# Poll Sprocket run directories and email CONTACT_EMAIL on module start/complete.
#
# Usage:
#   monitor-daedalus-task-emails.sh --daedalus-root PATH --to EMAIL --watch-pid PID [--interval SEC]
#   monitor-daedalus-task-emails.sh --daedalus-root PATH --to EMAIL --finalize-only
#
# Completion is detected from Sprocket artifacts (outputs.json, work/*.done) as well as
# LSF status, because bjobs often returns UNKNOWN after a job leaves the active queue.

set -euo pipefail

DAEDALUS_ROOT=""
NOTIFY_EMAIL=""
WATCH_PID=""
INTERVAL=30
FINALIZE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --daedalus-root) DAEDALUS_ROOT="$2"; shift 2 ;;
    --to) NOTIFY_EMAIL="$2"; shift 2 ;;
    --watch-pid) WATCH_PID="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --finalize-only) FINALIZE_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ "${FINALIZE_ONLY}" -eq 1 ]]; then
  [[ -n "${DAEDALUS_ROOT}" && -n "${NOTIFY_EMAIL}" ]] || {
    echo "Usage: monitor-daedalus-task-emails.sh --daedalus-root PATH --to EMAIL --finalize-only" >&2
    exit 1
  }
else
  [[ -n "${DAEDALUS_ROOT}" && -n "${NOTIFY_EMAIL}" && -n "${WATCH_PID}" ]] || {
    echo "Usage: monitor-daedalus-task-emails.sh --daedalus-root PATH --to EMAIL --watch-pid PID" >&2
    exit 1
  }
fi

NOTIFY_SCRIPT="${DAEDALUS_ROOT}/scripts/daedalus-notify-email.sh"
RUNS_ROOT="${DAEDALUS_ROOT}/out/runs/daedalus_from_cellranger"
STATE_DIR="${DAEDALUS_ROOT}/inputs"

send_module_email() {
  local subject="$1"
  local body="$2"
  bash "${NOTIFY_SCRIPT}" --to "${NOTIFY_EMAIL}" --subject "${subject}" --body "${body}" || true
}

normalize_module() {
  local alias="$1"
  case "${alias}" in
    upstream) echo "upstream" ;;
    integrative*) echo "integrative" ;;
    cluster*) echo "cluster" ;;
    contamination*) echo "contamination_removal" ;;
    cell_types*) echo "cell_types" ;;
    clone_phylogeny*) echo "clone_phylogeny" ;;
    de_go*) echo "de_go" ;;
    rshiny*) echo "rshiny" ;;
    project_updates*) echo "project_updates" ;;
    *) return 1 ;;
  esac
}

module_label() {
  local module="$1"
  case "${module}" in
    upstream) echo "Upstream analysis" ;;
    integrative) echo "Integrative analysis" ;;
    cluster) echo "Cluster cell calling" ;;
    contamination_removal) echo "Contamination removal" ;;
    cell_types) echo "Cell types annotation" ;;
    clone_phylogeny) echo "Clone phylogeny" ;;
    de_go) echo "DE/GO analysis" ;;
    rshiny) echo "R Shiny app" ;;
    project_updates) echo "Project updates / report" ;;
    *) echo "${module}" ;;
  esac
}

state_file_for_run() {
  local run_id="$1"
  echo "${STATE_DIR}/.daedalus-module-email-state-${run_id}"
}

is_marked() {
  local state_file="$1"
  local key="$2"
  [[ -f "${state_file}" ]] && grep -Fxq "${key}" "${state_file}"
}

mark() {
  local state_file="$1"
  local key="$2"
  mkdir -p "${STATE_DIR}"
  echo "${key}" >> "${state_file}"
}

resolve_calls_dir() {
  local latest_link="${RUNS_ROOT}/_latest"
  if [[ -L "${latest_link}" || -d "${latest_link}" ]]; then
    local target
    target="$(readlink -f "${latest_link}" 2>/dev/null || echo "${latest_link}")"
    if [[ -d "${target}/calls" ]]; then
      echo "${target}/calls"
      return 0
    fi
  fi
  local newest
  newest="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d ! -name '_latest' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -1 | awk '{print $2}')"
  if [[ -n "${newest}" && -d "${newest}/calls" ]]; then
    echo "${newest}/calls"
    return 0
  fi
  return 1
}

job_lsf_status() {
  local job_id="$1"
  local line
  line="$(bjobs -noheader -o stat "${job_id}" 2>/dev/null | head -1 | tr -d '[:space:]')"
  if [[ -n "${line}" ]]; then
    echo "${line}"
    return 0
  fi
  line="$(bjobs -a -noheader -o stat "${job_id}" 2>/dev/null | head -1 | tr -d '[:space:]')"
  if [[ -n "${line}" ]]; then
    echo "${line}"
    return 0
  fi
  echo "UNKNOWN"
}

lsf_status_upper() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Sprocket wrote outputs or the WDL task left a *.done flag under work/.
call_succeeded_on_disk() {
  local call_path="$1"
  local attempt_dir="$2"
  [[ -f "${call_path}outputs.json" ]] && return 0
  [[ -d "${attempt_dir}/work" ]] && compgen -G "${attempt_dir}/work/*.done" >/dev/null && return 0
  return 1
}

# pending | success | failed
module_outcome() {
  local call_path="$1"
  local attempt_dir="$2"
  local job_id="$3"

  if call_succeeded_on_disk "${call_path}" "${attempt_dir}"; then
    echo "success"
    return 0
  fi

  local status upper
  status="$(job_lsf_status "${job_id}")"
  upper="$(lsf_status_upper "${status}")"
  case "${upper}" in
    DONE) echo "success"; return 0 ;;
    EXIT|ZOMBI|UNKWN|UNKNOWN) echo "failed"; return 0 ;;
  esac
  echo "pending"
}

poll_modules_once() {
  local calls_dir run_id state_file
  calls_dir="$(resolve_calls_dir 2>/dev/null)" || return 0
  run_id="$(basename "$(dirname "${calls_dir}")")"
  state_file="$(state_file_for_run "${run_id}")"

  for call_path in "${calls_dir}"/*/; do
    [[ -d "${call_path}" ]] || continue
    local alias module label attempt_dir job_id_file job_id
    alias="$(basename "${call_path}")"
    if ! module="$(normalize_module "${alias}")"; then
      continue
    fi
    label="$(module_label "${module}")"
    attempt_dir="${call_path}attempts/0"
    job_id_file="${attempt_dir}/job_id"

    [[ -f "${job_id_file}" ]] || continue
    job_id="$(tr -d '[:space:]' < "${job_id_file}")"

    local start_key="${module}:started"
    if ! is_marked "${state_file}" "${start_key}"; then
      send_module_email \
        "[daedalus] ${module}: started" \
        "${label} started at $(date -Is)
LSF job: ${job_id}
Project: ${DAEDALUS_ROOT}"
      mark "${state_file}" "${start_key}"
    fi

    local complete_key="${module}:completed"
    local fail_key="${module}:failed"
    if is_marked "${state_file}" "${complete_key}" || is_marked "${state_file}" "${fail_key}"; then
      continue
    fi

    local outcome
    outcome="$(module_outcome "${call_path}" "${attempt_dir}" "${job_id}")"
    case "${outcome}" in
      success)
        send_module_email \
          "[daedalus] ${module}: completed" \
          "${label} completed successfully at $(date -Is)
LSF job: ${job_id}
Project: ${DAEDALUS_ROOT}"
        mark "${state_file}" "${complete_key}"
        ;;
      failed)
        send_module_email \
          "[daedalus] ${module}: failed" \
          "${label} failed at $(date -Is)
LSF job: ${job_id}
Project: ${DAEDALUS_ROOT}
Check: ${attempt_dir}/stderr"
        mark "${state_file}" "${fail_key}"
        ;;
    esac
  done
}

if [[ "${FINALIZE_ONLY}" -eq 1 ]]; then
  for _pass in 1 2 3; do
    poll_modules_once
    sleep 15
  done
  exit 0
fi

while kill -0 "${WATCH_PID}" 2>/dev/null; do
  poll_modules_once
  sleep "${INTERVAL}"
done

# Final passes after sprocket exits (LSF history + Sprocket outputs may lag).
for _pass in 1 2 3 4; do
  poll_modules_once
  sleep 15
done
