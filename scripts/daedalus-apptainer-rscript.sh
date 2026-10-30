#!/usr/bin/env bash
# Run Rscript inside the project Seurat Apptainer image (same stack as Sprocket tasks).
#
# Host `module load sprocket R` does not include Seurat; use this for validation and
# other scripts that read .rds Seurat objects.
#
# Usage:
#   bash scripts/daedalus-apptainer-rscript.sh [--daedalus-root PATH] -- SCRIPT [Rscript args...]
#
# Example:
#   bash scripts/daedalus-apptainer-rscript.sh --daedalus-root . -- \
#     scripts/daedalus_validate_outputs.R --daedalus-root . --json out/validation/biological_validation.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEDALUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --daedalus-root) DAEDALUS_ROOT="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help)
      sed -n '2,12p' "$0" | tail -n +2
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (use -- before Rscript arguments)" >&2
      exit 1
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Usage: bash scripts/daedalus-apptainer-rscript.sh [--daedalus-root PATH] -- SCRIPT [args...]" >&2
  exit 1
fi

export DAEDALUS_ROOT
# shellcheck source=daedalus-read-config.sh
source "${SCRIPT_DIR}/daedalus-read-config.sh"

CONTAINER="$(daedalus_container_image)" || true

RUNNER=()
if command -v apptainer >/dev/null 2>&1; then
  RUNNER=(apptainer)
elif command -v singularity >/dev/null 2>&1; then
  RUNNER=(singularity)
fi

if [[ ${#RUNNER[@]} -eq 0 || -z "${CONTAINER:-}" || ! -f "${CONTAINER}" ]]; then
  echo "WARN: Running on host R (container unavailable or missing: ${CONTAINER:-<unset>})" >&2
  exec Rscript "$@"
fi

BINDS=(--bind "${DAEDALUS_ROOT}:${DAEDALUS_ROOT}")
for mount in /research /research_jude /hpcf; do
  if [[ -d "${mount}" ]]; then
    BINDS+=(--bind "${mount}:${mount}")
  fi
done

exec "${RUNNER[@]}" exec --cleanenv "${BINDS[@]}" -W "${DAEDALUS_ROOT}" \
  "${CONTAINER}" Rscript "$@"
