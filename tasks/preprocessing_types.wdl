version 1.3

struct ExistingCellRangerInput {
    String id
    Directory count_output

    meta {
        description: "Existing Cell Ranger output supplied for one sample."
    }

    parameter_meta {
        id: "Sample identifier, matching project metadata `ID`."
        count_output: "Cell Ranger `outs` directory for the sample."
    }
}

struct CellRangerOutput {
    String sample_id
    Directory count_output
    File metrics_csv
    Int estimated_cells

    meta {
        description: "Validated Cell Ranger output with estimated cell count."
    }

    parameter_meta {
        sample_id: "Sample identifier."
        count_output: "Cell Ranger `outs` directory for the sample."
        metrics_csv: "Cell Ranger `metrics_summary.csv` file."
        estimated_cells: "Estimated number of cells reported by Cell Ranger."
    }
}

struct DownstreamResources {
    Int upstream_cpu
    Int upstream_memory_gb
    Int upstream_future_globals_gib
    Int integrative_cpu
    Int integrative_memory_gb
    Int integrative_future_globals_gib
    Int cluster_cpu
    Int cluster_memory_gb
    Int cluster_future_globals_gib
    Int contamination_cpu
    Int contamination_memory_gb
    Int contamination_future_globals_gib
    Int cell_types_cpu
    Int cell_types_memory_gb
    Int clone_phylogeny_cpu
    Int clone_phylogeny_memory_gb
    Int de_go_cpu
    Int de_go_memory_gb
    Int de_go_future_globals_gib
    Int rshiny_cpu
    Int rshiny_memory_gb
    Int project_updates_cpu
    Int project_updates_memory_gb

    meta {
        description: "LSF resource requests derived from sample count and estimated cells."
    }

    parameter_meta {
        upstream_cpu: "CPU cores for upstream analysis."
        upstream_memory_gb: "Memory request in GB for upstream analysis."
        upstream_future_globals_gib: "R `future.globals.maxSize` limit in GiB for upstream analysis."
        integrative_cpu: "CPU cores for integrative analysis."
        integrative_memory_gb: "Memory request in GB for integrative analysis."
        integrative_future_globals_gib: "R `future.globals.maxSize` limit in GiB for integrative analysis."
        cluster_cpu: "CPU cores for cluster cell calling."
        cluster_memory_gb: "Memory request in GB for cluster cell calling."
        cluster_future_globals_gib: "R `future.globals.maxSize` limit in GiB for cluster cell calling."
        contamination_cpu: "CPU cores for contamination removal."
        contamination_memory_gb: "Memory request in GB for contamination removal."
        contamination_future_globals_gib: "R `future.globals.maxSize` limit in GiB for contamination removal."
        cell_types_cpu: "CPU cores for cell-type annotation."
        cell_types_memory_gb: "Memory request in GB for cell-type annotation."
        clone_phylogeny_cpu: "CPU cores for clone phylogeny analysis."
        clone_phylogeny_memory_gb: "Memory request in GB for clone phylogeny analysis."
        de_go_cpu: "CPU cores for differential expression and GO analysis."
        de_go_memory_gb: "Memory request in GB for differential expression and GO analysis."
        de_go_future_globals_gib: "R `future.globals.maxSize` limit in GiB for DE/GO analysis."
        rshiny_cpu: "CPU cores for R Shiny app packaging."
        rshiny_memory_gb: "Memory request in GB for R Shiny app packaging."
        project_updates_cpu: "CPU cores for project report generation."
        project_updates_memory_gb: "Memory request in GB for project report generation."
    }
}
