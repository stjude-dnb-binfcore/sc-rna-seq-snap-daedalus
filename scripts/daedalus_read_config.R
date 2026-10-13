#' Resolve and read the pipeline project YAML config.
#'
#' WDL / Sprocket tasks set \code{DAEDALUS_CONFIG_FILE} (see tasks/post_cellranger_required.wdl and tasks/post_cellranger_optional.wdl) to
#' \code{inputs/project_parameters.generated.yaml}. Interactive runs, LSF jobs,
#' and launch_full_pipeline.sh do not set that variable and use the master
#' \code{project_parameters.Config.yaml} instead.
#'
#' @param daedalus_root Project root (parent of \code{analyses/} and \code{inputs/}).
#' @return Parsed YAML as a list; path used is in attribute \code{daedalus_config_path}.
#' @export
daedalus_is_wdl_run <- function() {
  nzchar(Sys.getenv("DAEDALUS_CONFIG_FILE", unset = ""))
}

daedalus_read_master_config <- function(daedalus_root = NULL) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Install yaml: install.packages('yaml')")
  }

  daedalus_root <- daedalus_resolve_root(daedalus_root)
  config_path <- file.path(daedalus_root, "project_parameters.Config.yaml")

  if (!file.exists(config_path)) {
    stop("Config not found: ", config_path)
  }

  config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)
  cfg <- yaml::read_yaml(config_path)
  attr(cfg, "daedalus_config_path") <- config_path
  cfg
}

daedalus_read_config <- function(daedalus_root = NULL) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Install yaml: install.packages('yaml')")
  }

  daedalus_root <- daedalus_resolve_root(daedalus_root)

  if (daedalus_is_wdl_run()) {
    env_path <- Sys.getenv("DAEDALUS_CONFIG_FILE", unset = "")
    if (!file.exists(env_path)) {
      stop("DAEDALUS_CONFIG_FILE is set but not found: ", env_path)
    }
    config_path <- normalizePath(env_path, winslash = "/", mustWork = TRUE)
  } else {
    return(daedalus_read_master_config(daedalus_root))
  }

  cfg <- yaml::read_yaml(config_path)
  attr(cfg, "daedalus_config_path") <- config_path
  cfg
}

#' Load project YAML for the current run mode (WDL vs interactive/LSF).
#'
#' Call from module entry scripts under \code{analyses/<module>/}.
daedalus_load_project_config <- function(daedalus_root = NULL) {
  daedalus_root <- daedalus_resolve_root(daedalus_root)
  cfg <- if (daedalus_is_wdl_run()) {
    daedalus_read_config(daedalus_root)
  } else {
    daedalus_read_master_config(daedalus_root)
  }
  message("Using config: ", attr(cfg, "daedalus_config_path"))
  cfg
}

daedalus_config_path <- function(daedalus_root = NULL) {
  attr(daedalus_read_config(daedalus_root = daedalus_root), "daedalus_config_path")
}

daedalus_resolve_root <- function(daedalus_root = NULL) {
  if (is.null(daedalus_root)) {
    normalizePath(file.path(getwd(), "..", ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(daedalus_root, winslash = "/", mustWork = TRUE)
  }
}
