# Daedalus downstream launcher

`launch-daedalus-downstream.sh` runs enabled downstream analyses from completed
Cell Ranger outputs. It submits jobs through **Sprocket** using the **static**
workflow at `workflows/daedalus_from_cellranger.wdl` (the fixed WDL in this
repository—not regenerated on each launch).

**Which modules run** is controlled separately: set `run_*` toggles under
`workflow_profile` in `project_parameters.Config.yaml`. Each launch copies
those toggles into `inputs/sprocket_inputs.json` and writes scaled resources to
`inputs/project_parameters.generated.yaml`; see
[What the launcher does](#what-the-launcher-does) and
[Files you edit manually](#files-you-edit-manually).

## Prerequisites

Before launching downstream:

1. **Cell Ranger** is complete under `analyses/cellranger-analysis/results/02_cellranger_count/<parameters>/<sample>/outs`, **or** set `workflow_profile.run_cellranger: true` so `--submit` runs alignment first (static LSF scripts; not resource-scaled).
2. **Sample metadata** exists at `data/project_metadata/project_metadata.tsv`.
3. Metadata `ID` values exactly match the Cell Ranger sample directory names.
4. **Apptainer/Singularity image** is configured at `resource_profile.container_image` in `project_parameters.Config.yaml` (default: `<root_dir>/rstudio_4.4.0_seurat_4.4.0_latest.sif`).
5. You are on a St. Jude HPC node with **Sprocket**, **R**, and **Apptainer/Singularity** available. Please note that a version of Singularity is installed by default on all the cluster nodes at St Jude HPC. Otherwise the user needs to ensure and load Singularity module.

## Load modules

```bash
module load sprocket R
```

## Dry run — validate files and refresh inputs

Run from the **project root** (parent of this `scripts/` folder). With no flags,
the launcher refreshes generated YAML/inputs, checks the static WDL, and
validates Sprocket inputs—it does **not** submit LSF jobs.

If `workflow_profile.run_cellranger: true` and alignments are **not** on disk yet,
dry-run still plans downstream resources from metadata (baseline cells/sample) and
**skips** `sprocket validate` until outputs exist. Use `--submit` to run Cell Ranger,
wait on the LSF waiter, then estimate and launch Sprocket automatically.

```bash
bash launch-daedalus-downstream.sh
```

To submit after a successful dry run, add `--submit` (see
[Safe ways to launch downstream analysis](#safe-ways-to-launch-downstream-analysis)).

---

## Safe ways to launch downstream analysis

### Option 1 — nohup in the background (recommended)

```bash
nohup bash launch-daedalus-downstream.sh --submit > daedalus-launch.log 2>&1 &
echo $!   # note the PID
```

Monitor progress:

```bash
tail -f daedalus-launch.log
```

or

```bash
tail -f out/runs/daedalus_from_cellranger/_latest/calls/upstream/attempts/0/stderr
```

Every submission disables Sprocket call caching because shared directories are
passed as `String` paths, so changes to their contents are not represented in
the cache key.

### Option 2 — tmux or screen

```bash
tmux new -s daedalus
module load sprocket R singularity
bash launch-daedalus-downstream.sh

bash launch-daedalus-downstream.sh --submit
# Detach: Ctrl+b then d
# Reattach later: tmux attach -t daedalus
```

---

## Module dependencies

The WDL uses `after` clauses to enforce module order (see
`workflows/MODULE_DEPENDENCIES.md` for the full diagram including FastQC,
Cell Ranger, and **project-updates**).

```text
summary → upstream → integrative (opt) → cluster → contamination (opt)
       → cell_types → rshiny → project_updates (opt)
       cell_types ─┬→ clone (opt)   } parallel; nothing downstream waits on these
                   └→ de_go (opt)   }
```

When a data-producing prerequisite is disabled, its expected result files must
already exist on disk.

For **standard project runs**, choose modules with `workflow_profile` in
`project_parameters.Config.yaml`; editing WDL is not required. Changing workflow
structure (dependencies, LSF tasks, or adding optional modules) is
**maintainer-level** and typically done only if you are developing the pipeline itself.
Those definitions live in `workflows/daedalus_from_cellranger.wdl` and
`tasks/post_cellranger_required.wdl` / `tasks/post_cellranger_optional.wdl`
(details in `workflows/MODULE_DEPENDENCIES.md`).

---

## What the launcher does

Each run performs these steps in order:

| Step | Script or command | Output |
|------|-------------------|--------|
| 1. Estimate resources | `scripts/estimate-daedalus-downstream-resources.R` | `<root_dir>/inputs/project_parameters.generated.yaml`, `inputs/generated_downstream.json`, `inputs/sprocket_inputs.json` |
| 2. Render Sprocket config | `scripts/render-sprocket-config.sh` | `inputs/sprocket.generated.toml` |
| 3. Check WDL | `sprocket check workflows/daedalus_from_cellranger.wdl` | — |
| 4. Validate inputs | `sprocket validate workflows/daedalus_from_cellranger.wdl @inputs/sprocket_inputs.json --config inputs/sprocket.generated.toml` | — |
| 5. Submit (if not dry-run) | `sprocket run ... --output-dir out --no-call-cache` | LSF jobs |
| 6. Collect resource usage (after `--submit` only) | `scripts/collect-resource-usage.sh --daedalus-root . --latest --json` | `out/resource_usage/` |

The resource estimator:

- Counts samples from `project_metadata.tsv` (or Cell Ranger output directories).
- Reads **Cell Ranger** `metrics_summary.csv` for cells per sample.
- Computes tiered CPU, memory, and `future_globals_*` for the pre-launch snapshot and generated YAML (baseline: 8 samples × 50k cells). **WDL/Sprocket LSF requests** are set at workflow runtime by `estimate_downstream_resources` (see below).
- Adds **20% LSF memory headroom** to every module’s `*_memory_gb` value (via `apply_lsf_memory_headroom()` in `estimate-daedalus-downstream-resources.R`) so jobs are not killed when usage spikes slightly above the base estimate. Example: upstream base **30 GB** → **36 GB** requested on LSF (`ceiling(30 × 1.2)`).
- Copies **workflow module toggles** from `workflow_profile` in your master YAML into Sprocket inputs.

### Resource estimation: R script vs WDL

Resource sizing is computed in **two places** with the same tiering rules (8 samples × 50k cells baseline, 20% memory headroom). They serve different roles:

| When | Where | Outputs | Used for |
|------|--------|---------|----------|
| **Before** `sprocket run` | `scripts/estimate-daedalus-downstream-resources.R` | `inputs/generated_downstream.json` (`resource_estimate` snapshot), `inputs/project_parameters.generated.yaml`, `inputs/sprocket_inputs.json` | Pre-flight logs, config overlay for R modules (`DAEDALUS_CONFIG_FILE`), Sprocket validate inputs. **`sprocket_inputs.json` does not include per-module CPU/memory.** |
| **During** the workflow | WDL task `estimate_downstream_resources` in `tasks/pre_cellranger.wdl` (called from `workflows/daedalus_from_cellranger.wdl` after per-sample metrics are parsed) | JSON consumed inside the workflow | **LSF requests** for each downstream module (`requirements.cpu` / `memory`) and `FUTURE_GLOBALS_MAXSIZE_GIB` passed into module commands. |

**If the two estimates ever disagree**, the **WDL task** values govern what Sprocket submits for WDL/Sprocket runs. The pre-launch JSON is a snapshot for visibility and resource-usage reporting, not the submission source of truth.

Under normal conditions both paths read the same Cell Ranger metrics and should match. They can diverge if metrics or inputs change between the pre-launch R step and the workflow run, or if the duplicated formulas in R and WDL are updated out of sync.

**Interactive / per-module runs** (no Sprocket workflow) do not run `estimate_downstream_resources`; use `project_parameters.Config.yaml` and the generated overlay from the R script only.

Editing **`compute_resources()`** in `estimate-daedalus-downstream-resources.R` updates the pre-launch JSON/YAML and helps **interactive** runs. It does **not** change LSF memory for **WDL/Sprocket** submissions unless you make the same change in the inline R inside **`estimate_downstream_resources`** in `tasks/pre_cellranger.wdl` (keep the two copies in sync).

At runtime, downstream R modules load config via `scripts/daedalus_read_config.R` (see [YAML config: which file is used?](#yaml-config-which-file-is-used) below).

---

## YAML config: which file is used?

The pipeline supports **three ways to run** downstream modules. The config file is chosen automatically — you do not pick it in the YAML itself.

| How you launch | Launcher | Config file used |
|----------------|----------|------------------|
| **WDL / Sprocket** | `bash launch-daedalus-downstream.sh --submit` or `bash scripts/launch-daedalus-sprocket.sh` | `<root_dir>/inputs/project_parameters.generated.yaml` |
| **Full LSF chain** | `bash launch_full_pipeline.sh` | `project_parameters.Config.yaml` |
| **Interactive / per-module LSF** | Run `analyses/<module>/run-*.sh` or `Rscript run-*.R` directly | `project_parameters.Config.yaml` |

### How it works

- **WDL/Sprocket** sets `DAEDALUS_CONFIG_FILE` in `tasks/post_cellranger_required.wdl` and `tasks/post_cellranger_optional.wdl` to the generated overlay. Module scripts detect this and load the generated YAML (scaled resources + paths refreshed at launch).
- **All other run modes** do not set `DAEDALUS_CONFIG_FILE`, so modules load the master template `project_parameters.Config.yaml`.
- **FastQC and Cell Ranger** are outside the WDL graph but can be turned on with `workflow_profile.run_fastqc` / `run_cellranger`. They use static LSF scripts (`analyses/fastqc-analysis/lsf-script.txt`, `analyses/cellranger-analysis/submit-multiple-jobs.sh`) and read `project_parameters.Config.yaml` directly (not the generated overlay). Cell Ranger can still be run **standalone** with `cd analyses/cellranger-analysis && bsub < submit-multiple-jobs.sh` — no daedalus launcher required.

### Helpers (R and bash)

| File | Use |
|------|-----|
| `scripts/daedalus_read_config.R` | `daedalus_load_project_config()`, `daedalus_read_master_config()`, `daedalus_is_wdl_run()` |
| `scripts/daedalus-read-config.sh` | `daedalus_yaml_get`, `daedalus_yaml_list`, `daedalus_log_config_file` |

**R module entry scripts** (upstream onwards) use:

```r
daedalus_root <- normalizePath("../..", winslash = "/")
source(file.path(daedalus_root, "scripts", "daedalus_read_config.R"))
yaml <- daedalus_load_project_config(daedalus_root)   # prints: Using config: <path>
```

**Bash module scripts** (e.g. clone-phylogeny) use:

```bash
DAEDALUS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${DAEDALUS_ROOT}/scripts/daedalus-read-config.sh"
daedalus_log_config_file
root_dir="$(daedalus_yaml_get root_dir)"
```

### Manual override

To force a specific YAML (e.g. test the generated overlay outside Sprocket):

```bash
export DAEDALUS_CONFIG_FILE=/path/to/project/inputs/project_parameters.generated.yaml
Rscript analyses/upstream-analysis/run-upstream-analysis.R
```

### What to edit

| File | Edit by hand? |
|------|----------------|
| `project_parameters.Config.yaml` | **Yes** — biology, paths, `workflow_profile`, emails (master template for Sprocket and direct/interactive runs) |
| `<root_dir>/inputs/project_parameters.generated.yaml` | **No** — regenerated by `estimate-daedalus-downstream-resources.R` on each Sprocket launch |

---

## Files you edit manually

### 1. `project_parameters.Config.yaml` (master template — **edit this**)

This is your main configuration file. The launcher **does not overwrite** it by default; it writes a generated overlay instead.

**Always review/update before launch:**

| Section | What to set |
|---------|-------------|
| Project paths | `root_dir`, `data_dir`, `metadata_dir` — use absolute paths for your project (estimator resolves these on each run). |
| `workflow_profile` | Turn modules on/off (`run_fastqc`, `run_cellranger`, `run_upstream`, `run_integrative`, `run_cluster`, etc.). Preprocessing toggles do not change estimator output. |
| `resource_profile.container_image` | Full path to the Seurat Apptainer `.sif` if not at `<root_dir>/rstudio_4.4.0_seurat_4.4.0_latest.sif`. |
| Biology / QC | Upstream filters (`min_genes`, `min_count`, `condition_value*`), integration method, clustering resolution, annotation method, etc. |
| Module-specific | Sections for integrative, cluster, contamination, cell-types, clone-phylogeny, de-go, rshiny — see inline comments in the YAML. |

**Example — align + upstream (FastQC and Cell Ranger in parallel, then Sprocket):**

```yaml
workflow_profile:
  run_fastqc: true
  run_cellranger: true
  run_upstream: true
  run_integrative: false
  run_cluster: false
  run_contamination_removal: false
  run_cell_types: false
  run_clone_phylogeny: false
  run_de_go: false
  run_rshiny: false
  run_project_updates: false
```

**Example — upstream only (Cell Ranger already complete):**

```yaml
workflow_profile:
  run_fastqc: false
  run_cellranger: false
  run_upstream: true
  run_integrative: false
  run_cluster: false
  run_contamination_removal: false
  run_cell_types: false
  run_clone_phylogeny: false
  run_de_go: false
  run_rshiny: false
  run_project_updates: false
```

**Example — enable more modules later:**

Set the relevant `run_*` keys to `true`, then re-run `bash launch-daedalus-downstream.sh --submit`.

Optional resource overrides (usually leave as `null` so Cell Ranger metrics drive scaling):

```yaml
resource_profile:
  num_samples: null                  # null = auto-count
  estimated_cells_per_sample: null   # null = mean from Cell Ranger
  resource_tier: "default"
  container_image: "/full/path/to/rstudio_4.4.0_seurat_4.4.0_latest.sif"
```

### 2. `data/project_metadata/project_metadata.tsv`

Define samples, FASTQ paths, and optional metadata columns (`condition`, etc.). Required columns: `ID`, `SAMPLE`, `FASTQ`.

### 3. `sprocket.toml` (optional)

Default LSF backend settings (queue, concurrency, job prefix). Usually fine as-is. Edit if you need a different queue or concurrency limits. The launcher copies these settings to `inputs/sprocket.generated.toml`; do not edit the generated copy. The **container image** is passed per-task from YAML/workflow inputs, not from `sprocket.toml`.

### 4. Supporting data files (when those modules are enabled)

Examples:

- Gene markers / palettes under `data/` and `.figures/palettes/`
- Reference `.rds` for cell-type annotation
- Clone-phylogeny sample list in YAML

---

## Files you should not edit

These are regenerated on each launch:

| File | Reason |
|------|--------|
| `<root_dir>/inputs/project_parameters.generated.yaml` | Runtime config overlay (master + scaled resources) |
| `inputs/generated_downstream.json` | Resource estimate snapshot |
| `inputs/sprocket_inputs.json` | Flat inputs for `sprocket validate` / `sprocket run` |
| `inputs/sprocket.generated.toml` | Runtime Sprocket configuration |

---

## Scripts in this folder

| Script | Purpose |
|--------|---------|
| `launch-daedalus-sprocket.sh` | Main orchestrator (estimate → render config → check → validate → run → resource report) |
| `estimate-daedalus-downstream-resources.R` | Cell Ranger metrics → LSF resources + YAML/JSON |
| `render-sprocket-config.sh` | Writes `inputs/sprocket.generated.toml` for launch |
| `monitor-daedalus-task-emails.sh` | Background per-module start/complete emails while Sprocket runs |
| `daedalus-notify-email.sh` | Sends workflow/module email notifications (login node) |
| `daedalus_read_config.R` | Helper used by R modules to load YAML config |
| `daedalus-read-config.sh` | Bash helper for shell scripts (same config precedence as `daedalus_read_config.R`) |
| `collect-resource-usage.sh` | Post-run LSF resource report (requested vs actual per module) |
| `extract-resource-usage.sh` | Convenience wrapper: `--latest --json` into `out/resource_usage/` |
| `test-downstream-layout.sh` | Sanity-check that expected WDL/inputs files exist |

Root launcher (one level up): `launch-daedalus-downstream.sh`

---

## Resource usage (requested vs actual)

After each Sprocket run, the launcher calls `scripts/collect-resource-usage.sh` to compare **requested** LSF resources (from task `inputs.json`) with **actual** usage from LSF (`bjobs`).

Reports are written to:

```text
out/resource_usage/resource_usage_<run_id>.csv
out/resource_usage/resource_usage_<run_id>.json
```

Key columns: `requested_cpu`, `requested_memory_gb`, `actual_max_memory_gb`, `memory_utilization_pct`, `cpu_time_sec`, `wall_time_sec`, `cpu_avg_efficiency_pct`.

**Run manually** (e.g. after an older run):

```bash
# Latest Sprocket run (writes out/resource_usage/resource_usage_<run_id>.{csv,json})
bash scripts/extract-resource-usage.sh

# Copy reports elsewhere (e.g. ROI analysis input/)
bash scripts/extract-resource-usage.sh --export-dir /path/to/destination

# Specific run / workflow folder
bash scripts/collect-resource-usage.sh --daedalus-root . --workflow daedalus_from_cellranger --run-id 2026-08-31_234355266651904 --json
```

**Requested resources only** (pre-run estimates from the R script, not LSF-observed usage; for WDL runs, LSF requests come from the workflow task at runtime):

| File | Contents |
|------|----------|
| `inputs/generated_downstream.json` | `resource_estimate` snapshot (per-module CPU/memory/`future_globals_*`) plus embedded copy of Sprocket inputs |
| `inputs/sprocket_inputs.json` | Paths, toggles, and containers for `sprocket validate` / `sprocket run` — **no per-module CPU/memory** |

---

## Downstream modules

| Module | YAML toggle | WDL task |
|--------|-------------|----------|
| Upstream QC / Seurat | `run_upstream` | `run_upstream` |
| Integrative (Harmony, etc.) | `run_integrative` | `run_integrative` |
| Cluster / markers | `run_cluster` | `run_cluster` |
| Contamination removal | `run_contamination_removal` | `run_contamination_removal` |
| Cell-type annotation | `run_cell_types` | `run_cell_types` |
| Clone phylogeny | `run_clone_phylogeny` | `run_clone_phylogeny` |
| DE / GO | `run_de_go` | `run_de_go` |
| R Shiny app | `run_rshiny` | `run_rshiny` |
| Project report / summary | `run_project_updates` | `run_project_updates` |

Enabled modules run in dependency order; skipped modules do not block later steps.

After a Sprocket run, workflow outputs include `*_results` paths pointing at each module’s primary artifact folder (usually `analyses/<module>/results`; project updates HTML under `analyses/project-updates/reports`). These strings are informational only—tasks always use `project_root` as `daedalus_root`.

---

## Email notifications

Notifications go to **`CONTACT_EMAIL`** in `project_parameters.Config.yaml` (passed as `notify_email` in Sprocket inputs).

| When | How |
|------|-----|
| Pipeline `--submit` started | `launch-daedalus-sprocket.sh` → `daedalus-notify-email.sh` (immediate) |
| FastQC / Cell Ranger submitted | `daedalus-notify-email.sh` on submit; LSF `-N` to `CONTACT_EMAIL` when the job ends (optional `-B` via `DAEDALUS_LSF_NOTIFY_ON_START=1`) |
| Cell Ranger chain finished (before Sprocket) | Launch script after `bwait` on waiter job |
| Sprocket downstream submitted | Launch script just before `sprocket run` |
| Each downstream module started | `monitor-daedalus-task-emails.sh` when LSF `job_id` appears for that module |
| Each downstream module completed / failed | Monitor when LSF job reaches `DONE` / `EXIT` |
| Sprocket run finished / failed | Launch script after `sprocket run` exits (subject: `[daedalus] workflow: completed`) |
| Missed module complete (catch-up) | `bash scripts/monitor-daedalus-task-emails.sh --daedalus-root . --to CONTACT_EMAIL --finalize-only` |

Module emails use **`CONTACT_EMAIL`** from `project_parameters.Config.yaml`. The monitor runs in the background while Sprocket executes and polls `out/runs/daedalus_from_cellranger/_latest/calls/`.

To change the recipient, edit `CONTACT_EMAIL` in the master YAML and re-run the launcher.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `sprocket not found` | `module load sprocket` on an HPC node |
| `singularity: command not found` inside task | Load singularity before launch: `module load singularity`. Tasks must not call `singularity exec` manually — Sprocket wraps commands via `runtime.container`. |
| Missing Cell Ranger metrics | Complete Cell Ranger or run `Rscript scripts/estimate-daedalus-downstream-resources.R --daedalus-root . --output inputs/generated_downstream.json --estimated-cells-per-sample <count>` |
| Container pull fails / `repository name must be lowercase` | Local `.sif` paths must use the `file://` scheme for Sprocket (auto-added in `sprocket_inputs.json`). Keep plain paths in YAML; re-run the launcher to regenerate inputs. |
| Wrong modules running | Edit `workflow_profile` in `project_parameters.Config.yaml`, then re-launch |
| LSF job killed at memory limit (`TERM_MEMLIMIT`) | See [LSF memory limit (`TERM_MEMLIMIT`)](#lsf-memory-limit-term_memlimit) below |

### LSF memory limit (`TERM_MEMLIMIT`)

LSF killed the job because **resident memory exceeded the requested limit** for that Sprocket task.

**20% headroom is already included** in both estimators (R: `apply_lsf_memory_headroom()` / `LSF_MEMORY_HEADROOM`; WDL: `* 1.2` on each `*_memory_gb` in `estimate_downstream_resources`). **Re-launching with no other changes does not add more headroom**—it only refreshes inputs and re-runs the same formulas. Re-launch *can* raise the tier if Cell Ranger metrics were missing before (so `cell_scale` was too low) or sample/cell counts changed.

**WDL / Sprocket runs:** LSF **CPU and memory requests** come from the workflow task `estimate_downstream_resources`, not from `sprocket_inputs.json` or `generated_downstream.json`. To request more memory:

1. Identify the failing module (upstream, integrative, cluster, etc.) from LSF/Sprocket logs.
2. Raise that module’s **base GB** (before the ×1.2 factor) in **`tasks/pre_cellranger.wdl`**, inside the inline R in task `estimate_downstream_resources`—for example `upstream_memory_gb = ... (30L + 10L * (cell_scale - 1L)) * 1.2` → increase `30L` (and the per-`cell_scale` increment if needed).
3. Mirror the same base values in **`compute_resources()`** in `scripts/estimate-daedalus-downstream-resources.R` so pre-launch estimates and `project_parameters.generated.yaml` stay aligned with what the workflow will request.

| Module | Field to adjust | Default base GB (before ×1.2 headroom) |
|--------|-----------------|----------------------------------------|
| Upstream | `upstream_memory_gb` | `30 + 10 × (cell_scale − 1)` |
| Integrative | `integrative_memory_gb` | `96 + 24 × (cell_scale − 1)` |
| Cluster | `cluster_memory_gb` | `48 + 16 × (cell_scale − 1)` |
| Contamination | `contamination_memory_gb` | `96 + 24 × (cell_scale − 1)` |
| Cell types | `cell_types_memory_gb` | `64 + 16 × (cell_scale − 1)` |
| Clone phylogeny | `clone_phylogeny_memory_gb` | fixed `30` |
| DE / GO | `de_go_memory_gb` | `32 + 8 × (cell_scale − 1)` |
| R Shiny | `rshiny_memory_gb` | fixed `30` |
| Project updates | `project_updates_memory_gb` | fixed `4` |

To increase headroom globally, change **`LSF_MEMORY_HEADROOM`** in the R script and the **`1.2`** multiplier in the WDL task (both places).

Compare requested vs observed usage after a run: `bash scripts/collect-resource-usage.sh --daedalus-root . --latest --json`. If the failure is R **`future`** global limits rather than LSF RSS, adjust the matching `*_future_globals_gib` fields in the same two locations.

**Interactive / per-module LSF** (no WDL): editing **`compute_resources()`** (or re-running the estimator with `--update-yaml`) is the supported path; optional fallback is reducing parallel workers inside that module’s R code.

Monitor LSF jobs after submit:

```bash
bjobs -u $USER
```

---

## Legacy path (not recommended)

`launch_full_pipeline.sh` uses static LSF bash scripts under `analyses/*/lsf-script.txt` and reads **`project_parameters.Config.yaml`** only (not the generated overlay). FastQC and Cell Ranger also read the master YAML directly. For dynamic scaling and optional modules via WDL, use **`launch-daedalus-downstream.sh`** instead.
