#!/usr/bin/env Rscript
################################################################################
# daedalus_validate_outputs.R
#
# Biological / consistency checks on completed module outputs (enabled modules
# only). Intended to run after a successful Sprocket downstream workflow.
#
# Usage:
#   Rscript scripts/daedalus_validate_outputs.R --daedalus-root PATH [--json PATH] [--strict]
#
# Exit 0 = pass (warnings allowed); exit 1 = one or more errors.
################################################################################

suppressPackageStartupMessages({
  if (!requireNamespace("yaml", quietly = TRUE)) stop("Install yaml")
})

`%||%` <- function(a, b) if (is.null(a)) b else a

parse_args <- function(args) {
  out <- list(daedalus_root = NULL, json = NULL, strict = FALSE)
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key == "--daedalus-root") { i <- i + 1L; out$daedalus_root <- args[[i]] }
    else if (key == "--json") { i <- i + 1L; out$json <- args[[i]] }
    else if (key == "--strict") out$strict <- TRUE
    else stop("Unknown argument: ", key)
    i <- i + 1L
  }
  if (is.null(out$daedalus_root)) stop("--daedalus-root is required")
  out
}

load_validation_config <- function(daedalus_root) {
  daedalus_root <- normalizePath(daedalus_root, winslash = "/", mustWork = TRUE)
  generated <- file.path(daedalus_root, "inputs", "project_parameters.generated.yaml")
  master <- file.path(daedalus_root, "project_parameters.Config.yaml")
  path <- if (file.exists(generated)) generated else master
  cfg <- yaml::read_yaml(path)
  list(cfg = cfg, daedalus_root = daedalus_root, config_path = path)
}

workflow_toggles <- function(cfg) {
  wp <- cfg$workflow_profile %||% list()
  list(
    run_upstream = isTRUE(wp$run_upstream %||% FALSE),
    run_integrative = isTRUE(wp$run_integrative %||% FALSE),
    run_cluster = isTRUE(wp$run_cluster %||% FALSE),
    run_contamination_removal = isTRUE(wp$run_contamination_removal %||% FALSE),
    run_cell_types = isTRUE(wp$run_cell_types %||% FALSE),
    run_clone_phylogeny = isTRUE(wp$run_clone_phylogeny %||% FALSE),
    run_de_go = isTRUE(wp$run_de_go %||% FALSE),
    run_rshiny = isTRUE(wp$run_rshiny %||% FALSE),
    run_project_updates = isTRUE(wp$run_project_updates %||% FALSE),
    run_biological_validation = isTRUE(wp$run_biological_validation %||% TRUE)
  )
}

new_report <- function() {
  list(errors = character(), warnings = character(), checks = list())
}

add_error <- function(r, msg) {
  r$errors <- c(r$errors, msg)
  r
}

add_warning <- function(r, msg) {
  r$warnings <- c(r$warnings, msg)
  r
}

add_check <- function(r, name, status, detail = "") {
  r$checks[[length(r$checks) + 1L]] <- list(name = name, status = status, detail = detail)
  r
}

metadata_sample_ids <- function(cfg) {
  md_dir <- cfg$metadata_dir
  md_file <- cfg$metadata_file %||% "project_metadata.tsv"
  path <- file.path(md_dir, md_file)
  if (!file.exists(path)) stop("Metadata not found: ", path)
  md <- read.delim(path, stringsAsFactors = FALSE)
  if (!"ID" %in% names(md)) stop("Metadata must contain column ID")
  sort(unique(trimws(as.character(md$ID))))
}

resolve_data_dir <- function(cfg, daedalus_root) {
  params <- cfg$cellranger_parameters %||% "DefaultParameters"
  data_dir <- cfg$data_dir %||% file.path(
    daedalus_root, "analyses", "cellranger-analysis", "results",
    "02_cellranger_count", params
  )
  if (!grepl("^/", data_dir)) {
    data_dir <- file.path(cfg$root_dir %||% daedalus_root, sub("^\\./", "", data_dir))
  }
  normalizePath(data_dir, winslash = "/", mustWork = FALSE)
}

cellranger_cells_per_sample <- function(data_dir) {
  if (!dir.exists(data_dir)) return(list())
  sample_dirs <- list.dirs(data_dir, full.names = TRUE, recursive = FALSE)
  out <- list()
  for (d in sample_dirs) {
    sid <- basename(d)
    metrics <- file.path(d, "outs", "metrics_summary.csv")
    if (!file.exists(metrics)) next
    m <- tryCatch(
      read.csv(metrics, check.names = FALSE, stringsAsFactors = FALSE),
      error = function(e) NULL
    )
    if (is.null(m) || nrow(m) != 1L) next
    col <- "Estimated Number of Cells"
    if (sum(names(m) == col) != 1L) next
    raw <- gsub(",", "", trimws(as.character(m[[col]][[1L]])), fixed = TRUE)
    val <- suppressWarnings(as.integer(raw))
    if (!is.na(val) && val >= 1L) out[[sid]] <- val
  }
  out
}

seurat_ncol <- function(path) {
  if (!requireNamespace("SeuratObject", quietly = TRUE) &&
      !requireNamespace("Seurat", quietly = TRUE)) {
    return(NA_integer_)
  }
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(obj)) return(NA_integer_)
  as.integer(ncol(obj))
}

find_markers_resolution <- function(cfg) {
  raw <- cfg$resolution_list_find_markers
  if (is.null(raw)) return(NULL)
  if (length(raw) < 1L) return(NULL)
  val <- if (is.list(raw)) raw[[1L]] else raw[[1L]]
  num <- suppressWarnings(as.numeric(val))
  if (!is.na(num)) return(num)
  trimws(as.character(val))
}

format_cluster_resolution <- function(res) {
  if (is.numeric(res) && !is.na(res) && res == as.integer(res)) {
    return(as.character(as.integer(res)))
  }
  as.character(res)
}

cluster_res_metadata_col <- function(cfg, res) {
  assay <- cfg$assay_clustering_module %||% "RNA"
  paste0(assay, "_snn_res.", format_cluster_resolution(res))
}

seurat_metadata_df <- function(obj) {
  if (is.null(obj)) return(NULL)
  tryCatch({
    if (requireNamespace("SeuratObject", quietly = TRUE)) {
      return(as.data.frame(SeuratObject::`[[`(obj)))
    }
    if (requireNamespace("Seurat", quietly = TRUE)) {
      return(as.data.frame(Seurat::`[[`(obj)))
    }
    NULL
  }, error = function(e) NULL)
}

resolve_cluster_seurat_path <- function(cfg, root) {
  mod_label <- cfg$resolution_clustering_module %||% "default_multiple"
  step1_dir <- file.path(
    root, "analyses", "cluster-cell-calling", "results",
    paste0("01_cluster_cell_calling_", mod_label)
  )
  candidates <- c(
    file.path(step1_dir, "seurat_obj_clusters_all.rds")
  )
  res <- find_markers_resolution(cfg)
  if (!is.null(res)) {
    candidates <- c(
      candidates,
      file.path(step1_dir, paste0("seurat_obj_clusters_", format_cluster_resolution(res), ".rds"))
    )
  }
  hits <- candidates[file.exists(candidates)]
  if (length(hits)) return(hits[[1L]])

  results_root <- file.path(root, "analyses", "cluster-cell-calling", "results")
  if (!dir.exists(results_root)) return(NULL)
  recursive <- list.files(
    results_root,
    pattern = "^seurat_obj_clusters_all\\.rds$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (!length(recursive)) return(NULL)
  ord <- order(
    grepl("/01_cluster_cell_calling_", recursive, fixed = TRUE),
    decreasing = TRUE
  )
  recursive[[ord[[1L]]]]
}

cluster_count_for_resolution <- function(obj, cfg, res) {
  meta <- seurat_metadata_df(obj)
  if (is.null(meta)) return(list(n = NA_integer_, column = NA_character_, source = "metadata"))
  col <- cluster_res_metadata_col(cfg, res)
  if (col %in% names(meta)) {
    n <- length(unique(meta[[col]]))
    return(list(n = as.integer(n), column = col, source = "metadata"))
  }
  suffix <- paste0("_snn_res.", format_cluster_resolution(res))
  matches <- grep(paste0(suffix, "$"), names(meta), value = TRUE)
  if (length(matches) == 1L) {
    n <- length(unique(meta[[matches[[1L]]]]))
    return(list(n = as.integer(n), column = matches[[1L]], source = "metadata"))
  }
  list(n = NA_integer_, column = col, source = "metadata")
}

report_cluster_count <- function(r, n_cl, count_detail) {
  if (is.na(n_cl)) {
    r <- add_warning(r, "Could not determine cluster count for validation")
    return(add_check(r, "cluster_count", "warn", "unknown"))
  }
  if (n_cl < 2L) {
    r <- add_warning(r, sprintf(
      "Fewer than 2 clusters detected (%d); expected at least 2 for meaningful clustering (%s)",
      n_cl, count_detail
    ))
    return(add_check(r, "cluster_count", "warn", count_detail))
  }
  add_check(r, "cluster_count", "pass", count_detail)
}

validate_metadata_cellranger <- function(r, cfg, daedalus_root) {
  meta_ids <- metadata_sample_ids(cfg)
  data_dir <- resolve_data_dir(cfg, daedalus_root)
  cr <- cellranger_cells_per_sample(data_dir)
  cr_ids <- sort(names(cr))

  missing_cr <- setdiff(meta_ids, cr_ids)
  extra_cr <- setdiff(cr_ids, meta_ids)
  if (length(missing_cr)) {
    r <- add_error(r, paste0(
      "Metadata sample IDs missing Cell Ranger outputs under data_dir: ",
      paste(missing_cr, collapse = ", ")
    ))
    r <- add_check(r, "metadata_vs_cellranger_ids", "fail", paste(missing_cr, collapse = ", "))
  } else if (length(extra_cr)) {
    r <- add_warning(r, paste0(
      "Cell Ranger sample dirs not in metadata ID column: ",
      paste(extra_cr, collapse = ", ")
    ))
    r <- add_check(r, "metadata_vs_cellranger_ids", "warn", "extra CR dirs")
  } else {
    r <- add_check(r, "metadata_vs_cellranger_ids", "pass",
                   sprintf("%d samples aligned", length(meta_ids)))
  }

  zero_cr <- names(cr)[unlist(cr) < 1L]
  if (length(zero_cr)) {
    r <- add_error(r, paste0("Cell Ranger reported zero cells for: ", paste(zero_cr, collapse = ", ")))
  }
  list(report = r, cellranger = cr, metadata_ids = meta_ids)
}

validate_upstream <- function(r, cfg, daedalus_root, cellranger) {
  root <- cfg$root_dir %||% daedalus_root
  filtered_rds <- file.path(
    root, "analyses", "upstream-analysis", "results", "04_Filter_object",
    "seurat_obj_merged_filtered.rds"
  )
  if (!file.exists(filtered_rds)) {
    r <- add_error(r, paste0("Missing upstream deliverable: ", filtered_rds))
    return(add_check(r, "upstream_filtered_seurat", "fail", "file missing"))
  }
  r <- add_check(r, "upstream_filtered_seurat", "pass", filtered_rds)

  n <- seurat_ncol(filtered_rds)
  if (is.na(n)) {
    r <- add_warning(r, "Could not read cell count from upstream filtered Seurat object (Seurat not installed?)")
    return(r)
  }
  if (n < 100L) {
    r <- add_warning(r, sprintf("Upstream filtered object has only %d cells", n))
  }

  total_cr <- sum(unlist(cellranger))
  if (total_cr > 0L && n > total_cr * 1.05) {
    r <- add_error(r, sprintf(
      "Upstream filtered cells (%d) exceed total Cell Ranger estimated cells (%d)",
      n, total_cr
    ))
  } else if (total_cr > 0L && n < total_cr * 0.01) {
    r <- add_warning(r, sprintf(
      "Upstream filtered cells (%d) are <1%% of Cell Ranger total (%d); confirm filters",
      n, total_cr
    ))
  } else {
    r <- add_check(r, "upstream_vs_cellranger_cells", "pass",
                   sprintf("filtered=%d CR_total=%d", n, total_cr))
  }
  r
}

validate_integrative <- function(r, cfg, daedalus_root, upstream_ncol = NA_integer_) {
  root <- cfg$root_dir %||% daedalus_root
  method <- cfg$integration_method %||% "harmony"
  rds <- file.path(
    root, "analyses", "integrative-analysis", "results",
    paste0("seurat_obj_integrated_", method, ".rds")
  )
  if (!file.exists(rds)) {
    r <- add_error(r, paste0("Missing integrative deliverable: ", rds))
    return(add_check(r, "integrative_seurat", "fail", "file missing"))
  }
  n <- seurat_ncol(rds)
  r <- add_check(r, "integrative_seurat", "pass", sprintf("%s ncol=%s", basename(rds), n))
  if (!is.na(upstream_ncol) && !is.na(n) && abs(n - upstream_ncol) > max(50L, upstream_ncol * 0.05)) {
    r <- add_warning(r, sprintf(
      "Integrative ncol (%d) differs from upstream filtered (%d) by more than 5%%",
      n, upstream_ncol
    ))
  }
  r
}

validate_cluster <- function(r, cfg, daedalus_root) {
  root <- cfg$root_dir %||% daedalus_root
  results_root <- file.path(root, "analyses", "cluster-cell-calling", "results")
  cluster_rds <- resolve_cluster_seurat_path(cfg, root)
  if (is.null(cluster_rds) || !nzchar(cluster_rds)) {
    r <- add_error(r, paste0("No cluster Seurat object under ", results_root))
    return(add_check(r, "cluster_seurat", "fail", "missing"))
  }
  r <- add_check(r, "cluster_seurat", "pass", cluster_rds)

  find_markers_res <- find_markers_resolution(cfg)
  has_seurat <- requireNamespace("SeuratObject", quietly = TRUE) ||
    requireNamespace("Seurat", quietly = TRUE)
  if (!has_seurat) {
    r <- add_warning(r, paste0(
      "Seurat not available; skipped cluster count check (cannot verify >= 2 clusters) for ",
      cluster_rds
    ))
    r <- add_check(r, "cluster_count", "warn", "skipped (no Seurat)")
  } else {
    obj <- tryCatch(readRDS(cluster_rds), error = function(e) NULL)
    if (is.null(obj)) {
      r <- add_warning(r, paste0("Could not read cluster Seurat object: ", cluster_rds))
      r <- add_check(r, "cluster_count", "warn", "unreadable object")
    } else {
      n_cl <- NA_integer_
      count_detail <- ""
      if (!is.null(find_markers_res)) {
        counted <- cluster_count_for_resolution(obj, cfg, find_markers_res)
        n_cl <- counted$n
        if (!is.na(n_cl)) {
          count_detail <- sprintf(
            "res=%s col=%s clusters=%d",
            format_cluster_resolution(find_markers_res),
            counted$column,
            n_cl
          )
        } else {
          r <- add_warning(r, sprintf(
            "Could not find cluster column for resolution_list_find_markers (%s); using active Idents",
            format_cluster_resolution(find_markers_res)
          ))
        }
      }
      if (is.na(n_cl)) {
        n_cl <- length(unique(SeuratObject::Idents(obj)))
        count_detail <- sprintf("idents=%d (fallback)", n_cl)
      }
      r <- report_cluster_count(r, n_cl, count_detail)
    }
  }

  if (!is.null(find_markers_res)) {
    markers_tsv <- file.path(
      results_root, "02_find_markers",
      paste0("Res_", format_cluster_resolution(find_markers_res), "_Markers_all.tsv")
    )
    if (file.exists(markers_tsv)) {
      r <- add_check(r, "find_markers_table", "pass", basename(markers_tsv))
    } else {
      r <- add_warning(r, paste0("Missing find-markers output (step 2 may not have run): ", markers_tsv))
      r <- add_check(r, "find_markers_table", "warn", "missing")
    }
  }

  r
}

validate_cell_types <- function(r, cfg, daedalus_root) {
  root <- cfg$root_dir %||% daedalus_root
  merged <- file.path(
    root, "analyses", "cell-types-annotation", "results",
    "seurat_obj_cell_types_annotations_all.rds"
  )
  broad <- file.path(
    root, "analyses", "cell-types-annotation", "results",
    "seurat_obj_SingleR_broad.rds"
  )
  if (file.exists(merged)) {
    r <- add_check(r, "cell_types_merged", "pass", merged)
  } else if (file.exists(broad)) {
    r <- add_warning(r, paste0("Merged cell-types object missing; found broad SingleR only: ", broad))
    r <- add_check(r, "cell_types_broad", "pass", broad)
  } else {
    r <- add_error(r, "Missing cell-types outputs (expected merged or SingleR broad RDS)")
    r <- add_check(r, "cell_types", "fail", "missing")
  }
  r
}

print_report <- function(r) {
  cat("==> Daedalus biological validation\n")
  for (chk in r$checks) {
    cat(sprintf("  [%s] %s", chk$status, chk$name))
    if (nzchar(chk$detail)) cat(" — ", chk$detail, sep = "")
    cat("\n")
  }
  if (length(r$warnings)) {
    cat("\nWarnings:\n")
    for (w in r$warnings) cat("  - ", w, "\n", sep = "")
  }
  if (length(r$errors)) {
    cat("\nErrors:\n")
    for (e in r$errors) cat("  - ", e, "\n", sep = "")
  }
}

main <- function() {
  args <- parse_args(commandArgs(trailingOnly = TRUE))
  loaded <- load_validation_config(args$daedalus_root)
  cfg <- loaded$cfg
  toggles <- workflow_toggles(cfg)

  if (!isTRUE(toggles$run_biological_validation)) {
    cat("Biological validation disabled (workflow_profile.run_biological_validation: false)\n")
    quit(status = 0)
  }

  r <- new_report()
  base <- validate_metadata_cellranger(r, cfg, loaded$daedalus_root)
  r <- base$report
  cellranger <- base$cellranger

  upstream_ncol <- NA_integer_
  if (isTRUE(toggles$run_upstream)) {
    r <- validate_upstream(r, cfg, loaded$daedalus_root, cellranger)
    filtered_rds <- file.path(
      cfg$root_dir %||% loaded$daedalus_root,
      "analyses", "upstream-analysis", "results", "04_Filter_object",
      "seurat_obj_merged_filtered.rds"
    )
    if (file.exists(filtered_rds)) upstream_ncol <- seurat_ncol(filtered_rds)
  }
  if (isTRUE(toggles$run_integrative)) {
    r <- validate_integrative(r, cfg, loaded$daedalus_root, upstream_ncol)
  }
  if (isTRUE(toggles$run_cluster)) {
    r <- validate_cluster(r, cfg, loaded$daedalus_root)
  }
  if (isTRUE(toggles$run_cell_types)) {
    r <- validate_cell_types(r, cfg, loaded$daedalus_root)
  }

  print_report(r)

  payload <- list(
    config = loaded$config_path,
    errors = r$errors,
    warnings = r$warnings,
    checks = r$checks
  )
  if (!is.null(args$json)) {
    if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Install jsonlite")
    json_path <- normalizePath(args$json, winslash = "/", mustWork = FALSE)
    dir.create(dirname(json_path), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(payload, json_path, auto_unbox = TRUE, pretty = TRUE)
    cat("Wrote ", json_path, "\n", sep = "")
  }

  status <- if (length(r$errors) || (isTRUE(args$strict) && length(r$warnings))) 1L else 0L
  quit(status = status)
}

if (sys.nframe() == 0L) main()
