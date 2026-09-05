# GLAD_EDGI_NBR QC workflow source archive

This directory is a code-only preservation bundle recovered from the CREATE HPC after the storage halt. It contains the two GLAD/NBR pre-QC scripts that were present beside the data, the newest canonical BioResource full-QC driver and its source-code dependencies, and the GLAD-specific full-QC variant.

No genotype, phenotype, ancestry, reference-panel, keep-list, log, report, or other participant-derived files are included. No PLINK binaries are included.

## Preservation policy

The workflow source is unmodified. Files copied directly retain their source bytes. The two pre-QC sources were stored remotely as bzip2 archives; they were decompressed without changing their contents and renamed locally only to distinguish their roles and identical remote basenames. Existing absolute paths, historical usernames, comments, mistakes, and software assumptions are deliberately preserved as evidence. Adapt a working copy rather than editing this archive in place.

## Layout and provenance

### Pre-QC

| Local file | Exact remote source | Remote timestamp | SHA-256 of decompressed content | Role |
| --- | --- | --- | --- | --- |
| `pre_qc/02.pre_QC_primary.sh` | `/scratch/prj/bioresource/recovered/data/GLAD_EDGI_NBR/02.pre_qc/02.pre_QC.sh.bz2` | 2023-04-17 12:48:56 +0100 | `ba6d925fc8c20199a8ad9544d2b8baae68712183434fe0265d477a679e60a185` | Converts per-batch VCFs, removes controls, updates sex/IDs, excludes duplicate positions, and merges GLAD batches. |
| `pre_qc/02.pre_QC_merge_GLAD_NBR.sh` | `/scratch/prj/bioresource/recovered/data/GLAD_EDGI_NBR/03.qc/02.pre_QC.sh.bz2` | 2023-04-17 13:19:34 +0100 | `3d6d88986740ae658f276b17ef6ac35f6204aed8f179f671efaf47fc2ba45db8` | A later merge-directory variant. Earlier conversion/update steps are commented out; it harmonizes duplicate positions and merges the PLINK inputs found in its working directory. |

These two files were selected instead of the older generic scripts under `Scripts/01.pre_qc/glad/` because they are the dataset-local workflow snapshots used for the April 2023 GLAD/NBR preparation, include later batches, and directly document the merge logic immediately preceding `GLAD_EDGI_NBRv3_pre`.

### Full QC

The primary driver is `full_pipe/full_pipe.sh`, copied from:

`/scratch/prj/bioresource/recovered/Scripts/02.qc/full_pipe.sh`

Remote timestamp: 2025-07-04 00:10:39 +0100. Remote size: 23,398 bytes. This was selected as the newest canonical `Scripts/02.qc` driver, ahead of `full_pipe_L.sh`, `oneclick.sh`, and `full_pipe_cutoffs.sh`.

Its copied source dependencies are in `full_pipe/dependencies/`:

| File | Remote timestamp |
| --- | --- |
| `Iterative_Missingness.sh` | 2022-11-20 16:40:35 +0000 |
| `missingness_histograms.r` | 2022-11-30 15:09:18 +0000 |
| `itmiss_table.r` | 2022-11-30 15:09:17 +0000 |
| `hardy_plots.r` | 2022-11-30 15:09:17 +0000 |
| `highLDregions4bim_b38.awk` | 2022-07-11 13:58:26 +0100 |
| `sex_check_hist.r` | 2022-11-30 15:09:18 +0000 |
| `sex_mismatch_table.r` | 2022-11-30 15:09:18 +0000 |
| `het_graphs.r` | 2022-12-11 13:49:47 +0000 |
| `IndividualIBD.r` | 2022-11-30 15:09:17 +0000 |
| `IBD_Hist.r` | 2023-03-30 23:53:21 +0100 |
| `ancestry_identifier.r` | 2025-07-30 23:51:33 +0100 |
| `bioresource.yml` | 2022-08-25 10:52:07 +0100 |

Every dependency above came from `/scratch/prj/bioresource/recovered/Scripts/02.qc/<filename>`.

The preserved GLAD-specific variant is `full_pipe/variants/full_pipe_GLAD_variant.sh`, copied from `/scratch/prj/bioresource/recovered/data/GLAD_EDGI_NBR/03.qc/full_pipe2.sh` (2024-04-26 14:30:49 +0100). It is retained because it reflects the operational GLAD branch and contains changes absent from the newer canonical script, including output-directory handling, split-X/ycount sex checking, an R 4.3 module choice, and individual-IBD plotting. Its extra plotting source, `full_pipe/variants/IndvIBD_Hist.r`, came from `/scratch/prj/bioresource/recovered/Scripts/02.qc/IndvIBD_Hist.r` (2025-03-28 12:57:51 +0000).

## Final manual GLAD/NBR merge

The exact PLINK command is reconstructed exactly from the PLINK options recorded in `GLAD_EDGI_NBRv3_pre.log.bz2`, whose run completed on 2023-04-28 at 14:05:50 in `/scratch/prj/nihr_ukbiobank/GLAD/02.pre_QC_rw/New_pre_QC/Merge_GLAD_NBR`:

```sh
plink --bfile COPINGR1R2R3R4R5_v1v2_b38_sex_hashed_geno0.10 \
  --bmerge GLAD_EDGI_all_rs \
  --allow-extra-chr \
  --merge-equal-pos \
  --make-bed \
  --out GLAD_EDGI_NBRv3_pre
```

The log reports 38,790 people and 749,044 variants in the resulting fileset. Those data are intentionally not included here.

## Runtime requirements not included

- GNU Bash, GNU Parallel, awk, sed, coreutils, and an HPC/SLURM environment for the embedded `#SBATCH` directives.
- PLINK 1.9. The pre-QC run loaded `plink/1.9-beta6.10-gcc-10.3.0`; the final merge log records PLINK v1.90b6.10 (17 June 2019).
- PLINK 2 for the full-QC ancestry stage. The remote 42 MB `Scripts/02.qc/plink2` executable was deliberately excluded.
- R plus packages used by the plotting and ancestry scripts. `full_pipe/dependencies/bioresource.yml` records the historical environment, but the environment must be recreated and checked on the target system.
- The per-batch input VCF or PLINK datasets, removal list, sex update file, variant-name and sample-ID update files used by pre-QC.
- The COPING/NBR and GLAD/EDGI PLINK inputs used by the final `--bmerge` command.
- The 1000 Genomes ancestry reference resources expected under the runtime scripts path, notably `ref/1kg/1KG_Phase3.chr*`, `ref_super_pop_keep_list.txt`, and `ref_pop_dat_reduced.txt`. Reference BED/BIM/FAM and keep/population files are data and were excluded.

## Known caveats

- Both pre-QC scripts hard-code paths under the old `/scratch/prj/nihr_ukbiobank/...` tree. They must be parameterized or run from an equivalent prepared working directory.
- The scripts discover inputs through shell globs, so an unexpected VCF, BIM, or FAM in the working directory changes the workflow input set.
- The canonical full-QC script still contains original, unrecovered `/scratch/prj/bioresource/...` defaults. Its `-d`, `-p`, `-n`, and `-o` arguments are intended to override them; `-p` must point to a directory containing the copied dependencies and separately supplied ancestry references.
- Near the end of canonical `full_pipe.sh`, report extraction refers to the literal `GLAD_test_ancestry_identifier.log` rather than `${name}_ancestry_identifier.log`. This is a preserved source defect.
- Historical GLAD SLURM logs show that the pipeline started and completed substantial PLINK work, but later reporting/ancestry steps sometimes failed because R packages such as `gridExtra`, `glmnet`, `spam`, or `caret` were missing, histogram inputs were empty, or ancestry score files were not produced.
- The canonical driver and the GLAD variant diverged. Newer modification time alone does not prove that every GLAD-specific fix was retained in the canonical version.
- Syntax checking can establish shell parse validity only; it does not validate external programs, R packages, reference data, absolute paths, or scientific correctness.

## Integrity

`SHA256SUMS` lists hashes for every preserved workflow/configuration file. Regenerate it only when intentionally creating a new archive revision.
