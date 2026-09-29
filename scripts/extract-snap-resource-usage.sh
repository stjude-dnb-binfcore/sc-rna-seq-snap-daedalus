#!/usr/bin/env bash
# Extract per-module LSF resource usage for a completed Sprocket run into
# out/resource_usage/ (CSV + JSON), matching the Daedalus prototype layout.
#
# Usage (from project root):
#   bash scripts/extract-snap-resource-usage.sh
#   bash scripts/extract-snap-resource-usage.sh --run-id 2026-09-12_143900834470824
#   bash scripts/extract-snap-resource-usage.sh --export-dir /path/to/roi/input
#
# Requires: jq, bjobs — run on a St. Jude HPC login/submit node (not from a Mac SMB mount).

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/local/bin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COLLECT="${SCRIPT_DIR}/collect-snap-resource-usage.sh"

EXTRA=()
HAS_SNAP_ROOT=0
HAS_LATEST=0
HAS_RUN_ID=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snap-root) HAS_SNAP_ROOT=1; EXTRA+=("$1" "$2"); shift 2 ;;
    --run-id) HAS_RUN_ID=1; EXTRA+=("$1" "$2"); shift 2 ;;
    --latest) HAS_LATEST=1; EXTRA+=("$1"); shift ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

[[ "${HAS_SNAP_ROOT}" -eq 1 ]] || EXTRA=(--snap-root "${SNAP_ROOT}" "${EXTRA[@]}")
[[ "${HAS_LATEST}" -eq 1 || "${HAS_RUN_ID}" -eq 1 ]] || EXTRA+=(--latest)
EXTRA+=(--json)

exec bash "${COLLECT}" "${EXTRA[@]}"
