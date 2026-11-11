# nf-core/gwasqc: Usage

## :warning: Please read this documentation on the nf-core website: [https://nf-co.re/gwasqc/usage](https://nf-co.re/gwasqc/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

nf-core/gwasqc quality-controls genotype array data. Each row of the samplesheet is a stratum — a PLINK 1 bed/bim/fam fileset, typically one ancestry group of a cohort — and every stratum is quality-controlled independently of every other one: nothing is pooled, and no count in the report mixes strata.

Every statistic is computed by plink2 on the original fileset with the decision lists accumulated so far applied through `--extract`, `--exclude` and `--remove`, so each report describes the filtered data although no filtered fileset exists. The QC'd fileset is written exactly once, at the end, by a single `--make-bed` run over the original fileset and the complete list set. That has two consequences worth knowing before you read the output: every threshold you set becomes a published list of the variants or samples it selected, and the QC'd fileset can always be reconstructed from the input fileset and those lists.

This pipeline reads and writes PLINK 1 bed/bim/fam filesets. A pgen/pvar/psam fileset is accepted by every plink2 module interface unconverted, but that route is not declared by the samplesheet schema and is untested; the VCZ format route is not implemented.

All parameters are documented on the [parameters page](https://nf-co.re/gwasqc/parameters) and by the pipeline itself: `--help` prints the visible parameters, `--help_full` prints every parameter with its help text, and `--show_hidden` adds the institutional and generic boilerplate that `--help` omits.

## Samplesheet input

You will need to create a samplesheet with one row per stratum before running the pipeline. A stratum is a PLINK 1 bed/bim/fam fileset, typically one ancestry group of a cohort, that the pipeline quality-controls independently of every other row. Use this parameter to specify its location. It has to be a comma-separated file with exactly the 5 columns below and a header row.

```bash
--input '[path to samplesheet file]'
```

```csv title="samplesheet.csv"
id,ancestry,bed,bim,fam
cohort_eur,EUR,/path/to/genotypes/cohort_eur.bed,/path/to/genotypes/cohort_eur.bim,/path/to/genotypes/cohort_eur.fam
cohort_afr,AFR,/path/to/genotypes/cohort_afr.bed,/path/to/genotypes/cohort_afr.bim,/path/to/genotypes/cohort_afr.fam
```

| Column     | Description                                                                                                                                           |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`       | Unique stratum identifier without spaces. It names the stratum's output directory and prefixes every file the stratum produces.                       |
| `ancestry` | Ancestry label of the stratum, such as `EUR`, `AFR` or `CSA`. Letters, digits, underscores, dots and dashes only; carried through as `meta.ancestry`. |
| `bed`      | Full path to the PLINK 1 binary genotype file. Relative paths are resolved against the launch directory.                                              |
| `bim`      | Full path to the PLINK 1 variant file. It must share its basename with the `bed` and `fam` files.                                                     |
| `fam`      | Full path to the PLINK 1 sample file. It must share its basename with the `bed` and `bim` files.                                                      |

An [example samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

### Chromosome codes

The QC'd fileset carries the human chromosomes only: 1 to 22, X, Y, XY (the pseudo-autosomal regions) and MT. In the `.bim`, each may be written as plink2 reads it: by number (`23` to `26` for X, Y, XY and MT, zero-padded or not) or by letter (`X`, `Y`, `XY`, `MT` or `M`), in either case, with or without a `chr` prefix, and the pseudo-autosomal regions also as `PAR1` and `PAR2`, the names plink2's `--split-par` gives them. A variant under any other code, such as an alt or random contig of GRCh38 (`7_KI270803v1_alt`, `1_KI270706v1_random`), an unplaced contig (`chrUn_KI270742v1`) or the unknown chromosome `0`, is accepted in the input and listed for exclusion before every filter, so that it reaches no statistic, decision list, ancestry projection or QC'd fileset. The list is published per stratum and its line count is the `variants_contig_removed` column of the summary; the MAF filter and everything after it count only the variants on the standard chromosomes.

### QC thresholds

After the variants on non-standard contigs are excluded (see [Chromosome codes](#chromosome-codes)), the variant filter chain applies four thresholds, each a pipeline parameter: `--maf` (variants below this minor allele frequency are dropped), `--geno` (variants whose missing-call rate exceeds this value are dropped), `--mind` (samples whose missing-call rate, measured over the variants that survive `--geno`, exceeds this value are dropped) and `--hwe` (variants whose Hardy-Weinberg exact-test p-value is below this value are dropped). The decision lists are published beside the statistics they were derived from, and the QC'd fileset is written once, at the end, from the original fileset and those lists. Alongside the `--geno` and `--mind` lists the pipeline records a call-rate ladder from 90 % to 99 %, one row per rate, stating what that rate would have removed; nothing on the ladder is applied.

### Sample checks

The sample checks run on a marker set chosen per stratum by `--sample_qc_marker_set`. In the `study` mode they run on an LD-pruned subset of the stratum's own QC'd variants (`--ld_window_size`, `--ld_step_size`, `--ld_r2` are the `--indep-pairwise` settings) and, for the heterozygosity and relatedness reports, outside the long-range LD regions of `--high_ld_regions` and off the sex chromosomes. In the `shared` mode they run on the harmonised, reference-pruned autosomal markers that the ancestry route builds for the stratum (see [Reference panel](#reference-panel)): no study-side pruning runs, the heterozygosity report is computed on the study and on the reference samples of the stratum's own super-population over those markers with the matched reference allele frequencies as the common basis (`--read-freq`), KING relatedness runs on the same markers, and the sex check runs on every QC-passing chromosome X and Y variant without pruning, because the reference carries no chromosome X. The default, `auto`, chooses `shared` for a stratum with fewer than `--small_n_threshold` samples after the `--mind` removals and `study` otherwise; the mode chosen for each stratum is recorded in `gwasqc_summary.tsv` and in the MultiQC report. `shared` needs the reference panel: with `--skip_ancestry` it is an error, as is a stratum that `auto` would send to `shared`.

`--sample_qc_shared_reference` chooses which reference samples the shared markers are filtered and pruned on. The default, `pooled`, takes the markers the ancestry route pruned on the whole panel, restricted to the autosomes; every `shared` stratum then runs on the same markers. `matched` filters (`--maf`, `--geno`) and prunes the harmonised reference once more for each `shared` stratum, on the reference samples of the stratum's own super-population only, so that a marker monomorphic or in LD only within that population is treated as such. The pooled set is the default until it has been measured on real small strata whose population is under-represented in the panel; `matched` needs at least 50 reference samples in the stratum's super-population, below which plink2 refuses the pruning. The choice is recorded per stratum in the summary column `sample_qc_shared_reference` (`NA` for a stratum in the `study` mode).

The reason for the two modes is sample size. Pairwise r-squared over a few dozen samples has a strongly inflated upper tail, so `--indep-pairwise` on a small stratum discards nearly every variant, and the sex check, heterozygosity and relatedness reports then run on almost nothing: an 11-sample stratum of the legacy cohort kept 0.5 % of its variants and checked sex on 42 chromosome X variants. The shared markers were pruned on the reference, whose sample size is not the stratum's. When a stratum in `study` mode keeps fewer than `--ld_min_retained_fraction` of its QC'd variants after pruning, its summary row and the MultiQC marker-set section carry a note recommending the `shared` mode; nothing is re-decided. plink2 itself refuses `--indep-pairwise`, `--check-sex` and `--het` below 50 samples, where it considers the allele frequencies and LD estimates unreliable; the pipeline lifts those refusals (`--bad-ld` on the study-side pruning, `--bad-freqs` on the sex check and on the `study`-mode heterozygosity report) because the mode is the user's choice and the note is its safety net, while the `shared`-mode heterozygosity report reads the reference frequencies and needs no such override.

> [!NOTE]
> In a small stratum a single missing call is a large fraction of the samples at that variant: with 12 samples one missing genotype is 8.3 % of the calls, so every variant with one missing call exceeds `--geno 0.05` and is dropped, while the sample that misses it is barely affected (`--mind` is a fraction of the variants, not of the samples). Choose `--geno` with the stratum size in mind, at or above `1/n` if a variant should survive one missing call. Likewise the Hardy-Weinberg exact test cannot reach small p-values with a dozen samples, so `--hwe` excludes nothing there.

The sex check splits the chromosome X pseudo-autosomal regions for `--genome_build` and applies four thresholds through plink2 `--check-sex`, as that command's own modifiers: `--sex_check_max_female_xf` and `--sex_check_min_male_xf` bound the chromosome X inbreeding coefficient for a female and a male call, and `--sex_check_max_female_ycount` and `--sex_check_min_male_ycount` bound the number of non-missing chromosome Y calls each call may carry. plink2 makes the call and the pipeline lists its own `PROBLEM` verdicts; nothing is re-decided.

The relatedness table holds the pairs at or above `--king_table_filter`, classifies them on KING's kinship boundaries with `--relatedness_po_ibs0_max` telling parent-offspring from full-sib pairs, and flags individuals `--relatedness_indiv_sd` standard deviations above the cohort mean kinship.

The heterozygosity report is computed against the frequencies of the marker set: the stratum's own in `study` mode, the matched reference's in `shared` mode, where the histogram draws the reference samples' distribution in grey beneath the study's. Every sample check publishes its decision list, but only the missingness removals are applied by default, as in the legacy chain. With `--apply_sample_removals`, the sex mismatches, one member of each duplicate/MZ pair and, unless `--ancestry_remove_mismatched` is switched off, the ancestry mismatches are removed from the QC'd fileset as well; the mean-kinship outliers and the heterozygosity report are never applied.

> [!NOTE]
> The default `--high_ld_regions` asset is GRCh38. A cohort on another build needs both `--genome_build` and a matching region file.

### Reference panel

Ancestry inference needs a labelled reference panel on the same genome build as the cohort, declared by two parameters. `--reference_panel` is a samplesheet of the panel's PLINK 1 filesets, one row per fileset: a single whole-genome fileset is one row, and the per-chromosome 1000 Genomes layout of the legacy pipeline is one row per chromosome. The rows must share their samples and carry disjoint variants, because each is restricted to the variants it shares with a stratum and the restrictions are then concatenated into one reference per stratum.

```csv title="reference_panel.csv"
id,bed,bim,fam
chr1,/path/to/reference/1KG_Phase3.chr1.bed,/path/to/reference/1KG_Phase3.chr1.bim,/path/to/reference/1KG_Phase3.chr1.fam
chr2,/path/to/reference/1KG_Phase3.chr2.bed,/path/to/reference/1KG_Phase3.chr2.bim,/path/to/reference/1KG_Phase3.chr2.fam
```

| Column | Description                                                                                                     |
| ------ | --------------------------------------------------------------------------------------------------------------- |
| `id`   | Unique identifier of the fileset without spaces, such as a chromosome or `all`; the filesets merge in id order. |
| `bed`  | Full path to the PLINK 1 binary genotype file of the fileset.                                                   |
| `bim`  | Full path to the PLINK 1 variant file. It must share its basename with the `bed` and `fam` files.               |
| `fam`  | Full path to the PLINK 1 sample file. It must share its basename with the `bed` and `bim` files.                |

`--reference_pop_data` is a tab-separated table with a header row and the columns `FID`, `IID`, `pop` and `super_pop`, one row per reference sample; every sample of the panel must be listed. The `super_pop` labels are the groups the classifier learns, and the `ancestry` column of the samplesheet is matched against them: a stratum whose label is not one of them has every sample listed as an ancestry mismatch, which is a warning when the list is only published and an error when `--apply_sample_removals` would apply it.

```tsv title="ref_pop.tsv"
FID	IID	pop	super_pop
HG00096	HG00096	GBR	EUR
NA19625	NA19625	ASW	AFR
```

#### Preparing the reference panel

The reference variants are matched to a stratum's QC'd variants by chromosome, position and alleles, not by ID, so a panel named by array probe IDs, by `chr:pos:ref:alt` or by another dbSNP release still meets the study at every shared site; where the IDs differ the reference variant is renamed to the study's ID in the merged reference. The matching makes three demands of the panel that the pipeline does not repair:

- **The same genome build as the cohort.** `--genome_build` declares the study's build and the pipeline does not lift anything over. When more than half of the variant IDs a stratum shares with the panel sit at another chromosome or position, the run stops with a message naming the counts and asking for the panel to be lifted over beforehand; below that the disagreeing variants are classed `position_mismatch` and dropped.
- **Unique reference IDs.** A reference ID that occurs more than once in the panel cannot be addressed by plink2's `--extract`, so a study variant matched to it is classed `duplicate_id` and dropped. Positions shared by several reference variants are resolved by alleles; where that leaves more than one candidate, or one reference variant claimed by several study variants, the site is classed `duplicate_position` and dropped.
- **Recognisable chromosome codes.** A `chr` prefix is ignored and `X`, `Y`, `XY` and `MT` (or `M`) are read as `23` to `26`, so `chr7` in the panel meets `7` in the study; any other naming is compared as written. A panel may carry variants on alt, random or other contigs: they are read, and never matched, because the stratum's own variants on such contigs were excluded before the harmonisation.

Every stratum's harmonisation table states, per QC'd study variant, the reference variant it matched, its class and whether the match rested on ID and position or on position alone (see [Outputs](output.md#ancestry)).

> [!NOTE]
> A panel can be sufficient for the ancestry projection and still too sparse for the `shared` marker set. In the measurements of the predecessor pipeline, the gnomAD v3.1.2 HGDP + 1000 Genomes genotype panel cut the shared pruned markers of a Middle Eastern stratum from 388 to 31, while remaining usable for the components. No reference panel used so far has carried non-PAR chromosome X, so the sex check cannot be anchored on the reference: the `shared`-mode sex check runs on the study's own chromosome X and Y variants.

#### How the reference is processed

The reference is restricted to the variants it shares with each stratum, harmonised onto the stratum's strand (A/T and C/G pairs are dropped), filtered with the pipeline's `--maf` and `--geno` (no Hardy-Weinberg filter, which on a pooled multi-population panel measures population structure) and pruned with `--ancestry_ld_window_size`, `--ancestry_ld_step_size` and `--ancestry_ld_r2` outside the long-range LD regions, and decomposed into `--ancestry_n_pcs` components; reference and study samples are projected onto them with plink2's documented `--score` recipe. A study sample is assigned the super-population of its largest posterior probability when that reaches `--ancestry_prob_threshold`; `--ancestry_sd_filter`, off by default, additionally unassigns a sample more than that many standard deviations from its group's reference mean on any component. `--skip_ancestry` leaves the stage out, and the two reference parameters are then not needed.

> [!NOTE]
> plink2 refuses `--pca` on fewer than 50 reference samples and recommends its `approx` modifier on panels far beyond 5000 samples; the modifier reaches the decomposition through `ext.args` of `PLINK2_PCAWTS` in a custom config.

### Threshold semantics

The boundaries are not uniform across the pipeline, so each one is stated here exactly as it is implemented. A variant is kept by `--maf` when its minor allele frequency is at or above the threshold, as plink2's own `--maf` keeps it. A variant is listed by `--geno`, and a sample by `--mind`, only when its missing-call rate is **strictly greater than** the threshold, which is again what plink2's `--geno` and `--mind` do; every rung of the call-rate ladder uses the same strict comparison. A variant is listed by `--hwe` only when its exact-test p-value is **strictly below** the threshold.

The KING degree lower bounds are **inclusive**: a pair is `duplicate_or_mz` at kinship `>= 0.354`, first-degree at `>= 0.177`, `second_degree` at `>= 0.0884` and `third_degree` at `>= 0.0442`. Because the default `--king_table_filter` is that last bound, a pair reported at exactly the filter value is classified third-degree rather than falling outside every class. A first-degree pair is `parent_offspring` when its IBS0 proportion is at or below `--relatedness_po_ibs0_max` and `full_sibling` otherwise. An individual is a mean-kinship outlier only when its mean kinship is **strictly above** the cohort mean plus `--relatedness_indiv_sd` standard deviations.

A study sample is assigned its most probable super-population when that posterior is **at or above** `--ancestry_prob_threshold`, and is unassigned below it. The optional centroid rule unassigns an already-assigned sample only when its distance from its group's reference mean on some component is **strictly greater than** `--ancestry_sd_filter` standard deviations; with the parameter unset the rule does not run.

> [!WARNING]
> Do not add the `midp` modifier to the `ext.args2` of `PLINK2_HARDY`, the seam through which `--hardy` modifiers reach plink2 and which the pipeline leaves empty. plink2 does not add a column for the mid-p adjustment: it **renames** the report's `P` column to `MIDP`. The Hardy-Weinberg decision module addresses that column by name, so with `midp` set it stops with a message naming the missing column rather than writing an empty exclusion list and silently excluding nothing.

### Report

The run root holds `gwasqc_summary.tsv`, one row per stratum with the samples and variants that entered, what every stage removed or listed at its threshold, the sex, heterozygosity, relatedness and ancestry counts, what `--apply_sample_removals` did or would do, and what left. The MultiQC report under `multiqc/` opens with the same table and continues with one section per QC stage: a table across strata, then the review figures of each stratum. Every number in both is read from a published list or table, so a count in the report can be traced to the file it was counted from; no threshold has to be re-entered to read it, because the thresholds are recorded in the summary. The report takes no parameters of its own beyond the MultiQC options (`--multiqc_title`, `--multiqc_config`, `--multiqc_logo`, `--multiqc_methods_description`); a custom MultiQC config extends the pipeline's `assets/multiqc_config.yml`, which orders the sections.

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run nf-core/gwasqc --input ./samplesheet.csv --reference_panel ./reference_panel.csv --reference_pop_data ./ref_pop.tsv --outdir ./results -profile docker
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles. `--input` and `--outdir` are the only parameters required in every run; `--reference_panel` and `--reference_pop_data` are required unless you pass `--skip_ancestry`. Set `--email` to receive a summary message when the run finishes, and `--email_on_fail` to receive one only when it does not.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/running/run-pipelines#configuring-pipelines), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run nf-core/gwasqc -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
input: './samplesheet.csv'
outdir: './results/'
<...>
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull nf-core/gwasqc
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [nf-core/gwasqc releases page](https://github.com/nf-core/gwasqc/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `test_alt_contig`
  - The `test` profile with one fixture stratum beside a copy of it that also carries variants on GRCh38 alt and random contigs, against a reference panel that carries the same; checks that those variants are listed and excluded and that nothing else changes
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://charliecloud.io/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow ` 24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#set-max-resources) and [customise process resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#customize-process-resources) section of the nf-core website.

### Custom containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#update-tool-versions) section of the nf-core website.

### Custom tool arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#modifying-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
