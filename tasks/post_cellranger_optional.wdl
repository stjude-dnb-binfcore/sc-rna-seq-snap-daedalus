version 1.3

# Assumes FastQC and Cell Ranger have already completed.
#
# Container execution is handled by Sprocket (lsf_apptainer backend) via
# requirements.container — do not call singularity/apptainer in command blocks.
# Per-module email: LSF bsub -B/-N/-u CONTACT_EMAIL (inputs/sprocket.generated.toml).
# Workflow email: scripts/daedalus-notify-email.sh from launch-daedalus-sprocket.sh.
task run_integrative {
    meta {
        description: "Integrative analysis module"
        outputs: {
            done_flag: "Present when `run-integrative-analysis.sh` completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`."
        container_image: "Apptainer image URI for the downstream R analysis container."
        notify_email: "Email address for LSF begin/end notifications."
        cpu: {
            description: "LSF CPU cores for integrative analysis.",
            group: "Resource"
        }
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource"
        }
        future_globals_gib: {
            description: "R `future.globals.maxSize` limit in gibibytes.",
            group: "Resource"
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 10
        Int memory_gb = 96
        Int future_globals_gib = 200
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: integrative  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        export FUTURE_GLOBALS_MAXSIZE_GIB="~{future_globals_gib}"
        cd "~{daedalus_root}/analyses/integrative-analysis"
        bash run-integrative-analysis.sh
        echo "done" > "${TASK_DIR}/integrative.done"
    >>>

    output {
        File done_flag = "integrative.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB"
        container: container_image
    }
}

task run_contamination_removal {
    meta {
        description: "Cell contamination removal module"
        outputs: {
            done_flag: "Present when contamination-removal analysis completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`."
        container_image: "Apptainer image URI for the downstream R analysis container."
        notify_email: "Email address for LSF begin/end notifications."
        cpu: {
            description: "LSF CPU cores for contamination removal.",
            group: "Resource"
        }
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource"
        }
        future_globals_gib: {
            description: "R `future.globals.maxSize` limit in gibibytes.",
            group: "Resource"
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 8
        Int memory_gb = 96
        Int future_globals_gib = 400
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: contamination_removal  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        export FUTURE_GLOBALS_MAXSIZE_GIB="~{future_globals_gib}"
        cd "~{daedalus_root}/analyses/cell-contamination-removal-analysis"
        bash run-cell-contamination-removal-analysis.sh
        echo "done" > "${TASK_DIR}/contamination.done"
    >>>

    output {
        File done_flag = "contamination.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB"
        container: container_image
    }
}

task run_clone_phylogeny {
    meta {
        description: "Clone phylogeny analysis module"
        outputs: {
            done_flag: "Present when `run-clone-phylogeny-analysis.sh` completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`."
        container_image: "Apptainer image URI for the downstream R analysis container."
        notify_email: "Email address for LSF begin/end notifications."
        cpu: {
            description: "LSF CPU cores for clone phylogeny analysis.",
            group: "Resource"
        }
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource"
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 16
        Int memory_gb = 30
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: clone_phylogeny  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        cd "~{daedalus_root}/analyses/clone-phylogeny-analysis"
        bash run-clone-phylogeny-analysis.sh
        echo "done" > "${TASK_DIR}/clone_phylogeny.done"
    >>>

    output {
        File done_flag = "clone_phylogeny.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB"
        container: container_image
    }
}

task run_de_go {
    meta {
        description: "DE and GO analysis module"
        outputs: {
            done_flag: "Present when `run-de-go-analysis.sh` completes successfully."
        }
    }

    parameter_meta {
        daedalus_root: "Daedalus project root containing `analyses/` and `inputs/`."
        container_image: "Apptainer image URI for the downstream R analysis container."
        notify_email: "Email address for LSF begin/end notifications."
        cpu: {
            description: "LSF CPU cores for differential expression and GO analysis.",
            group: "Resource"
        }
        memory_gb: {
            description: "LSF memory request in gigabytes.",
            group: "Resource"
        }
        future_globals_gib: {
            description: "R `future.globals.maxSize` limit in gibibytes.",
            group: "Resource"
        }
    }

    input {
        String daedalus_root
        String container_image
        String notify_email
        Int cpu = 4
        Int memory_gb = 32
        Int future_globals_gib = 200
    }

    command <<<
        set -euo pipefail
        TASK_DIR="$(pwd)"
        echo "Module: de_go  LSF mail: ~{notify_email}"
        export DAEDALUS_CONFIG_FILE="~{daedalus_root}/inputs/project_parameters.generated.yaml"
        export FUTURE_GLOBALS_MAXSIZE_GIB="~{future_globals_gib}"
        cd "~{daedalus_root}/analyses/de-go-analysis"
        bash run-de-go-analysis.sh
        echo "done" > "${TASK_DIR}/de_go.done"
    >>>

    output {
        File done_flag = "de_go.done"
    }

    requirements {
        cpu: cpu
        memory: "~{memory_gb} GB"
        container: container_image
    }
}
