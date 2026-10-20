#!/usr/bin/env bash
# Resolve YAML config (same precedence as scripts/daedalus_read_config.R).
#
# Usage from a module script under analyses/<module>/:
#   DAEDALUS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
#   # shellcheck source=../../scripts/daedalus-read-config.sh
#   source "${DAEDALUS_ROOT}/scripts/daedalus-read-config.sh"
#   root_dir="$(daedalus_yaml_get root_dir)"

daedalus_resolve_root() {
  if [[ -n "${DAEDALUS_ROOT:-}" ]]; then
    echo "${DAEDALUS_ROOT}"
    return 0
  fi
  if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
    cd "$(dirname "${BASH_SOURCE[1]}")/../.." && pwd
    return 0
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

daedalus_config_file() {
  local daedalus_root
  daedalus_root="$(daedalus_resolve_root)"
  if [[ -n "${DAEDALUS_CONFIG_FILE:-}" ]]; then
    if [[ -f "${DAEDALUS_CONFIG_FILE}" ]]; then
      echo "${DAEDALUS_CONFIG_FILE}"
      return 0
    fi
    echo "DAEDALUS_CONFIG_FILE is set but not found: ${DAEDALUS_CONFIG_FILE}" >&2
    return 1
  fi
  if [[ -f "${daedalus_root}/project_parameters.Config.yaml" ]]; then
    echo "${daedalus_root}/project_parameters.Config.yaml"
  else
    echo "No daedalus config found under ${daedalus_root}" >&2
    return 1
  fi
}

daedalus_log_config_file() {
  echo "Using config: $(daedalus_config_file)"
}

daedalus_yaml_r() {
  local daedalus_root rcode
  daedalus_root="$(daedalus_resolve_root)"
  rcode="$1"
  Rscript --vanilla -e "
    source('${daedalus_root}/scripts/daedalus_read_config.R')
    cfg <- daedalus_read_config('${daedalus_root}')
    ${rcode}
  "
}

# Print a top-level scalar value.
daedalus_yaml_get() {
  local key="$1"
  _daedalus_yaml_r "
    val <- cfg[['${key}']]
    if (is.null(val) || length(val) == 0L) quit(status=1)
    if (is.logical(val)) {
      cat(ifelse(val, 'TRUE', 'FALSE'))
    } else if (is.list(val)) {
      quit(status=1)
    } else {
      cat(as.character(val[[1L]]))
    }
  "
}

# Print one line per list element (skips null/empty entries).
daedalus_yaml_list() {
  local key="$1"
  _daedalus_yaml_r "
    val <- cfg[['${key}']]
    if (is.null(val)) quit(status=1)
    if (is.list(val) && !is.data.frame(val)) {
      for (x in val) {
        if (!is.null(x) && nzchar(as.character(x))) cat(x, '\n', sep='')
      }
    } else if (length(val) > 1L) {
      for (x in val) cat(x, '\n', sep='')
    } else if (!is.null(val) && nzchar(as.character(val))) {
      cat(val)
    }
  "
}

# Sample IDs from config \`sample\` list, or ID column of project_metadata.tsv.
daedalus_sample_ids() {
  local ids
  ids="$(daedalus_yaml_list sample 2>/dev/null || true)"
  if [[ -n "${ids}" ]]; then
    printf '%s\n' "${ids}"
    return 0
  fi

  local metadata_dir metadata_file tsv
  metadata_dir="$(daedalus_yaml_get metadata_dir)"
  metadata_file="$(daedalus_yaml_get metadata_file)"
  tsv="${metadata_dir}/${metadata_file}"
  if [[ ! -f "${tsv}" ]]; then
    echo "No sample list in config and metadata not found: ${tsv}" >&2
    return 1
  fi
  tail -n +2 "${tsv}" | cut -f1
}
