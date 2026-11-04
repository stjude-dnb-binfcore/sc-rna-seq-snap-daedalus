# Biological output validation

After a successful **Daedalus downstream** Sprocket run, the launcher can run
`scripts/daedalus_validate_outputs.R` when `workflow_profile.run_biological_validation`
is `true` (default).

When enabled, `launch-daedalus-sprocket.sh` emails **`CONTACT_EMAIL`** on validation
start, pass (`[daedalus] biological validation: completed`), or failure. The downstream
“completed” email is skipped if validation fails (Sprocket still succeeded).

## What it checks

| Check | When | Purpose |
|-------|------|---------|
| Metadata vs Cell Ranger | Always (if validation enabled) | `project_metadata.tsv` `ID` values match sample dirs under `data_dir` |
| Cell Ranger cell counts | Always | Non-zero estimated cells per sample |
| Upstream deliverable | `run_upstream` | `seurat_obj_merged_filtered.rds` exists; filtered cell count vs Cell Ranger totals |
| Integrative deliverable | `run_integrative` | `seurat_obj_integrated_<integration_method>.rds` exists; ncol vs upstream |
| Cluster deliverable | `run_cluster` | `seurat_obj_clusters_all.rds` under `01_cluster_cell_calling_<resolution_clustering_module>/`; cluster count at **`resolution_list_find_markers`** (metadata column); **warning if fewer than 2 clusters** |
| Cell types deliverable | `run_cell_types` | Seurat RDS at `cell-types-annotation/results/<annotations_dir_rshiny_app>/<annotations_filename_rshiny_app>` (same keys as the R Shiny app) |

Warnings (e.g. aggressive filtering) do not fail the run unless you pass `--strict`.

## Manual run

```bash
module load R   # or apptainer on your cluster
cd ./sc-rna-seq-snap-daedalus

bash scripts/daedalus-apptainer-rscript.sh --daedalus-root . -- \
  scripts/daedalus_validate_outputs.R \
  --daedalus-root . \
  --json out/validation/biological_validation.json
```

### Config file

The script reads **`inputs/project_parameters.generated.yaml`** when that file exists;
otherwise it falls back to **`project_parameters.Config.yaml`**. Module-specific checks
(see table above) run only when the matching **`workflow_profile.run_*`** flag is
`true` (for example `run_upstream`, `run_integrative`, `run_cluster`, `run_cell_types`).
If you edit toggles in the master Config, refresh the generated overlay before
validating so it matches what Sprocket would use:

```bash
bash launch-daedalus-downstream.sh    # dry-run: no --submit; refreshes generated YAML/inputs
```

### Seurat and where to run

Plain **`Rscript` on a login node** without Seurat still runs metadata / Cell Ranger
checks and file-existence checks, but **skips** steps that load Seurat objects (filtered
and integrated **`ncol`**, cluster metadata, cross-step cell counts).

When **Seurat** or **SeuratObject** is installed, the script **loads** upstream,
integrative, cluster, and cell-type RDS files. Use an **interactive node** (or
`daedalus-apptainer-rscript.sh` as above) with **enough memory for the largest
object**—avoid login nodes for full validation.

## Disable

```yaml
workflow_profile:
  run_biological_validation: false
```
