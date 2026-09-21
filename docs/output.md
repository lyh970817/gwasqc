# nf-core/gwasqc: Output

## Introduction

This document describes the output produced by the pipeline. The MultiQC report summarises every stage across strata and embeds the review figures; the tables and figures it is built from are published beside the statistics they were derived from.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory. `<id>` is the stratum identifier from the samplesheet; every file of a stratum carries it as a prefix.

The published tree holds only what a reviewer reads: the QC'd fileset, every decision list, the statistics tables, the plot-data tables and the figures, the ladder and summary tables, the MultiQC report and the pipeline information. Every intermediate that a published table already contains stays in the work directory: the pruned-out variants (the QC'd set minus the pruned-in list), the raw KING table (the classified pairs table carries all of its columns), the score projections (the ancestry plot-data table carries every coordinate), the per-rung missingness reports of the ladder, the merged reference fileset, the per-stratum summary rows and the MultiQC fragments, and the plink2 run logs and version fragments.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [QC summary](#qc-summary) - One table across strata, the same shape as the MultiQC report's first section
- [Variant and sample QC lists](#variant-and-sample-qc-lists) - Per-stratum MAF keep-list, missingness and Hardy-Weinberg statistics, the decision lists derived from them, and their histograms
- [LD pruning and long-range LD exclusion](#ld-pruning-and-long-range-ld-exclusion) - The pruned variant set of the sample checks and the variants excluded from the autosomal reports
- [Sex check](#sex-check) - The plink2 sex check, the mismatch table and removal list, and the F histogram
- [Heterozygosity](#heterozygosity) - The heterozygosity report and its plots, report-only
- [Relatedness](#relatedness) - The classified kinship pairs, the duplicate removal list, the mean-kinship outliers and the kinship histogram
- [Ancestry](#ancestry) - The harmonisation of the reference panel, the assignment of every study sample to a super-population, the keep-lists, the mismatch removal list and the projection plots
- [QC'd genotypes](#qcd-genotypes) - The filtered PLINK 1 fileset of each stratum, written once from the original fileset and the decision lists
- [MultiQC](#multiqc) - The report, one section per QC stage, fed by the tables above
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### QC summary

<details markdown="1">
<summary>Output files</summary>

- `gwasqc_summary.tsv`: One row per stratum, in stratum id order, with the columns below; the ancestry columns are present only when ancestry inference ran.

</details>

Every number in the summary is a line count of a published decision list, a row count of a published table, or a statistic of one of its columns; nothing is re-decided and no log is read. The columns, in order:

| Column                                                                                                                                                                           | Meaning                                                                                                                                                                                                     |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `stratum`, `ancestry`                                                                                                                                                            | The samplesheet `id` and `ancestry` of the row.                                                                                                                                                             |
| `samples_input`, `variants_input`                                                                                                                                                | Lines of the input `.fam` and `.bim`.                                                                                                                                                                       |
| `maf_threshold`, `variants_maf_removed`, `variants_after_maf`                                                                                                                    | `--maf`, the variants it dropped, and the lines of `<id>.maf.snplist`.                                                                                                                                      |
| `geno_threshold`, `variants_geno_removed`, `variants_after_geno`                                                                                                                 | `--geno`, the lines of `<id>.geno_exclude.txt`, and the MAF-passing variants that remain.                                                                                                                   |
| `mind_threshold`, `samples_mind_removed`, `samples_after_mind`                                                                                                                   | `--mind`, the lines of `<id>.mind_remove.txt`, and the samples that remain.                                                                                                                                 |
| `hwe_threshold`, `variants_hwe_removed`, `variants_after_hwe`                                                                                                                    | `--hwe`, the lines of `<id>.hwe_exclude.txt`, and the QC'd variant set.                                                                                                                                     |
| `variants_ld_pruned_in`, `variants_ld_pruned_out`                                                                                                                                | Lines of `<id>.prune.in`, and the QC'd variants pruning removed.                                                                                                                                            |
| `variants_highld_excluded`, `variants_sample_checks`                                                                                                                             | Lines of `<id>.highld_exclude.txt`, and the pruned autosomal variants outside the long-range LD regions that the heterozygosity and relatedness reports use.                                                |
| `sex_check_problems`, `sex_removals`                                                                                                                                             | Rows of `<id>.sex_mismatch.tsv`, and whether that list was `applied` to the QC'd fileset or `listed only`.                                                                                                  |
| `het_samples`, `het_f_mean`, `het_f_sd`, `het_f_min`, `het_f_max`, `het_outside_3sd`                                                                                             | Samples in `<id>.het`, the mean, standard deviation, minimum and maximum of its `F`, and the samples whose `F` lies more than three standard deviations from the mean (informational; no sample is listed). |
| `relatedness_pairs_reported`, `relatedness_duplicate_or_mz`, `relatedness_parent_offspring`, `relatedness_full_sibling`, `relatedness_second_degree`, `relatedness_third_degree` | Rows of `<id>.relatedness_pairs.tsv` in total and per `RELATIONSHIP`.                                                                                                                                       |
| `relatedness_removed`, `relatedness_removals`, `relatedness_outliers`                                                                                                            | Lines of `<id>.relatedness_remove.txt`, whether that list was `applied` or `listed only`, and lines of `<id>.relatedness_outliers.txt`.                                                                     |
| `ancestry_n_<group>`, `ancestry_unassigned`                                                                                                                                      | Study samples assigned to each super-population and the unassigned, from `<id>.ancestry_summary.tsv`.                                                                                                       |
| `ancestry_mismatches`, `ancestry_removals`                                                                                                                                       | Lines of `<id>.ancestry_mismatch_remove.txt`, and whether that list was `applied` or `listed only`.                                                                                                         |
| `samples_removed_under_gate`                                                                                                                                                     | The samples `--apply_sample_removals` removed, or would remove when off: the union of the mind, sex-mismatch, duplicate and, while `--ancestry_remove_mismatched` holds, ancestry-mismatch lists.           |
| `samples_removed`, `samples_final`, `variants_final`                                                                                                                             | What the QC'd fileset actually lost, and the lines of its `.fam` and `.bim`.                                                                                                                                |

### Variant and sample QC lists

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/maf/`
  - `<id>.maf.snplist`: Variants passing the `--maf` threshold, one ID per line; the keep-list every later step starts from.
- `qc/<id>/missingness/`
  - `<id>.vmiss`: [plink2 `--missing`](https://www.cog-genomics.org/plink/2.0/basic_stats#missing) per-variant missing-call report over the MAF-passing variants.
  - `<id>.geno_exclude.txt`: Variants whose missing-call rate exceeds `--geno`, one ID per line.
  - `<id>.smiss`: plink2 `--missing` per-sample missing-call report over the MAF-passing variants that survive `--geno`, as the legacy chain measured it.
  - `<id>.mind_remove.txt`: Samples whose missing-call rate over those variants exceeds `--mind`, one `FID IID` pair per line.
  - `<id>.missingness_ladder.tsv`: Call-rate ladder from 90 % to 99 %, one row per rate, each applied from the base fileset with the variant threshold first and the sample threshold second: `call_rate`, the `missing_threshold` the rate implies, `variants_removed`, `variants_remaining`, `samples_removed` and `samples_remaining`.
  - `<id>.missingness_ladder.pdf`, `<id>.missingness_ladder.png`: The ladder rendered as a table image.
  - `<id>.vmiss_hist.tsv`: Counts of variants in 100 bins of `F_MISS` (`bin_start`, `bin_end`, `count`) from zero to the larger of the largest rate and `--geno`, the data behind the histogram.
  - `<id>.vmiss_hist.pdf`, `<id>.vmiss_hist.png`: Histogram of the per-variant missing-call rate, counts on a linear and on a log scale side by side, with `--geno` as a dashed line.
  - `<id>.smiss_hist.tsv`: Counts of samples in 100 bins of `F_MISS` from zero to the larger of the largest rate and `--mind`, the data behind the histogram.
  - `<id>.smiss_hist.pdf`, `<id>.smiss_hist.png`: Histogram of the per-sample missing-call rate in the same two panels, with `--mind` as a dashed line.
- `qc/<id>/hwe/`
  - `<id>.hardy`: [plink2 `--hardy`](https://www.cog-genomics.org/plink/2.0/basic_stats#hardy) autosomal exact-test report over the MAF-, `--geno`- and `--mind`-filtered set.
  - `<id>.hardy.x`: The chromosome X report, present only when the stratum carries chromosome X variants.
  - `<id>.hwe_exclude.txt`: Variants whose exact-test p-value is below `--hwe`, one ID per line.
  - `<id>.hwe_hist.tsv`: Counts of variant rows per `report` (`autosomal`, `chrX`) in 100 bins of the p-value over [0, 1] (`bin_start`, `bin_end`, `count`), the data behind the histogram.
  - `<id>.hwe_hist.pdf`, `<id>.hwe_hist.png`: Histogram of the exact-test p-value over every variant row, stacked by report.
  - `<id>.hwe_hist_window.tsv`: Counts of variant rows per `report` in 100 bins of log10 p-value over [-20, -2] (`log10_p_start`, `log10_p_end`, `count`), the window 1e-20 < P < 0.01 of the legacy plot.
  - `<id>.hwe_hist_window.pdf`, `<id>.hwe_hist_window.png`: The windowed histogram with `--hwe` as a dashed line.

</details>

[PLINK 2](https://www.cog-genomics.org/plink/2.0/) computes every statistic on the original fileset with the lists accumulated so far applied through `--extract`, `--exclude` and `--remove`, so no intermediate fileset is written. The decision lists are derived from the statistics in R at the configured thresholds. plink2 writes its `--missing` report before it applies `--geno`, so the variant threshold becomes an exclusion list first and the sample report is computed with that list excluded; a sample at the `--mind` threshold over all variants can survive once its missing calls in the excluded variants no longer count. The legacy missingness histograms were drawn three times with fixed y-axis limits so that the tail could be read under the peak at zero; the log-scale panel shows the same tail at any cohort size.

### LD pruning and long-range LD exclusion

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/ld_pruning/`
  - `<id>.prune.in`: Variants retained by [plink2 `--indep-pairwise`](https://www.cog-genomics.org/plink/2.0/ld#indep) over the QC'd set on every chromosome, one ID per line.
  - `<id>.highld_exclude.txt`: Pruned variants that lie inside a long-range LD region of `--high_ld_regions` or on a chromosome other than 1 to 22, one ID per line; excluded from the heterozygosity and relatedness reports.

</details>

Pruning runs over every chromosome so that the sex check sees the pruned chromosome X; the long-range LD and non-autosomal exclusion is applied afterwards, for the autosomal reports, as the legacy chain ordered the two. The pruned-out list is the QC'd set minus `<id>.prune.in` and is not published. The default region file, `assets/high_ld_regions_b38.bed`, is derived from the legacy `highLDregions4bim_b38.awk` rules; its header records the derivation. The fixture used by the test profile has no LD structure, so pruning there removes almost nothing.

### Sex check

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/sex_check/`
  - `<id>.sexcheck`: [plink2 `--check-sex`](https://www.cog-genomics.org/plink/2.0/basic_stats#check_sex) report over the pruned set after `--split-par`, with the recorded and imputed sex, the `OK`/`PROBLEM` status, the chromosome X inbreeding coefficient `F`, and the chromosome Y call count and rate.
  - `<id>.sex_mismatch.tsv`: The `PROBLEM` rows of the report with its header; header only when there is no mismatch.
  - `<id>.sex_mismatch_remove.txt`: The mismatches as `FID IID` pairs, applied to the QC'd fileset only under `--apply_sample_removals`.
  - `<id>.sex_check_hist.tsv`: Counts of samples per `recorded_sex` in 100 bins of `F` (`bin_start`, `bin_end`, `count`), the data behind the histogram.
  - `<id>.sex_check_hist.pdf`, `<id>.sex_check_hist.png`: Histogram of `F` by recorded sex; the PDF adds a page zoomed to a count of 20.

</details>

The thresholds are the `--sex_check_*` parameters, passed to `--check-sex` as its modifiers; plink2 makes the call and nothing is re-decided in R.

### Heterozygosity

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/heterozygosity/`
  - `<id>.het`: [plink2 `--het`](https://www.cog-genomics.org/plink/2.0/basic_stats#het) report over the pruned autosomal set outside the long-range LD regions: observed and expected homozygous counts and the inbreeding coefficient `F` per sample.
  - `<id>.het_hist.tsv`: Counts of samples in 100 bins of `F` (`bin_start`, `bin_end`, `count`), the data behind the histogram.
  - `<id>.het_hist.pdf`, `<id>.het_hist.png`: Histogram of `F`.
  - `<id>.het_sex_scatter.tsv`: Per sample, `FID`, `IID`, `PEDSEX`, the heterozygosity `F_HET` and the sex-check `F_SEX`, joined on `FID` and `IID`.
  - `<id>.het_sex_scatter.pdf`, `<id>.het_sex_scatter.png`: Scatter of `F_HET` against `F_SEX`, coloured by recorded sex.

</details>

Heterozygosity is report-only: no threshold is applied and no sample is listed. The summary's `het_outside_3sd` counts the samples more than three standard deviations from the mean `F` for review and lists none of them.

### Relatedness

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/relatedness/`
  - `<id>.relatedness_pairs.tsv`: The [plink2 `--make-king-table`](https://www.cog-genomics.org/plink/2.0/distance#make_king) KING-robust kinship table over the same set, restricted to pairs at or above `--king_table_filter`, with every column of the report (`FID1`, `IID1`, `FID2`, `IID2`, `NSNP`, `HETHET`, `IBS0`, `KINSHIP`) and `DEGREE` and `RELATIONSHIP` per pair, on KING's inference boundaries taken as inclusive lower bounds: `duplicate_or_mz` at kinship 0.354 or above, `parent_offspring` or `full_sibling` from 0.177 up to it depending on IBS0 against `--relatedness_po_ibs0_max`, `second_degree` from 0.0884 and `third_degree` from 0.0442, so a pair reported at exactly the default `--king_table_filter` is third-degree.
  - `<id>.relatedness_indiv.tsv`: Per sample, the number of reported pairs, the mean kinship over all other samples (unreported pairs count as zero) and whether it is an outlier at `--relatedness_indiv_sd` standard deviations above the cohort mean.
  - `<id>.relatedness_remove.txt`: One member of each duplicate/MZ pair, the one with the higher missing-call rate over the geno-retained variants (a tie drops the ID that sorts later), as `FID IID` pairs; applied only under `--apply_sample_removals`.
  - `<id>.relatedness_outliers.txt`: The mean-kinship outliers as `FID IID` pairs; published, never applied.
  - `<id>.relatedness_hist.tsv`: Counts of reported pairs in 100 bins of kinship (`bin_start`, `bin_end`, `count`), the data behind the histogram.
  - `<id>.relatedness_hist.pdf`, `<id>.relatedness_hist.png`: Histogram of the reported kinship coefficients; the PDF adds a page zoomed to a count of 100.

</details>

The raw `.kin0` report is not published: the classified pairs table is the report with two columns added.

### Ancestry

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/ancestry/`
  - `<id>.ancestry_harmonisation.tsv`: One row per reference variant of the intersect with the stratum's QC'd variants: chromosome, position, the reference and stratum alleles and its class (`match`, `swap`, `flip`, `ambiguous`, `allele_mismatch`, `non_snp`, `position_mismatch`, `absent_from_target`, `duplicate_id`).
  - `<id>.ancestry_harmonisation_summary.tsv`: Variant count per class and whether the class is retained.
  - `<id>.ancestry_harmonised.snplist`: The retained variants (`match`, `swap`, `flip`), one ID per line.
  - `<id>.ancestry_flip_update.txt`: The strand-flipped variants with their reference alleles and the complements applied to the reference through `--update-alleles`; empty when nothing flips.
  - `<id>.ancestry.highld_exclude.txt`: Harmonised variants inside a long-range LD region of `--high_ld_regions` or off the autosomes, excluded from the reference before pruning.
  - `<id>.ancestry.prune.in`: Variants retained by [plink2 `--indep-pairwise`](https://www.cog-genomics.org/plink/2.0/ld#indep) over the merged reference; the components are computed and projected on exactly this set.
  - `<id>.ancestry.eigenval`: Eigenvalues of the reference components, one per line.
  - `<id>.ancestry_model.tsv`: Leave-one-out confusion of the classifier on the reference samples (`OBSERVED`, `PREDICTED`, `N`).
  - `<id>.ancestry_assignment.tsv`: Per study sample, `ASSIGNED` (a super-population or `unassigned`), `STATUS` (`assigned`, `below_threshold`, `outside_sd`), `MAX_PROB`, `MAX_ABS_Z` (the largest per-component distance from the nearest group's reference mean, in that group's standard deviations) and `PROB_<group>` for every super-population.
  - `<id>.ancestry_summary.tsv`: Reference and study sample counts per group (`GROUP`, `STATUS`, `N_REFERENCE`, `N_STUDY`, `RULE`), then the unassigned study samples; every row states the rule that produced its count.
  - `<id>.ancestry_<group>.keep`: The study samples assigned to each super-population as `FID IID` pairs; one file per super-population present among the scored, labelled reference samples, in sorted label order. A group to which no study sample was assigned gets an empty file, and the unassigned study samples get no file at all.
  - `<id>.ancestry_mismatch_remove.txt`: The study samples not assigned to the stratum's `ancestry` label, the unassigned included, as `FID IID` pairs; applied to the QC'd fileset only under `--apply_sample_removals` with `--ancestry_remove_mismatched`.
  - `<id>.ancestry_pca.tsv`: Reference and study coordinates (`PC1` to `PC<n>`) with `SOURCE`, `POP`, `SUPER_POP` and `ASSIGNED`, the data behind the plots and the one table of the projections.
  - `<id>.ancestry_pc1_pc2.pdf`, `<id>.ancestry_pc1_pc2.png`, `<id>.ancestry_pc3_pc4.pdf`, `<id>.ancestry_pc3_pc4.png`: The projections, reference populations in their own colours and the study samples drawn above them in orange with a dark outline.

</details>

Each reference fileset of `--reference_panel` is restricted to the stratum's QC'd variants, the intersect is harmonised onto the stratum's strand (A/T and C/G pairs are dropped, flips are applied to the reference), the filesets are merged into one reference per stratum, and that reference is pruned outside the long-range LD regions and decomposed with [plink2 `--pca allele-wts`](https://www.cog-genomics.org/plink/2.0/strat#pca). Reference and study samples are then projected with one `--score` run each, following plink2's documented recipe, and a linear discriminant classifier trained on the reference labels (equal priors) assigns every study sample the super-population of its largest posterior when that reaches `--ancestry_prob_threshold`. With `--ancestry_sd_filter` set, an assigned sample more than that many standard deviations from its group's reference mean on any component becomes unassigned. The merged reference is the one intermediate fileset the pipeline writes, and neither it nor the raw `--score` tables are published: the plot-data table carries every projected coordinate. With `--skip_ancestry` the directory is absent.

### QC'd genotypes

<details markdown="1">
<summary>Output files</summary>

- `genotypes/<id>/`
  - `<id>.qc.bed`: PLINK 1 binary genotype table after all variant and sample lists were applied.
  - `<id>.qc.bim`: The matching variant file.
  - `<id>.qc.fam`: The matching sample file.

</details>

The fileset keeps the MAF-passing variants minus the `--geno` and `--hwe` exclusions, and drops the `--mind` removals. With `--apply_sample_removals` it also drops the sex mismatches, the listed duplicate members and, unless `--ancestry_remove_mismatched` is off, the ancestry mismatches. The summary's `samples_removed_under_gate` states what the gate removed, or would have removed, in either case.

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. Every section of this report is custom content fed by the tables above, never by a log, and the figures are embedded as the published PNGs. The sections, in report order, with one row per stratum unless stated:

- **QC summary**: the `gwasqc_summary.tsv` table; the threshold and per-stage detail columns are hidden and can be shown from the table's column selector.
- **Variant and sample filters**: _Filters_ (input counts, each threshold and what it removed, the pruned set), _Missingness ladder_ (one row per stratum and call rate), and one figure section per stratum with the missingness histograms, the ladder image and the Hardy-Weinberg histograms.
- **Sex check**: _Summary_ (samples checked, mismatches, whether the list was applied), _Mismatches_ (one row per mismatched sample across strata, present when any stratum has one), and one figure section per stratum.
- **Heterozygosity**: _Summary_ (the `F` distribution) and one figure section per stratum with the histogram and the heterozygosity-against-sex-check scatter.
- **Relatedness**: _Summary_ (pairs per class, the duplicate members listed, the outliers), _Duplicate and first-degree pairs_ (one row per such pair across strata, naming the member listed for removal), and one figure section per stratum.
- **Ancestry**: _Summary_ (study samples per super-population against the stratum label, the unassigned, the mismatches) and one figure section per stratum with the PC1/PC2 and PC3/PC4 projections; absent with `--skip_ancestry`.
- **Sample removals**: what `--apply_sample_removals` did or would do: every removal list's size, whether it was applied, the union the gate removes, and the final counts.

The pipeline has special steps which also allow the software versions to be reported in the MultiQC output for future traceability. For more information about how to use MultiQC reports, see <http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow, each stamped with the launch timestamp: `execution_timeline_<suffix>.html`, `execution_report_<suffix>.html`, `execution_trace_<suffix>.txt` and `pipeline_dag_<suffix>.html`.
  - Parameters used by the pipeline run: `params_<suffix>.json`.
  - Software versions collected from every process that ran: `nf_core_gwasqc_software_mqc_versions.yml`, which is also the source of the MultiQC report's software-versions section.
  - Reports generated by the pipeline: `pipeline_report.html` and `pipeline_report.txt`. These are present only if the `--email` or `--email_on_fail` parameter is used when running the pipeline.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
