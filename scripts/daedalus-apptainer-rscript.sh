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

DAEDALUS_ROOT="$(cd "${DAEDALUS_ROOT}" && pwd)"
export DAEDALUS_ROOT
# shellcheck source=daedalus-read-config.sh
source "${SCRIPT_DIR}/daedalus-read-config.sh"

RUNNER=()
if command -v apptainer >/dev/null 2>&1; then
  RUNNER=(apptainer)
elif command -v singularity >/dev/null 2>&1; then
  RUNNER=(singularity)
fi

if [[ ${#RUNNER[@]} -eq 0 ]]; then
  echo "WARN: apptainer/singularity not in PATH; running host Rscript (Seurat checks may be skipped)." >&2
  echo "      On St. Jude HPC: module load singularity" >&2
  exec Rscript "$@"
fi

CONTAINER="$(daedalus_container_image)" || true
if [[ -z "${CONTAINER:-}" || ! -f "${CONTAINER}" ]]; then
  echo "WARN: Container image not found (${CONTAINER:-<unset>}); running host Rscript." >&2
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
