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

### Changed

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
| gawk         |             | 5.3.1       |

### Deprecated
