# Daedalus WDL reference

This site documents the [Sprocket](https://sprocket.bio/) workflows and tasks used to run **Daedalus** downstream single-cell RNA-seq analysis from existing Cell Ranger outputs.

## Getting started

- Configure the project and launch runs with the scripts in [`scripts/README.md`](https://github.com/stjude-dnb-binfcore/sc-rna-seq-snap-daedalus/blob/main/scripts/README.md).
- Module ordering and optional branches are described in [`workflows/MODULE_DEPENDENCIES.md`](https://github.com/stjude-dnb-binfcore/sc-rna-seq-snap-daedalus/blob/main/workflows/MODULE_DEPENDENCIES.md).

## Primary workflow

**`daedalus_from_cellranger`** validates Cell Ranger `outs` directories, estimates LSF resources, and runs selected Daedalus analysis modules under `analyses/`.
