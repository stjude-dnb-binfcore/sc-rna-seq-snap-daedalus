version 1.3

import "../tasks/post_cellranger_optional.wdl" as optional
import "../tasks/post_cellranger_required.wdl" as required
import "../tasks/pre_cellranger.wdl" as preprocessing

workflow daedalus_from_cellranger {
    meta {
        description: "Run Daedalus downstream analysis from existing Cell Ranger outputs."
        category: "Daedalus"
        author: "DNB Bioinformatics Core"
        help: "Optional modules and `after` dependencies are documented in `workflows/MODULE_DEPENDENCIES.md`."
        external_help: "https://github.com/stjude-dnb-binfcore/sc-rna-seq-snap-daedalus/blob/main/workflows/MODULE_DEPENDENCIES.md"
        outputs: {
            cellranger_outputs: "Validated Cell Ranger outputs with estimated cell counts per sample."
            cellranger_summary: "TSV summary of sample IDs and estimated cells."
            estimated_cells: "Estimated cell counts in sample order."
            num_samples: "Number of Cell Ranger samples in the run."
            downstream_resources: "Scaled CPU, memory, and R future limits for each module."
            upstream_cpu: "CPU cores requested for upstream analysis."
            upstream_memory_gb: "Memory in GB requested for upstream analysis."
            upstream_future_globals_gib: "R future global size limit for upstream analysis."
            integrative_cpu: "CPU cores requested for integrative analysis."
            integrative_memory_gb: "Memory in GB requested for integrative analysis."
            integrative_future_globals_gib: "R future global size limit for integrative analysis."
            upstream_completion: "Completion flag when upstream analysis is enabled and succeeds."
            upstream_results: "Path to upstream analysis results when `run_upstream` is true."
            cluster_completion: "Completion flag when cluster cell calling is enabled and succeeds."
            cluster_results: "Path to cluster cell calling results when `run_cluster` is true."
            cell_types_completion: "Completion flag when cell-type annotation is enabled and succeeds."
            cell_types_results: "Path to cell-type annotation results when `run_cell_types` is true."
            rshiny_completion: "Completion flag when R Shiny packaging is enabled and succeeds."
            rshiny_results: "Path to R Shiny app results when `run_rshiny` is true."
            integrative_completion: "Completion flag when integrative analysis is enabled and succeeds."
            integrative_results: "Path to integrative analysis results when `run_integrative` is true."
            contamination_removal_completion: "Completion flag when contamination removal is enabled and succeeds."
            contamination_removal_results: "Path to contamination removal results when `run_contamination_removal` is true."
            clone_phylogeny_completion: "Completion flag when clone phylogeny is enabled and succeeds."
            clone_phylogeny_results: "Path to clone phylogeny results when `run_clone_phylogeny` is true."
            de_go_completion: "Completion flag when DE/GO analysis is enabled and succeeds."
            de_go_results: "Path to DE/GO results when `run_de_go` is true."
            project_updates_completion: "Completion flag when project updates are enabled and succeeds."
            project_updates_results: "Path to project update reports when `run_project_updates` is true."
        }
    }

    parameter_meta {
        cellranger_inputs: "Existing Cell Ranger outs directories, one struct per sample."
        resource_estimator_container: "Apptainer image for preprocessing and resource-estimation tasks."
        project_root: "Daedalus project root passed to downstream analysis modules."
        downstream_container: "Apptainer image for Daedalus R analysis modules."
        notify_email: "Email for LSF notifications on downstream module jobs."
        run_upstream: {
            description: "Run upstream Seurat QC (`analyses/upstream-analysis`).",
            group: "Modules",
        }
        run_integrative: {
            description: "Run integrative analysis (`analyses/integrative-analysis`).",
            group: "Modules",
        }
        run_cluster: {
            description: "Run cluster cell calling (`analyses/cluster-cell-calling`).",
            group: "Modules",
        }
        run_contamination_removal: {
            description: "Run cell contamination removal analysis.",
            group: "Modules",
        }
        run_cell_types: {
            description: "Run cell-type annotation (`analyses/cell-types-annotation`).",
            group: "Modules",
        }
        run_clone_phylogeny: {
            description: "Run clone phylogeny analysis.",
            group: "Modules",
        }
        run_de_go: {
            description: "Run differential expression and GO analysis.",
            group: "Modules",
        }
        run_rshiny: {
            description: "Package the R Shiny exploration app.",
            group: "Modules",
        }
        run_project_updates: {
            description: "Generate cross-module project reports.",
            group: "Modules",
        }
        resource_estimator_cpu: {
            description: "CPU cores for validation, metrics parsing, and resource estimation.",
            group: "Resource",
        }
        resource_estimator_memory_gb: {
            description: "Memory in GB for preprocessing and resource estimation tasks.",
            group: "Resource",
        }
    }

    input {
        Array[ExistingCellRangerInput]+ cellranger_inputs
        String resource_estimator_container
        String project_root
        String downstream_container
        String notify_email
        Boolean run_upstream = false
        Boolean run_integrative = false
        Boolean run_cluster = false
        Boolean run_contamination_removal = false
        Boolean run_cell_types = false
        Boolean run_clone_phylogeny = false
        Boolean run_de_go = false
        Boolean run_rshiny = false
        Boolean run_project_updates = false
        Int resource_estimator_cpu = 1
        Int resource_estimator_memory_gb = 1
    }

    scatter (cellranger_input in cellranger_inputs) {
        String sample_id = cellranger_input.id
        Directory count_output = cellranger_input.count_output
        File metrics_csv = join_paths(count_output, "metrics_summary.csv")
    }

    call preprocessing.validate_existing_cellranger { input:
        sample_ids = sample_id,
        count_outputs = count_output,
        cpu = resource_estimator_cpu,
        memory_gb = resource_estimator_memory_gb,
        container_image = resource_estimator_container,
    }

    scatter (index in range(length(cellranger_inputs))) {
        call preprocessing.parse_cellranger_metrics after validate_existing_cellranger { input:
            metrics_csv = metrics_csv[index],
            cpu = resource_estimator_cpu,
            memory_gb = resource_estimator_memory_gb,
            container_image = resource_estimator_container,
        }

        Int sample_estimated_cells = parse_cellranger_metrics.estimated_cells
        CellRangerOutput cellranger_output = CellRangerOutput {
            sample_id: sample_id[index],
            count_output: count_output[index],
            metrics_csv: metrics_csv[index],
            estimated_cells: parse_cellranger_metrics.estimated_cells,
        }
    }

    call preprocessing.estimate_downstream_resources { input:
        estimated_cells = sample_estimated_cells,
        cpu = resource_estimator_cpu,
        memory_gb = resource_estimator_memory_gb,
        container_image = resource_estimator_container,
    }

    call preprocessing.write_cellranger_summary { input:
        sample_ids = sample_id,
        estimated_cells = sample_estimated_cells,
        cpu = resource_estimator_cpu,
        memory_gb = resource_estimator_memory_gb,
        container_image = resource_estimator_container,
    }

    if (run_upstream) {
        call required.run_upstream as upstream after write_cellranger_summary { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.upstream_cpu,
            memory_gb = estimate_downstream_resources.resources.upstream_memory_gb,
            future_globals_gib = estimate_downstream_resources.resources.upstream_future_globals_gib,
        }
    }
    if (run_integrative) {
        call optional.run_integrative as integrative after upstream { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.integrative_cpu,
            memory_gb = estimate_downstream_resources.resources.integrative_memory_gb,
            future_globals_gib = estimate_downstream_resources.resources.integrative_future_globals_gib,
        }
    }

    if (run_cluster) {
        call required.run_cluster as cluster after upstream after integrative { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.cluster_cpu,
            memory_gb = estimate_downstream_resources.resources.cluster_memory_gb,
            future_globals_gib = estimate_downstream_resources.resources.cluster_future_globals_gib,
        }
    }

    if (run_contamination_removal) {
        call optional.run_contamination_removal as contamination_removal after cluster { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.contamination_cpu,
            memory_gb = estimate_downstream_resources.resources.contamination_memory_gb,
            future_globals_gib = estimate_downstream_resources.resources.contamination_future_globals_gib,
        }
    }

    if (run_cell_types) {
        call required.run_cell_types as cell_types after cluster after contamination_removal { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.cell_types_cpu,
            memory_gb = estimate_downstream_resources.resources.cell_types_memory_gb,
        }
    }

    if (run_rshiny) {
        call required.run_rshiny as rshiny after cell_types { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.rshiny_cpu,
            memory_gb = estimate_downstream_resources.resources.rshiny_memory_gb,
        }
    }

    if (run_clone_phylogeny) {
        call optional.run_clone_phylogeny as clone_phylogeny after cell_types { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.clone_phylogeny_cpu,
            memory_gb = estimate_downstream_resources.resources.clone_phylogeny_memory_gb,
        }
    }

    if (run_de_go) {
        call optional.run_de_go as de_go after cell_types { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.de_go_cpu,
            memory_gb = estimate_downstream_resources.resources.de_go_memory_gb,
            future_globals_gib = estimate_downstream_resources.resources.de_go_future_globals_gib,
        }
    }

    if (run_project_updates) {
        call required.run_project_updates as project_updates after upstream after integrative
            after cluster after contamination_removal after cell_types after rshiny { input:
            daedalus_root = project_root,
            container_image = downstream_container,
            notify_email = notify_email,
            cpu = estimate_downstream_resources.resources.project_updates_cpu,
            memory_gb = estimate_downstream_resources.resources.project_updates_memory_gb,
        }
    }

    # Primary artifact directories (informational workflow outputs only; not used for task wiring).
    output {
        Array[CellRangerOutput] cellranger_outputs = cellranger_output
        File cellranger_summary = write_cellranger_summary.summary
        Array[Int] estimated_cells = sample_estimated_cells
        Int num_samples = length(cellranger_inputs)
        DownstreamResources downstream_resources = estimate_downstream_resources.resources
        Int upstream_cpu = estimate_downstream_resources.resources.upstream_cpu
        Int upstream_memory_gb = estimate_downstream_resources.resources.upstream_memory_gb
        Int upstream_future_globals_gib = estimate_downstream_resources.resources.upstream_future_globals_gib
        Int integrative_cpu = estimate_downstream_resources.resources.integrative_cpu
        Int integrative_memory_gb = estimate_downstream_resources.resources.integrative_memory_gb
        Int integrative_future_globals_gib = estimate_downstream_resources.resources.integrative_future_globals_gib
        File? upstream_completion = upstream.done_flag
        String? upstream_results = if run_upstream
            then project_root + "/analyses/upstream-analysis/results"
            else None
        File? cluster_completion = cluster.done_flag
        String? cluster_results = if run_cluster
            then project_root + "/analyses/cluster-cell-calling/results"
            else None
        File? cell_types_completion = cell_types.done_flag
        String? cell_types_results = if run_cell_types
            then project_root + "/analyses/cell-types-annotation/results"
            else None
        File? rshiny_completion = rshiny.done_flag
        String? rshiny_results = if run_rshiny
            then project_root + "/analyses/rshiny-app/results"
            else None
        File? integrative_completion = integrative.done_flag
        String? integrative_results = if run_integrative
            then project_root + "/analyses/integrative-analysis/results"
            else None
        File? contamination_removal_completion = contamination_removal.done_flag
        String? contamination_removal_results = if run_contamination_removal
            then project_root + "/analyses/cell-contamination-removal-analysis/results"
            else None
        File? clone_phylogeny_completion = clone_phylogeny.done_flag
        String? clone_phylogeny_results = if run_clone_phylogeny
            then project_root + "/analyses/clone-phylogeny-analysis/results"
            else None
        File? de_go_completion = de_go.done_flag
        String? de_go_results = if run_de_go
            then project_root + "/analyses/de-go-analysis/results"
            else None
        File? project_updates_completion = project_updates.done_flag
        String? project_updates_results = if run_project_updates
            then project_root + "/analyses/project-updates/reports"
            else None
    }
}
