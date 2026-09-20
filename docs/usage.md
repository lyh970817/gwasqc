# nf-core/gwasqc: Usage

## :warning: Please read this documentation on the nf-core website: [https://nf-co.re/gwasqc/usage](https://nf-co.re/gwasqc/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

<!-- TODO nf-core: Add documentation about anything specific to running your pipeline. For general topics, please point to (and add to) the main nf-core website. -->

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

### QC thresholds

The variant filter chain applies four thresholds, each a pipeline parameter: `--maf` (variants below this minor allele frequency are dropped), `--geno` (variants whose missing-call rate exceeds this value are dropped), `--mind` (samples whose missing-call rate, measured over the variants that survive `--geno`, exceeds this value are dropped) and `--hwe` (variants whose Hardy-Weinberg exact-test p-value is below this value are dropped). Every comparison is strict, as in plink2 itself. The decision lists are published beside the statistics they were derived from, and the QC'd fileset is written once, at the end, from the original fileset and those lists.

### Sample checks

The sample checks run on an LD-pruned subset of the QC'd variants (`--ld_window_size`, `--ld_step_size`, `--ld_r2` are the `--indep-pairwise` settings) and, for the heterozygosity and relatedness reports, outside the long-range LD regions of `--high_ld_regions` and off the sex chromosomes. The sex check splits the chromosome X pseudo-autosomal regions for `--genome_build` and applies the four `--sex_check_*` thresholds through plink2 `--check-sex`; the relatedness table holds the pairs at or above `--king_table_filter`, classifies them on KING's kinship boundaries with `--relatedness_po_ibs0_max` telling parent-offspring from full-sib pairs, and flags individuals `--relatedness_indiv_sd` standard deviations above the cohort mean kinship.

Every sample check publishes its decision list, but only the missingness removals are applied by default, as in the legacy chain. With `--apply_sample_removals`, the sex mismatches, one member of each duplicate/MZ pair and, unless `--ancestry_remove_mismatched` is switched off, the ancestry mismatches are removed from the QC'd fileset as well; the mean-kinship outliers and the heterozygosity report are never applied.

> [!NOTE]
> The default `--high_ld_regions` asset is GRCh38. A cohort on another build needs both `--genome_build` and a matching region file.

### Reference panel

Ancestry inference needs a labelled reference panel on the same genome build as the cohort, declared by two parameters. `--reference_panel` is a samplesheet of the panel's PLINK 1 filesets, one row per fileset: a single whole-genome fileset is one row, and the per-chromosome 1000 Genomes layout of the legacy pipeline is one row per chromosome. The rows must share their samples and carry disjoint variants, because each is intersected with a stratum's QC'd variants and the intersects are then concatenated into one reference per stratum.

```csv title="reference_panel.csv"
id,bed,bim,fam
chr1,/path/to/reference/1KG_Phase3.chr1.bed,/path/to/reference/1KG_Phase3.chr1.bim,/path/to/reference/1KG_Phase3.chr1.fam
chr2,/path/to/reference/1KG_Phase3.chr2.bed,/path/to/reference/1KG_Phase3.chr2.bim,/path/to/reference/1KG_Phase3.chr2.fam
```

| Column | Description                                                                                                    |
| ------ | -------------------------------------------------------------------------------------------------------------- |
| `id`   | Unique identifier of the fileset without spaces, such as a chromosome or `all`; the filesets merge in id order. |
| `bed`  | Full path to the PLINK 1 binary genotype file of the fileset.                                                  |
| `bim`  | Full path to the PLINK 1 variant file. It must share its basename with the `bed` and `fam` files.              |
| `fam`  | Full path to the PLINK 1 sample file. It must share its basename with the `bed` and `bim` files.               |

`--reference_pop_data` is a tab-separated table with a header row and the columns `FID`, `IID`, `pop` and `super_pop`, one row per reference sample; every sample of the panel must be listed. The `super_pop` labels are the groups the classifier learns, and the `ancestry` column of the samplesheet is matched against them: a stratum whose label is not one of them has every sample listed as an ancestry mismatch, which is a warning when the list is only published and an error when `--apply_sample_removals` would apply it.

```tsv title="ref_pop.tsv"
FID	IID	pop	super_pop
HG00096	HG00096	GBR	EUR
NA19625	NA19625	ASW	AFR
```

The reference is restricted to each stratum's QC'd variants with the pipeline's `--maf` and `--geno` (no Hardy-Weinberg filter, which on a pooled multi-population panel measures population structure), harmonised onto the stratum's strand (A/T and C/G pairs are dropped), pruned with `--ancestry_ld_window_size`, `--ancestry_ld_step_size` and `--ancestry_ld_r2` outside the long-range LD regions, and decomposed into `--ancestry_n_pcs` components; reference and study samples are projected onto them with plink2's documented `--score` recipe. A study sample is assigned the super-population of its largest posterior probability when that reaches `--ancestry_prob_threshold`; `--ancestry_sd_filter`, off by default, additionally unassigns a sample more than that many standard deviations from its group's reference mean on any component. `--skip_ancestry` leaves the stage out, and the two reference parameters are then not needed.

> [!NOTE]
> plink2 refuses `--pca` on fewer than 50 reference samples and recommends its `approx` modifier on panels far beyond 5000 samples; the modifier reaches the decomposition through `ext.args` of `PLINK2_PCAWTS` in a custom config.

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run nf-core/gwasqc --input ./samplesheet.csv --outdir ./results  -profile docker
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

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

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#update-tool-versions) section of the nf-core website.

### Custom Tool Arguments

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
