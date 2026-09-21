# nf-core/gwasqc: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings are `## [<version>] - <YYYY-MM-DD>`, the version linked to its release tag once one exists and
the date a `[date]` placeholder while the version is still in development. Entries are recorded directly under
the next release heading; there is no persistent "Unreleased" section, and a Keep a Changelog heading with no
entries is omitted rather than left empty.

## [1.0.0dev] - [date]

Initial release of nf-core/gwasqc, created with the [nf-core](https://nf-co.re/) template. It ports the legacy
GLAD/EDGI/NBR bash and R genotype QC pipeline, archived read-only under `GLAD_EDGI_NBR_qc_workflows/`, to this
pipeline. This release implements the PLINK-format route only: bed/bim/fam in, a QC'd bed/bim/fam fileset out.
The VCZ format route is deferred to its own issue, and pre-QC batch merging is out of scope.

### Added

- Per-stratum input contract: a samplesheet of PLINK 1 filesets (`id,ancestry,bed,bim,fam`) validated by
  nf-schema against `assets/schema_input.json`, with the fileset basename check and the ancestry-label check
  performed in Groovy at ingress. Each row is quality-controlled independently and its `id` is the output
  prefix of every file it produces.
- Foundation QC chain per stratum: a MAF keep-list, missingness statistics with the `geno` and `mind` decision
  lists and the legacy 90 %–99 % call-rate ladder, Hardy-Weinberg statistics with an exclusion list, and a
  single terminal `--make-bed` materialisation driven by the accumulated
  `--extract`/`--exclude`/`--keep`/`--remove` lists. Every statistic runs on the unfiltered fileset with the
  lists so far applied, so no intermediate fileset exists anywhere in the chain.
- Sample QC chain per stratum: LD pruning, a long-range LD and non-autosomal exclusion list from the tracked
  GRCh38 asset `assets/high_ld_regions_b38.bed`, the plink2 sex check with the pseudo-autosomal split and its
  mismatch table, removal list and F histogram, the heterozygosity report with its histogram and
  heterozygosity-against-sex scatter (report-only, no list), and KING-robust relatedness with classified pairs,
  a duplicate/MZ removal list and a mean-kinship outlier list.
- Ancestry inference per stratum against a schema-declared reference panel (`reference_panel`, a samplesheet of
  PLINK 1 filesets, whole-genome or per chromosome, validated by `assets/schema_reference.json`) and its
  population table (`reference_pop_data`, validated by `assets/schema_reference_pop.json`): every reference
  fileset restricted to the stratum's QC'd variants, harmonisation by ID, position and alleles with the
  strand-ambiguous pairs dropped and the flips applied to the reference through `--update-alleles`, one merged
  reference per stratum (the route's only intermediate fileset, unpublished), long-range LD exclusion before
  `--indep-pairwise`, `--freq counts` with `--pca allele-wts`, projection of reference and study samples with
  plink2's documented `--score` recipe, and a linear discriminant classifier (MASS, equal priors) with a
  posterior threshold and an optional centroid rule. Publishes the harmonisation tables and lists, the pruned
  set, the eigenvalues, both projections, the assignment, summary and model tables, per-super-population
  keep-lists, the mismatch removal list, and the PC1/PC2 and PC3/PC4 plots with their plot-data table.
- Upstream-bound PLINK 2 atomic modules, each accepting a bed/bim/fam or pgen/pvar/psam fileset and the same
  four optional filter-list slots: `plink2/writesnplist`, `plink2/missing`, `plink2/hardy`,
  `plink2/indeppairwise`, `plink2/checksex`, `plink2/het`, `plink2/makekingtable`, `plink2/makebed`,
  `plink2/pmergelist`, `plink2/pcawts` and `plink2/score`.
- Pipeline-owned decision, plot and report modules with their plot-data tables: `geno_decisions`,
  `mind_decisions`, `hwe_decisions`, `missingness_ladder`, `missingness_plots`, `hwe_plots`, `highld_exclude`,
  `sex_check_decisions`, `heterozygosity_plots`, `relatedness_decisions`, `ancestry_harmonise`,
  `ancestry_assign`, `stratum_report` and `qc_summary`. The missingness histograms carry a linear and a
  log-scale panel in place of the legacy fixed y-axis views, the ladder is rendered as a table image, and the
  Hardy-Weinberg histograms cover every variant and the legacy 1e-20 < P < 0.01 window.
- Reporting: a per-stratum summary row and MultiQC custom-content fragments assembled from the published lists
  and tables (`stratum_report`), the cross-stratum summary `gwasqc_summary.tsv` at the run root and the
  per-stage MultiQC tables cut from it (`qc_summary`), and a MultiQC report with one section per QC stage,
  strata as rows, the mismatch and duplicate-pair tables across strata, the removal-gate section stating what
  `apply_sample_removals` did or would do, and the review figures of every stratum embedded as images.
- Parameters: `input`, `outdir`; `genome_build`, `high_ld_regions`, `reference_panel`, `reference_pop_data`;
  `maf`, `geno`, `mind`, `hwe`; `ld_window_size`, `ld_step_size`, `ld_r2`; `sex_check_max_female_xf`,
  `sex_check_min_male_xf`, `sex_check_max_female_ycount`, `sex_check_min_male_ycount`, `king_table_filter`,
  `relatedness_indiv_sd`, `relatedness_po_ibs0_max`, `apply_sample_removals`; `skip_ancestry`,
  `ancestry_ld_window_size`, `ancestry_ld_step_size`, `ancestry_ld_r2`, `ancestry_n_pcs`,
  `ancestry_prob_threshold`, `ancestry_sd_filter`, `ancestry_remove_mismatched`.
- Synthetic two-stratum fixture on the `gwasqc` branch of `nf-core/test-datasets`, with planted sex mismatches,
  a duplicate pair, parent-offspring and full-sibling pairs, high-missingness samples, Hardy-Weinberg
  violations, a long-range LD block, strand-flipped and strand-ambiguous variants, known-ancestry outliers and
  a labelled reference panel. `conf/test_fixtures.config` resolves its relative fileset paths before
  validation, and the pipeline tests assert every planted defect by name.

### Changed

- Publication policy: the published tree holds the QC'd fileset, the decision lists, the statistics tables,
  the plot-data tables and figures, the ladder and summary tables, the MultiQC report and the pipeline
  information. The pruned-out list, the raw KING `.kin0` table and the `--score` projections are no longer
  published: the pruned-in list, the classified pairs table and the ancestry plot-data table carry them. The
  process-wide default `publishDir` publishes nothing and each per-method-family config in `conf/modules/`
  opts its own processes in by scientific stage.
- Missingness follows the legacy order exactly: the geno exclusion list is derived from one `--missing` run,
  the sample report and the mind removal list from a second run with that list excluded, and each rung of the
  call-rate ladder from its own run; plink2 writes `--missing` before it applies `--geno`, so the single-run
  approximation of the foundation chain is withdrawn.
- Relatedness is estimated with KING-robust kinship (`--make-king-table`) rather than the legacy plink1.9
  `--genome` PI_HAT, and the pairs are classified on KING's own inference boundaries.

### Fixed

- The stubs of `ancestry_assign`, `sex_check_decisions` and `relatedness_decisions` now write the same file set
  and the same headers as their real templates, derived from their inputs, so a `-stub` run exercises the
  published layout rather than a narrower one.
- The `meta.yml` of the plink2 atoms and of `ancestry_assign` is truthful: the optional outputs are marked
  optional with the `ext.args` modifier that suppresses each one, the ancestry keep-list semantics state which
  value set names the files and what the empty and unassigned cases produce, the population-table columns are
  named, and the container lock-file paths point at `modules/local/` where the modules actually live.
- The base-R decision templates (`geno_decisions`, `mind_decisions`, `hwe_decisions`, `missingness_ladder`) and
  `relatedness_decisions` stop with a message naming the missing column when a required input column is absent,
  instead of writing an empty decision list and exiting successfully.
- The KING degree lower bounds are inclusive, so a pair reported at exactly `--king_table_filter` is
  classified third-degree rather than falling outside every class.
- The kinship-table parser accepts `ID1`/`ID2` as well as `IID1`/`IID2`, so a `--make-king-table` report
  written without the `FID` columns is classified like one written with them.
- `ancestry_harmonise` reads a `.pvar` through plink2's own bim mapping (A1 = ALT, A2 = REF), so a mixed
  bim/pvar input pair classifies its variants exactly as a bim/bim pair does.
- The five base-R modules moved from frozen biocontainers to the Wave/Seqera container convention with lock
  files, matching the rest of the pipeline, and `r-mass` is declared by `ancestry_assign` rather than being
  relied on implicitly.
- The nf-test version used in CI is aligned with the development shell (0.9.5), so a version difference cannot
  change a test result between the two.
- The contributing guide's tags and links resolve.
- The template workflows that need nf-core or Seqera secrets are guarded to the `nf-core/gwasqc` repository, so
  they do not fail on a fork or a mirror that has no such secrets.

### Dependencies

| Dependency   | Old version | New version   |
| ------------ | ----------- | ------------- |
| coreutils    |             | 9.4           |
| gawk         |             | 5.3.1         |
| MultiQC      |             | 1.34          |
| plink2       |             | 2.0.0a.6.9    |
| r-base       |             | 4.3.1 / 4.4.3 |
| r-data.table |             | 1.17.8        |
| r-ggplot2    |             | 3.5.2         |
| r-mass       |             | 7.3-66        |

`r-base` is 4.3.1 in the base-R modules that load no library (`geno_decisions`, `mind_decisions`,
`hwe_decisions`, `missingness_ladder`, `ancestry_harmonise`) and 4.4.3 in the modules that load `ggplot2` and
`data.table`. `coreutils` is declared by no `environment.yml`: `stratum_report` and `qc_summary` invoke it from
the gawk image and report the version they find.
