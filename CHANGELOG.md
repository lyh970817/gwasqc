# nf-core/gwasqc: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Entries are recorded directly under the next release heading; there is no persistent "Unreleased" section.

## v1.0.0dev - [date]

Initial release of nf-core/gwasqc, created with the [nf-core](https://nf-co.re/) template.

### Added

- Samplesheet of per-stratum PLINK 1 filesets (`id,ancestry,bed,bim,fam`) validated by nf-schema.
- Foundation QC chain per stratum: MAF keep-list, missingness statistics with geno/mind decision lists and the
  legacy call-rate ladder, Hardy-Weinberg statistics with an exclusion list, and a single terminal `--make-bed`
  materialisation driven by `--extract`/`--exclude`/`--remove` lists.
- Sample QC chain per stratum: LD pruning, a long-range LD and non-autosomal exclusion list from the tracked
  GRCh38 asset `assets/high_ld_regions_b38.bed`, the plink2 sex check with the pseudo-autosomal split and its
  mismatch table, removal list and F histogram, the heterozygosity report with its histogram and
  heterozygosity-against-sex scatter, and KING relatedness with classified pairs, a duplicate/MZ removal list
  and a mean-kinship outlier list; every plot publishes its plot-data table.
- Upstream-bound PLINK 2 modules `plink2/writesnplist`, `plink2/missing`, `plink2/hardy`, `plink2/indeppairwise`,
  `plink2/checksex`, `plink2/het`, `plink2/makekingtable` and `plink2/makebed` accepting bed/bim/fam or
  pgen/pvar/psam filesets plus optional filter lists.
- Parameters `maf`, `geno`, `mind`, `hwe`, `genome_build`, `high_ld_regions`, `ld_window_size`, `ld_step_size`,
  `ld_r2`, `sex_check_max_female_xf`, `sex_check_min_male_xf`, `sex_check_max_female_ycount`,
  `sex_check_min_male_ycount`, `king_table_filter`, `relatedness_indiv_sd`, `relatedness_po_ibs0_max` and
  `apply_sample_removals`.
- Ancestry inference per stratum against a schema-declared reference panel (`reference_panel`, a samplesheet
  of PLINK 1 filesets, whole-genome or per chromosome, validated by `assets/schema_reference.json`) and its
  population table (`reference_pop_data`, validated by `assets/schema_reference_pop.json`): every reference
  fileset restricted to the stratum's QC'd variants, harmonisation by ID, position and alleles with the
  strand-ambiguous pairs dropped and the flips applied to the reference through `--update-alleles`, one merged
  reference per stratum (the route's only intermediate fileset, unpublished), long-range LD exclusion before
  `--indep-pairwise`, `--freq counts` with `--pca allele-wts`, projection of reference and study samples with
  plink2's documented `--score` recipe, and a linear discriminant classifier (MASS, equal priors) with a
  posterior threshold and an optional centroid rule; publishes the harmonisation tables and lists, the pruned
  set, the eigenvalues, both projections, the assignment, summary and model tables, per-super-population
  keep-lists, the mismatch removal list, and the PC1/PC2 and PC3/PC4 plots with their plot-data table.
- Upstream-bound PLINK 2 modules `plink2/pmergelist`, `plink2/pcawts` and `plink2/score`, and pipeline-owned R
  modules `ancestry_harmonise` and `ancestry_assign`.
- Parameters `reference_panel`, `reference_pop_data`, `skip_ancestry`, `ancestry_ld_window_size`,
  `ancestry_ld_step_size`, `ancestry_ld_r2`, `ancestry_n_pcs`, `ancestry_prob_threshold`, `ancestry_sd_filter`
  and `ancestry_remove_mismatched`; under `apply_sample_removals` the ancestry mismatch list joins the terminal
  `--remove` unless `ancestry_remove_mismatched` is off.
- The remaining legacy review figures as pipeline-owned R modules with their plot-data tables: the per-variant
  and per-sample missingness histograms with the `geno` and `mind` thresholds marked (`missingness_plots`, one
  linear and one log-scale panel in place of the legacy fixed y-axis views), the call-rate ladder rendered as a
  table image, and the Hardy-Weinberg p-value histograms over every variant and within the legacy
  1e-20 < P < 0.01 window with the `hwe` threshold marked (`hwe_plots`).
- Reporting: a per-stratum summary row and MultiQC custom-content fragments assembled from the published lists
  and tables (`stratum_report`), the cross-stratum summary `gwasqc_summary.tsv` at the run root and the
  per-stage MultiQC tables cut from it (`qc_summary`), and a MultiQC report with one section per QC stage,
  strata as rows, the mismatch and duplicate-pair tables across strata, the removal-gate section stating what
  `apply_sample_removals` did or would do, and the review figures of every stratum embedded as images.

### Changed

- Publication policy: the published tree holds the QC'd fileset, the decision lists, the statistics tables,
  the plot-data tables and figures, the ladder and summary tables, the MultiQC report and the pipeline
  information. The pruned-out list, the raw KING `.kin0` table and the `--score` projections are no longer
  published: the pruned-in list, the classified pairs table and the ancestry plot-data table carry them.

- Missingness follows the legacy order exactly: the geno exclusion list is derived from one `--missing` run,
  the sample report and the mind removal list from a second run with that list excluded, and each rung of the
  call-rate ladder from its own run; plink2 writes `--missing` before it applies `--geno`, so the single-run
  approximation of the foundation chain is withdrawn.

### Fixed

### Dependencies

| Dependency   | Old version | New version |
| ------------ | ----------- | ----------- |
| PLINK 2      |             | 2.0.0a.6.9  |
| R            |             | 4.3.1       |
| R (plots)    |             | 4.4.3       |
| r-ggplot2    |             | 3.5.2       |
| r-data.table |             | 1.17.8      |
| r-mass       |             | 7.3-66      |
| gawk         |             | 5.3.1       |
| coreutils    |             | 9.4         |
| MultiQC      |             | 1.34        |

### Deprecated
