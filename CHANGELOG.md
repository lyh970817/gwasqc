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
  lists from the legacy 90 %–99 % call-rate ladder, Hardy-Weinberg statistics with an exclusion list, and a
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
  population table (`reference_pop_data`, validated by `assets/schema_reference_pop.json`): harmonisation of
  the reference variant tables with the stratum's QC'd variants by chromosome, position and alleles, whatever
  the IDs, with the strand-ambiguous pairs dropped and a build guard that stops the run when most of the IDs
  the two share sit at different positions; every reference fileset restricted to the matched variants by its
  own IDs, one merged reference per stratum with the reference IDs renamed to the study's through
  `--update-name` and the flips applied through `--update-alleles` (the restrictions and the merge are the
  route's only intermediate filesets, unpublished), the legacy ancestry-stage filters (`ancestry_geno`,
  `ancestry_maf`, `ancestry_hwe`) on the study's QC'd variants and on the reference, long-range LD exclusion
  before `--indep-pairwise`, `--pca allele-wts`, the legacy `--score` projection of reference and study samples
  (raw dosages, the reference mean-imputed and the study not), and the legacy classifier, a cross-validated
  elastic-net multinomial regression (caret with glmnet) on the reference-scaled components, with a
  class-probability threshold and an optional centroid rule. Publishes the harmonisation tables and lists, the
  pruned set, the eigenvalues, both projections, the assignment, summary, model and tuning tables, per-super-population
  keep-lists, the mismatch removal list, and the PC1/PC2 and PC3/PC4 plots with their plot-data table.
- Upstream-bound PLINK 2 atomic modules, each accepting a bed/bim/fam or pgen/pvar/psam fileset and the same
  four optional filter-list slots: `plink2/writesnplist`, `plink2/missing`, `plink2/hardy`,
  `plink2/indeppairwise`, `plink2/checksex`, `plink2/het`, `plink2/makekingtable`, `plink2/makebed`,
  `plink2/pmergelist`, `plink2/pcawts`, `plink2/score` and `plink2/freq`.
- Pipeline-owned decision, plot and report modules with their plot-data tables: `contig_exclude`, `geno_decisions`,
  `mind_decisions`, `hwe_decisions`, `missingness_ladder`, `missingness_plots`, `hwe_plots`, `highld_exclude`,
  `sex_check_decisions`, `heterozygosity_plots`, `relatedness_decisions`, `ancestry_harmonise`,
  `ancestry_assign`, `ancestry_reference_keep`, `stratum_report` and `qc_summary`. The missingness histograms carry a linear and a
  log-scale panel in place of the legacy fixed y-axis views, the ladder is rendered as a table image, and the
  Hardy-Weinberg histograms cover every variant and the legacy 1e-20 < P < 0.01 window.
- Reporting: a per-stratum summary row and MultiQC custom-content fragments assembled from the published lists
  and tables (`stratum_report`), the cross-stratum summary `gwasqc_summary.tsv` at the run root and the
  per-stage MultiQC tables cut from it (`qc_summary`), and a MultiQC report with one section per QC stage,
  strata as rows, the mismatch and duplicate-pair tables across strata, the removal-gate section stating what
  `apply_sample_removals` did or would do, and the review figures of every stratum embedded as images.
- Parameters: `input`, `outdir`; `genome_build`, `high_ld_regions`, `reference_panel`, `reference_pop_data`;
  `maf`, `geno`, `mind`, `hwe`, `missingness_mode`; `ld_window_size`, `ld_step_size`, `ld_r2`; `sex_check_max_female_xf`,
  `sex_check_min_male_xf`, `sex_check_max_female_ycount`, `sex_check_min_male_ycount`, `king_table_filter`,
  `relatedness_indiv_sd`, `relatedness_po_ibs0_max`, `apply_sample_removals`, `sample_qc_marker_set`,
  `sample_qc_shared_reference`, `small_n_threshold`, `ld_min_retained_fraction`; `skip_ancestry`,
  `ancestry_ld_window_size`, `ancestry_ld_step_size`, `ancestry_ld_r2`, `ancestry_n_pcs`,
  `ancestry_geno`, `ancestry_maf`, `ancestry_hwe`, `ancestry_prob_threshold`, `ancestry_sd_filter`, `ancestry_remove_mismatched`.
- Synthetic three-stratum fixture on the `gwasqc` branch of `nf-core/test-datasets`: two 125-sample strata
  with planted sex mismatches, a duplicate pair, parent-offspring and full-sibling pairs, high-missingness
  samples, Hardy-Weinberg violations, a long-range LD block, strand-flipped and strand-ambiguous variants and
  known-ancestry outliers, a 12-sample stratum with one sex mismatch, one duplicate pair and a sample missing
  one call at five variants, and a labelled reference panel. `conf/test_fixtures.config` resolves its relative
  fileset paths before validation, and the pipeline tests assert every planted defect by name.
- Per-stratum marker-set mode of the sample checks (`sample_qc_marker_set`: `auto`, `study` or `shared`, with
  `small_n_threshold`): a stratum below the threshold after the mind filter, or every stratum under a forced
  `shared`, runs its heterozygosity and KING relatedness reports on the harmonised, reference-pruned markers of
  the ancestry route, with the allele frequencies of the reference samples of its own super-population as the
  heterozygosity baseline (`--read-freq`) and those samples' own report drawn beneath the study's, and its sex
  check on every QC-passing chromosome X and Y variant unpruned; no study-side `--indep-pairwise` runs. The
  mode and the marker count are recorded per stratum in `gwasqc_summary.tsv`
  (`sample_qc_marker_set`, `sample_qc_markers`, `sample_qc_note`) and in a MultiQC section, and a `study`-mode
  stratum whose pruning kept fewer than `ld_min_retained_fraction` of its QC'd variants is noted.
- Choice of the reference samples the `shared` marker set is filtered and pruned on
  (`sample_qc_shared_reference`): `matched`, the default, reruns the ancestry-stage `--maf`, `--geno` and `--hwe` and `--indep-pairwise`
  outside the long-range LD regions on the reference samples of the stratum's own super-population, published
  as `<id>.ancestry_matched.prune.in`; `pooled` takes the ancestry route's pruned markers over the whole panel.
  A super-population with fewer than 50 reference samples, below which plink2 refuses LD pruning and frequency
  estimates, uses the pooled panel for that stratum, recorded as `pooled` with a `sample_qc_note`. The reference
  used is recorded per stratum in `gwasqc_summary.tsv` (`sample_qc_shared_reference`) and in the MultiQC
  marker-set section. `matched` is the default because of the first real run on CREATE (MID, 11 study samples
  against 136 matched reference samples; AMR, 70 against 412): pooled filtering and pruning left 57 MID
  heterozygosity markers monomorphic in the matched reference (none under `matched`), the matched
  heterozygosity F agreed better with the predecessor pipeline's estimates (r 0.983 against 0.969 for MID,
  0.886 against 0.724 for AMR) at a cost of 6-8 % of the pruned markers (MID 69,057 against 73,681; AMR 62,562
  against 67,879), and the sex check and ancestry outputs were byte-identical between the modes.
- Opt-in exclusion of the variants on non-standard contigs, `--exclude_nonstandard_contigs` (default `false`):
  by default a variant on an alt, random or unplaced contig, or on chromosome 0, goes through the filters like
  any other and reaches the QC'd fileset, as in the legacy pipeline, which ran PLINK with `--allow-extra-chr`
  and never dropped them, and `variants_contig_removed` reads 0. When set, a variant whose `.bim` chromosome
  code is not one of 1-22, X, Y, XY and MT (numeric or lettered, in either case, with or without a `chr` prefix,
  and `PAR1`/`PAR2` for the pseudo-autosomal regions) is listed by the pipeline-owned `contig_exclude` module,
  published as `qc/<id>/contigs/<id>.contig_exclude.txt` and excluded at the MAF run, so that it reaches no
  statistic, decision list, ancestry projection or QC'd fileset; `variants_contig_removed` counts it and
  `variants_maf_removed` counts the remaining variants alone. A reference panel carrying such contigs is read
  unchanged either way.
- `test_alt_contig` profile and fixture: the EUR stratum of the synthetic fixture beside a copy of it that
  also carries eight variants on seven GRCh38 alt and random contigs, against a copy of the reference panel
  that carries the same, with a pipeline test that asserts the copy keeps the eight variants by default and, under
  `--exclude_nonstandard_contigs`, that the copy's QC'd fileset and every published list and table equal the
  stratum's own.
- `missing_block` fixture: a copy of the EUR stratum in which seven samples miss every call on chromosomes 1
  and 2, on which the two missingness modes part: the single pass drops the 615 variants of the block and
  keeps the samples, the iterative ladder removes the seven samples at its first rung and keeps the block.
- Upstream-bound `plink2/freq` atom (`--freq`, with the `counts` modifier through `ext.args2`) and an optional
  `--read-freq` table on `plink2/het`; pipeline-owned `ancestry_reference_keep`, which lists the reference
  samples of a stratum's super-population from the population table as a `--keep` list.

### Changed

- The ancestry route matches reference variants by chromosome (a `chr` prefix ignored, `X`/`Y`/`XY`/`MT` read
  as `23` to `26`), position and alleles instead of by ID, so a panel named by array probe or `chr:pos` IDs
  meets the study at every shared site. The harmonisation table has one row per QC'd study variant, names the
  reference variant matched and the basis of the match (`BASIS`), replaces the `absent_from_target` class with
  `absent_from_reference` and adds `duplicate_position`; the summary counts each class by basis. The route
  publishes the reference IDs of the matched variants (`<id>.ancestry_reference_extract.snplist`) and the
  rename table (`<id>.ancestry_name_update.txt`), the flip table is keyed by the study ID, and the reference
  `--maf` and `--geno` filters moved from the per-fileset restriction to the pruning run. The
  `ancestry_reference_keep` list of a `shared` stratum is built by the ancestry route.
- `plink2/pmergelist` takes an optional `--update-name` table, applied before `--update-alleles`, which is
  then keyed by the new IDs.
- The heterozygosity histogram data carries a `source` column (`study`, and `reference` in the shared marker-set
  mode) with both sources binned over one range; the `shared`-mode reference keep list, `.afreq` table and
  `.het` report are published beside the study's report under the stratum's `heterozygosity` stage. The
  `variants_ld_pruned_*`, `variants_highld_excluded` and `variants_sample_checks` summary columns read `NA`
  for a stratum in the shared mode, and its `ld_pruning` directory is absent.
- plink2's refusal to run `--indep-pairwise`, `--check-sex` and `--het` below 50 samples is lifted where the
  marker-set mode makes the stratum's own estimates the user's choice: `--bad-ld` on the study-side pruning
  and `--bad-freqs` on the sex check and on the `study`-mode heterozygosity report, through `ext.args`; the
  `shared`-mode heterozygosity report reads the reference frequencies instead.
- Publication policy: the published tree holds the QC'd fileset, the decision lists, the statistics tables,
  the plot-data tables and figures, the ladder and summary tables, the MultiQC report and the pipeline
  information. The pruned-out list, the raw KING `.kin0` table and the `--score` projections are no longer
  published: the pruned-in list, the classified pairs table and the ancestry plot-data table carry them. The
  process-wide default `publishDir` publishes nothing and each per-method-family config in `conf/modules/`
  opts its own processes in by scientific stage.
- Missingness replicates the legacy GLAD pipeline's applied call-rate ladder by default
  (`missingness_mode iterative`, `Iterative_Missingness.sh`): at each call rate from 90 % up to the call rate
  1 - `geno` (95 % at the defaults), the variants and then the samples whose missing-call rate exceeds 1 - the
  call rate are removed from what the previous step left. Each step is one `--missing` run over the original
  fileset with the cumulative lists of the steps before it, because plink2 writes `--missing` before it
  applies `--geno`; nothing is materialised. `geno` and `mind` must then be equal and a whole percentage from
  0.01 to 0.10. `missingness_mode single` is the one pass of the canonical legacy script, `--geno` and then
  `--mind` on the geno-retained variants, which was the only behaviour before. The ladder table is cumulative
  in both modes and matches the legacy table: 20 rows, a variant and a sample step per call rate from 90 % to
  99 % (`step`, `call_rate`, `filter`, `missing_threshold`, `variants_removed`, `variants_remaining`,
  `samples_removed`, `samples_remaining`), in place of ten rows that applied each rate from the base fileset.
  `gwasqc_summary.tsv` and the MultiQC filter table gain `missingness_mode`. On the first real stratum that
  showed the difference, five samples sharing a block of some 105,000 missing variants cost the single pass
  those variants, where the ladder removes the five samples.
- The ancestry classifier is the legacy `ancestry_identifier.r` model in place of linear discriminant
  analysis: `caret::train(method = 'glmnet', metric = 'logLoss')` with five-fold cross-validation on the
  super-population labels, every component centred and scaled by the reference samples; there is no option
  to keep the discriminant classifier, which on the first real run assigned 23 of 70 AMR samples to EUR where
  the predecessor pipeline's glmnet model assigned them AMR. `<id>.ancestry_model.tsv` is now the five-fold cross-validated confusion
  with a second count column at the probability threshold (`N_THRESHOLD`), and `<id>.ancestry_model_tuning.tsv`
  is new. Two departures from the legacy script are recorded: the folds are drawn under a fixed seed, where
  the legacy cross-validation was unseeded, and the threshold comparison is `>=` on unrounded probabilities,
  where the legacy script compared three-decimal probabilities with `>`.
- The ancestry projection follows the legacy recipe in place of plink2's documented one: `--score` on the raw
  allele dosages with the `--pca allele-wts` weights, without `variance-standardize` and without `--read-freq`,
  the reference samples mean-imputed and the study samples scored with `no-mean-imputation`.
- The ancestry stage applies the legacy variant filters of its own: `ancestry_geno` (0.02), `ancestry_maf`
  (default `maf`) and `ancestry_hwe` (1e-6) on the stratum's QC'd variants before harmonisation, all three for
  a stratum of more than 100 samples after the mind removals and `ancestry_geno` alone otherwise, and all
  three on the reference samples in the pruning runs, where the reference was filtered with `maf` and `geno`
  and without a Hardy-Weinberg test before. The harmonisation table lists the study variants that pass them.
- Relatedness is estimated with KING-robust kinship (`--make-king-table`) rather than the legacy plink1.9
  `--genome` PI_HAT, and the pairs are classified on KING's own inference boundaries.
- The per-individual mean kinship is the legacy `IndividualIBD.r` statistic: the mean over every other sample,
  read from the `--make-king` matrix plink2 writes in the pass of the pair table, and an individual is an
  outlier at or above the cohort mean plus `--relatedness_indiv_sd` standard deviations. The duplicate rule
  compares the sample missingness over the MAF-passing variants before the `--geno` filter, the legacy
  `_check.imiss`.
- The per-individual mean-kinship histogram (`<id>.relatedness_indiv_hist.*`) and the three fixed-limit
  per-variant missingness histogram pages (`<id>.vmiss_hist_ylim.pdf`) of the legacy chain are published.

### Fixed

- Sample and variant IDs are read as text in every R step that reads a plink or population table
  (`geno_decisions`, `mind_decisions`, `hwe_decisions`, `hwe_plots`, `missingness_ladder`, `missingness_plots`,
  `sex_check_decisions`, `heterozygosity_plots`, `relatedness_decisions` and `ancestry_assign`), so an
  all-numeric ID with leading zeros, such as `007`, is written back to the decision lists byte for byte instead
  of being coerced to a number that no longer matches the fileset.
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
  files, matching the rest of the pipeline.
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
| r-caret      |             | 7.0-1         |
| r-data.table |             | 1.17.8        |
| r-ggplot2    |             | 3.5.2         |
| r-glmnet     |             | 4.1-10        |
| r-mlmetrics  |             | 1.1.3         |
| r-proc       |             | 1.19.0.1      |

`r-base` is 4.3.1 in the base-R modules that load no library (`geno_decisions`, `mind_decisions`,
`hwe_decisions`, `missingness_ladder`, `ancestry_harmonise`) and 4.4.3 in the modules that load `ggplot2` and
`data.table`. `r-caret`, `r-glmnet`, `r-mlmetrics` and `r-proc` belong to `ancestry_assign` alone, the last two
because caret's `multiClassSummary` loads them. `coreutils` is declared by no `environment.yml`: `stratum_report` and `qc_summary` invoke it from
the gawk image and report the version they find.
