# Biological output validation

After a successful **Daedalus downstream** Sprocket run, the launcher can run
`scripts/daedalus_validate_outputs.R` when `workflow_profile.run_biological_validation`
is `true` (default).

## What it checks

| Check | When | Purpose |
|-------|------|---------|
| Metadata vs Cell Ranger | Always (if validation enabled) | `project_metadata.tsv` `ID` values match sample dirs under `data_dir` |
| Cell Ranger cell counts | Always | Non-zero estimated cells per sample |
| Upstream deliverable | `run_upstream` | `seurat_obj_merged_filtered.rds` exists; filtered cell count vs Cell Ranger totals |
| Integrative deliverable | `run_integrative` | `seurat_obj_integrated_<integration_method>.rds` exists; ncol vs upstream |
| Cluster deliverable | `run_cluster` | `seurat_obj_clusters_all.rds` under cluster results; ≥2 clusters |
| Cell types deliverable | `run_cell_types` | Merged or SingleR broad annotation RDS |

Warnings (e.g. aggressive filtering) do not fail the run unless you pass `--strict`.

## Manual run

```bash
Rscript scripts/daedalus_validate_outputs.R \
  --daedalus-root /path/to/project \
  --json out/validation/biological_validation.json
```

Uses `inputs/project_parameters.generated.yaml` when present, else master Config.

## Disable

```yaml
workflow_profile:
  run_biological_validation: false
```
