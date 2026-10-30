version 1.3

# Assumes FastQC and Cell Ranger have already completed.
#
# Container execution is handled by Sprocket (lsf_apptainer backend) via
# requirements.container — do not call singularity/apptainer in command blocks.
# Per-module email: LSF bsub -B/-N/-u CONTACT_EMAIL (inputs/sprocket.generated.toml).
# Workflow email: scripts/daedalus-notify-email.sh from launch-daedalus-sprocket.sh.
task run_upstream {
    meta {
        description: "Upstream Seurat QC module",
        outputs: {
            done_flag: "Present when `run-upstream-analysis.sh` completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`.",
        container_image: "Apptainer image URI for the downstream R analysis container.",
        notify_email: "Email address for LSF begin/end notifications.",
        cpu: {
            description: "LSF CPU cores for upstream analysis.",
            group: "Resource",
        },
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource",
        },
        future_globals_gib: {
            description: "R `future.globals.maxSize` limit in gibibytes.",
            group: "Resource",
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 16
        Int memory_gb = 30
        Int future_globals_gib = 200
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: upstream  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        export FUTURE_GLOBALS_MAXSIZE_GIB="~{future_globals_gib}"
        cd "~{daedalus_root}/analyses/upstream-analysis"
        bash run-upstream-analysis.sh
        echo "done" > "${TASK_DIR}/upstream.done"
    >>>

    output {
        File done_flag = "upstream.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB",
        container: container_image
    }
}

task run_cluster {
    meta {
        description: "Cluster cell calling module",
        outputs: {
            done_flag: "Present when `run-cluster-cell-calling.sh` completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`.",
        container_image: "Apptainer image URI for the downstream R analysis container.",
        notify_email: "Email address for LSF begin/end notifications.",
        cpu: {
            description: "LSF CPU cores for cluster cell calling.",
            group: "Resource",
        },
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource",
        },
        future_globals_gib: {
            description: "R `future.globals.maxSize` limit in gibibytes.",
            group: "Resource",
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 4
        Int memory_gb = 48
        Int future_globals_gib = 400
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: cluster  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        export FUTURE_GLOBALS_MAXSIZE_GIB="~{future_globals_gib}"
        cd "~{daedalus_root}/analyses/cluster-cell-calling"
        bash run-cluster-cell-calling.sh
        echo "done" > "${TASK_DIR}/cluster.done"
    >>>

    output {
        File done_flag = "cluster.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB",
        container: container_image
    }
}

task run_cell_types {
    meta {
        description: "Cell types annotation module",
        outputs: {
            done_flag: "Present when `run-cell-types-annotation.sh` completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`.",
        container_image: "Apptainer image URI for the downstream R analysis container.",
        notify_email: "Email address for LSF begin/end notifications.",
        cpu: {
            description: "LSF CPU cores for cell-type annotation.",
            group: "Resource",
        },
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource",
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 4
        Int memory_gb = 64
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: cell_types  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        cd "~{daedalus_root}/analyses/cell-types-annotation"
        bash run-cell-types-annotation.sh
        echo "done" > "${TASK_DIR}/cell_types.done"
    >>>

    output {
        File done_flag = "cell_types.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB",
        container: container_image
    }
}

task run_project_updates {
    meta {
        description: "Project report and cross-module summary module",
        outputs: {
            done_flag: "Present when `run-project-updates.sh` completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`.",
        container_image: "Apptainer image URI for the downstream R analysis container.",
        notify_email: "Email address for LSF begin/end notifications.",
        cpu: {
            description: "LSF CPU cores for project report generation.",
            group: "Resource",
        },
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource",
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 1
        Int memory_gb = 4
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: project_updates  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        cd "~{daedalus_root}/analyses/project-updates"
        bash run-project-updates.sh
        echo "done" > "${TASK_DIR}/project_updates.done"
    >>>

    output {
        File done_flag = "project_updates.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB",
        container: container_image
    }
}

task run_rshiny {
    meta {
        description: "R Shiny app packaging module",
        outputs: {
            done_flag: "Present when `run-rshiny-app.sh` completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`.",
        container_image: "Apptainer image URI for the downstream R analysis container.",
        notify_email: "Email address for LSF begin/end notifications.",
        cpu: {
            description: "LSF CPU cores for R Shiny app packaging.",
            group: "Resource",
        },
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource",
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 4
        Int memory_gb = 30
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: rshiny  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        cd "~{daedalus_root}/analyses/rshiny-app"
        bash run-rshiny-app.sh
        echo "done" > "${TASK_DIR}/rshiny.done"
    >>>

    output {
        File done_flag = "rshiny.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB",
        container: container_image
    }
}
