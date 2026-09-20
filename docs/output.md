# nf-core/gwasqc: Output

## Introduction

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Variant and sample QC lists](#variant-and-sample-qc-lists) - Per-stratum MAF keep-list, missingness and Hardy-Weinberg statistics, and the decision lists derived from them
- [LD pruning and long-range LD exclusion](#ld-pruning-and-long-range-ld-exclusion) - The pruned variant set of the sample checks and the variants excluded from the autosomal reports
- [Sex check](#sex-check) - The plink2 sex check, the mismatch table and removal list, and the F histogram
- [Heterozygosity](#heterozygosity) - The heterozygosity report and its plots, report-only
- [Relatedness](#relatedness) - The KING kinship table, the classified pairs, the duplicate removal list and the mean-kinship outliers
- [Ancestry](#ancestry) - The harmonisation of the reference panel, the projections, the assignment of every study sample to a super-population, the keep-lists and the mismatch removal list
- [QC'd genotypes](#qcd-genotypes) - The filtered PLINK 1 fileset of each stratum, written once from the original fileset and the decision lists
- [MultiQC](#multiqc) - Aggregate report describing results and QC from the whole pipeline
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

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
  - `<id>.missingness_ladder.tsv`: Call-rate ladder from 90 % to 99 %, one row per rate, each applied from the base fileset with the variant threshold first and the sample threshold second: the missing-call threshold the rate implies, the variants removed and remaining, the samples removed and remaining.
- `qc/<id>/hwe/`
  - `<id>.hardy`: [plink2 `--hardy`](https://www.cog-genomics.org/plink/2.0/basic_stats#hardy) autosomal exact-test report over the MAF-, `--geno`- and `--mind`-filtered set.
  - `<id>.hardy.x`: The chromosome X report, present only when the stratum carries chromosome X variants.
  - `<id>.hwe_exclude.txt`: Variants whose exact-test p-value is below `--hwe`, one ID per line.

</details>

[PLINK 2](https://www.cog-genomics.org/plink/2.0/) computes every statistic on the original fileset with the lists accumulated so far applied through `--extract`, `--exclude` and `--remove`, so no intermediate fileset is written. The decision lists are derived from the statistics in R at the configured thresholds. plink2 writes its `--missing` report before it applies `--geno`, so the variant threshold becomes an exclusion list first and the sample report is computed with that list excluded; a sample at the `--mind` threshold over all variants can survive once its missing calls in the excluded variants no longer count.

### LD pruning and long-range LD exclusion

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/ld_pruning/`
  - `<id>.prune.in`: Variants retained by [plink2 `--indep-pairwise`](https://www.cog-genomics.org/plink/2.0/ld#indep) over the QC'd set on every chromosome, one ID per line.
  - `<id>.prune.out`: Variants removed by pruning.
  - `<id>.highld_exclude.txt`: Pruned variants that lie inside a long-range LD region of `--high_ld_regions` or on a chromosome other than 1 to 22, one ID per line; excluded from the heterozygosity and relatedness reports.

</details>

Pruning runs over every chromosome so that the sex check sees the pruned chromosome X; the long-range LD and non-autosomal exclusion is applied afterwards, for the autosomal reports, as the legacy chain ordered the two. The default region file, `assets/high_ld_regions_b38.bed`, is derived from the legacy `highLDregions4bim_b38.awk` rules; its header records the derivation. The fixture used by the test profile has no LD structure, so pruning there removes almost nothing.

### Sex check

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/sex_check/`
  - `<id>.sexcheck`: [plink2 `--check-sex`](https://www.cog-genomics.org/plink/2.0/basic_stats#check_sex) report over the pruned set after `--split-par`, with the recorded and imputed sex, the `OK`/`PROBLEM` status, the chromosome X inbreeding coefficient `F`, and the chromosome Y call count and rate.
  - `<id>.sex_mismatch.tsv`: The `PROBLEM` rows of the report with its header; header only when there is no mismatch.
  - `<id>.sex_mismatch_remove.txt`: The mismatches as `FID IID` pairs, applied to the QC'd fileset only under `--apply_sample_removals`.
  - `<id>.sex_check_hist.tsv`: Counts of samples per recorded sex in 100 bins of `F`, the data behind the histogram.
  - `<id>.sex_check_hist.pdf`, `<id>.sex_check_hist.png`: Histogram of `F` by recorded sex; the PDF adds a page zoomed to a count of 20.

</details>

The thresholds are the `--sex_check_*` parameters, passed to `--check-sex` as its modifiers; plink2 makes the call and nothing is re-decided in R.

### Heterozygosity

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/heterozygosity/`
  - `<id>.het`: [plink2 `--het`](https://www.cog-genomics.org/plink/2.0/basic_stats#het) report over the pruned autosomal set outside the long-range LD regions: observed and expected homozygous counts and the inbreeding coefficient `F` per sample.
  - `<id>.het_hist.tsv`: Counts of samples in 100 bins of `F`, the data behind the histogram.
  - `<id>.het_hist.pdf`, `<id>.het_hist.png`: Histogram of `F`.
  - `<id>.het_sex_scatter.tsv`: Per sample, the heterozygosity `F_HET` and the sex-check `F_SEX`, joined on `FID` and `IID`.
  - `<id>.het_sex_scatter.pdf`, `<id>.het_sex_scatter.png`: Scatter of `F_HET` against `F_SEX`, coloured by recorded sex.

</details>

Heterozygosity is report-only: no threshold is applied and no sample is listed.

### Relatedness

<details markdown="1">
<summary>Output files</summary>

- `qc/<id>/relatedness/`
  - `<id>.kin0`: [plink2 `--make-king-table`](https://www.cog-genomics.org/plink/2.0/distance#make_king) KING-robust kinship table over the same set, restricted to pairs at or above `--king_table_filter`.
  - `<id>.relatedness_pairs.tsv`: The table with `DEGREE` and `RELATIONSHIP` per pair: `duplicate_or_mz` above kinship 0.354, `parent_offspring` or `full_sibling` between 0.177 and 0.354 depending on IBS0 against `--relatedness_po_ibs0_max`, `second_degree` above 0.0884, `third_degree` above 0.0442.
  - `<id>.relatedness_indiv.tsv`: Per sample, the number of reported pairs, the mean kinship over all other samples (unreported pairs count as zero) and whether it is an outlier at `--relatedness_indiv_sd` standard deviations above the cohort mean.
  - `<id>.relatedness_remove.txt`: One member of each duplicate/MZ pair, the one with the higher missing-call rate over the geno-retained variants (a tie drops the ID that sorts later), as `FID IID` pairs; applied only under `--apply_sample_removals`.
  - `<id>.relatedness_outliers.txt`: The mean-kinship outliers as `FID IID` pairs; published, never applied.
  - `<id>.relatedness_hist.tsv`: Counts of reported pairs in 100 bins of kinship, the data behind the histogram.
  - `<id>.relatedness_hist.pdf`, `<id>.relatedness_hist.png`: Histogram of the reported kinship coefficients; the PDF adds a page zoomed to a count of 100.

</details>

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
  - `<id>.ancestry_reference.sscore`, `<id>.ancestry_study.sscore`: [plink2 `--score`](https://www.cog-genomics.org/plink/2.0/score) projections of the reference and study samples onto the components, one `PC<k>_AVG` column per component; both runs use the same weights, the reference allele counts and the same modifiers, so the two tables share one scale.
  - `<id>.ancestry_model.tsv`: Leave-one-out confusion of the classifier on the reference samples.
  - `<id>.ancestry_assignment.tsv`: Per study sample, `ASSIGNED` (a super-population or `unassigned`), `STATUS` (`assigned`, `below_threshold`, `outside_sd`), `MAX_PROB`, `MAX_ABS_Z` (the largest per-component distance from the nearest group's reference mean, in that group's standard deviations) and `PROB_<group>` for every super-population.
  - `<id>.ancestry_summary.tsv`: Reference and study sample counts per group, then the unassigned study samples; every row states the rule that produced its count.
  - `<id>.ancestry_<group>.keep`: The study samples assigned to each super-population as `FID IID` pairs, one file per label of `--reference_pop_data`.
  - `<id>.ancestry_mismatch_remove.txt`: The study samples not assigned to the stratum's `ancestry` label, the unassigned included, as `FID IID` pairs; applied to the QC'd fileset only under `--apply_sample_removals` with `--ancestry_remove_mismatched`.
  - `<id>.ancestry_pca.tsv`: Reference and study coordinates with `SOURCE`, `POP`, `SUPER_POP` and `ASSIGNED`, the data behind the plots.
  - `<id>.ancestry_pc1_pc2.pdf`, `<id>.ancestry_pc1_pc2.png`, `<id>.ancestry_pc3_pc4.pdf`, `<id>.ancestry_pc3_pc4.png`: The projections, reference populations in their own colours and the study samples drawn above them in orange with a dark outline.

</details>

Each reference fileset of `--reference_panel` is restricted to the stratum's QC'd variants, the intersect is harmonised onto the stratum's strand (A/T and C/G pairs are dropped, flips are applied to the reference), the filesets are merged into one reference per stratum, and that reference is pruned outside the long-range LD regions and decomposed with [plink2 `--pca allele-wts`](https://www.cog-genomics.org/plink/2.0/strat#pca). Reference and study samples are then projected with one `--score` run each, following plink2's documented recipe, and a linear discriminant classifier trained on the reference labels (equal priors) assigns every study sample the super-population of its largest posterior when that reaches `--ancestry_prob_threshold`. With `--ancestry_sd_filter` set, an assigned sample more than that many standard deviations from its group's reference mean on any component becomes unassigned. The merged reference is the one intermediate fileset the pipeline writes, and it is not published.

### QC'd genotypes

<details markdown="1">
<summary>Output files</summary>

- `genotypes/<id>/`
  - `<id>.qc.bed`: PLINK 1 binary genotype table after all variant and sample lists were applied.
  - `<id>.qc.bim`: The matching variant file.
  - `<id>.qc.fam`: The matching sample file.

</details>

The fileset keeps the MAF-passing variants minus the `--geno` and `--hwe` exclusions, and drops the `--mind` removals. With `--apply_sample_removals` it also drops the sex mismatches, the listed duplicate members and, unless `--ancestry_remove_mismatched` is off, the ancestry mismatches.

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. Most of the pipeline QC results are visualised in the report and further statistics are available in the report data directory.

Results generated by MultiQC collate pipeline QC from supported tools e.g. FastQC. The pipeline has special steps which also allow the software versions to be reported in the MultiQC output for future traceability. For more information about how to use MultiQC reports, see <http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.
  - Parameters used by the pipeline run: `params.json`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
