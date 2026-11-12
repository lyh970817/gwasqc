# Genotype-QC component contracts

These repository-specific contracts refine the generic nf-core component standards for the genotype quality-control
domain this pipeline implements: PLINK 1 and PLINK 2 filesets, the plink2 filter-list block, the statistics tables
the pipeline parses, the decision lists it derives, the review figures it draws, and the reference-panel assets the
ancestry route reads.

This topic owns **shapes**: tuple order, member roles, optionality, identity, file formats, and bundle boundaries.
[`pipeline-architecture.md`](pipeline-architecture.md) owns the **route policy** — which list reaches which flag,
in which order, and why. Where a rule here restates a mechanism, it does so because a component interface depends
on it, not to duplicate the route.

Evidence for these contracts is this repository's own implementing code, cited per rule, not the reference
pipelines; the reference-pipeline evidence markers described in `CODING_STANDARDS.md` therefore do not appear here.
Severity follows the same file: **[MUST]** is a review finding, **[SHOULD]** is a strong default whose unexplained
deviation is flagged.

## Stratum and reference identity

- **[MUST]** A stratum's metadata map is exactly `[ id, ancestry ]`, both declared by the samplesheet row and
  neither derived (`assets/schema_input.json`). `meta.id` is unique across the samplesheet, carries no
  whitespace, and is the output prefix of every file the stratum produces. `meta.ancestry` is a scientific label,
  not a routing key: only `ancestry_assign` consumes it, to decide which assigned samples count as mismatches
  (`modules/local/ancestry_assign/main.nf:36`).
- **[MUST]** A reference-panel fileset's metadata map is exactly `[ id ]` (`assets/schema_reference.json`). A
  reference fileset carries no ancestry: the population table, not the samplesheet, labels reference samples.
- **[MUST]** A stratum's `ancestry` is validated at ingress against the super-population vocabulary read from the
  population table, fatally only when the mismatch list would actually be applied and as a warning otherwise
  (`subworkflows/local/utils_nfcore_gwasqc_pipeline/main.nf:119`, `:208-217`). Downstream stages consume the
  label without revalidating it.
- **[MUST]** One further key is decided by the route rather than declared: `sample_qc_marker_set`, `study` or
  `shared`, is added to the stratum's map by the workflow once the mind list exists, because the sample QC
  chain branches on it per stratum, the plink2 configuration reads it, and the report records it
  (`workflows/gwasqc.nf`, the marker-set decision; `subworkflows/local/plink_sample_qc_lists/main.nf`, the
  `branch`; `conf/modules/plink2.config`, `PLINK2_HET`; `modules/local/stratum_report/templates/stratum_report.sh`).
  It is not a scatter key: it reaches the published summary deliberately, as the `sample_qc_marker_set` column.
  A module that reads it says so in its `meta.yml` expected keys; a plink2 atom never reads it.
- **[MUST]** Metadata keys beyond these are scatter-local: `call_rate` for one rung of the call-rate ladder
  (`subworkflows/local/plink_qc_filter_lists/main.nf:86`) and `stratum`, `reference`, `n_reference` for one
  stratum-by-fileset intersect (`subworkflows/local/ancestry_inference/main.nf:53`). A scatter key is collision-free,
  is used only to keep concurrent runs of one process apart and to size its `groupKey`, and is dropped at the
  gather by restoring the stratum's own map through a join on `meta.id`
  (`subworkflows/local/plink_qc_filter_lists/main.nf:105-106`, `subworkflows/local/ancestry_inference/main.nf:85`).
  No scatter key reaches a published product.
- **[MUST]** An identity a scatter key distinguishes lives in the staged basename through `ext.prefix`, not in the
  module: `${meta.id}.ladder${meta.call_rate}` (`conf/modules/plink2.config:47`) is configuration, and the module
  still derives `prefix` from `meta.id` alone.

## The fileset tuple

- **[MUST]** One fileset is `tuple val(meta), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file)`,
  in that semantic primary/variant/sample order. This single union covers both formats: PLINK 1 binds bed/bim/fam
  and PLINK 2 binds pgen/pvar/psam to the same three roles. Do not split the formats into separate
  metadata-bearing roles; they occupy one identity and one native CLI role
  (`modules/local/plink2/missing/main.nf:11` and every sibling atom).
- **[MUST]** The staged primary-genotype extension selects the native flag, with PGEN as the only special case:

  ```nextflow
  def mode = plink_genotype_file.extension == 'pgen' ? '--pfile' : '--bfile'
  ```

  Every plink2 atom does this identically (`modules/local/plink2/missing/main.nf:24`). A caller therefore passes a
  PGEN fileset through the same interface unconverted, and nothing in the pipeline converts between the formats.

- **[MUST]** The three members share one basename, because plink2 addresses a fileset by a single prefix that the
  module derives from the genotype member (`plink_genotype_file.baseName`). Document the requirement in `meta.yml`
  and let ingress reject a violating samplesheet row
  (`subworkflows/local/utils_nfcore_gwasqc_pipeline/main.nf:195-201`); never repair a mismatch inside a module
  with `stageAs`, a rename, a symlink, or a basename-equality check.
- **[MUST]** `stageAs: 'input/*'` on the fileset members is reserved for a genuine work-directory collision, and
  the module states which one in a comment: an atom that writes the extensions it reads
  (`modules/local/plink2/makebed/main.nf:11-14`, `modules/local/plink2/pmergelist/main.nf:11-13`) or an atom whose
  second input set may carry the first's basename (`modules/local/ancestry_harmonise/main.nf:11-14`). When the
  members are staged into a subfolder the prefix becomes
  `plink_genotype_file.resolveSibling(plink_genotype_file.baseName)`
  (`modules/local/plink2/makebed/main.nf:27`), and the bare `baseName` otherwise.
- **[MUST]** The many-fileset form pluralises the same three roles and keeps the order:
  `path(plink_genotype_files)`, `path(plink_variant_files)`, `path(plink_sample_files)`. The atom pairs the members
  by basename, orders the filesets deterministically, writes the native merge list itself, and falls back to
  `--bfile`/`--pfile` for a single fileset because plink2 refuses `--pmerge-list` below two
  (`modules/local/plink2/pmergelist/main.nf:25-38`). The caller supplies the three lists in one order and does not
  also supply a count.
- **[MUST]** A module that reads only one member of a fileset takes only that member, not the whole fileset, and
  selects its parser from that member's extension (`modules/local/highld_exclude/main.nf:11`, `:23`). Do not stage
  a genotype file a script never opens.
- **[SHOULD]** An output fileset is one channel, because its members always travel together:
  `emit: bed` carries bed/bim/fam (`modules/local/plink2/makebed/main.nf:17`) and `emit: pgen` carries
  pgen/pvar/psam (`modules/local/plink2/pmergelist/main.nf:16`). The run log is a separate channel and is not
  published.

## The filter-list block

- **[MUST]** Every plink2 atom exposes plink2's filter block as exactly four path members, in this order,
  immediately after the three fileset members and before any role-specific file:

  ```nextflow
  path(extract), path(exclude), path(keep), path(remove)
  ```

  The order is fixed across all eleven atoms and is not abbreviated when a route uses only some of the slots
  (`modules/local/plink2/missing/main.nf:11`).

- **[MUST]** A caller passes `[]` for an unused slot and never omits it. A stage that applies no list at all still
  fills all four (`subworkflows/local/plink_qc_filter_lists/main.nf:37`).
- **[MUST]** A slot accepts one file or several. Nextflow renders a collection bound to a `path` input
  blank-separated, and plink2 concatenates the files given to one flag, so several files in one slot are that
  flag's union: `--extract` keeps the union of its keep-lists, `--exclude` drops the union of its exclusion lists,
  `--keep` keeps the union of its sample lists, and `--remove` drops the union of its removal lists. The
  composition, not the module, assembles the union — the exclusion slot carries the geno and HWE lists together
  (`workflows/gwasqc.nf:142`). A module never concatenates, deduplicates, or intersects list files.
- **[MUST]** Each slot becomes one presence-driven CLI fragment and nothing else:

  ```nextflow
  def extract_fragment = extract ? "--extract ${extract}" : ''
  ```

  The four fragments appear in slot order in the command, before `args`
  (`modules/local/plink2/missing/main.nf:27-30`, `:37-41`). Both the present and the absent path are covered by
  tests.

- **[MUST]** A threshold is never a filter-list slot and a filter list is never a threshold. A variant-missingness
  or Hardy-Weinberg threshold reaches plink2 only after a pipeline-owned module has turned it into a list; the
  native `--geno`, `--mind`, `--maf`, and `--hwe` flags reach plink2 only through `ext.args`.
- **[MUST]** A role-specific file follows the block rather than interrupting it: `path(update_name),
path(update_alleles)` (`modules/local/plink2/pmergelist/main.nf:13`), in the order plink2 applies them, `path(score_file), path(read_freq)`
  (`modules/local/plink2/score/main.nf:11`) and `path(read_freq)` (`modules/local/plink2/het/main.nf`). Each
  gets its own presence-driven fragment, and a mandatory one, such as the score file, gets no presence check.
- **[SHOULD]** The `keep` slot stays `[]` throughout this pipeline: every sample decision the QC chain makes is a
  removal list, so the gate is one union at one slot (`workflows/gwasqc.nf:142`). The slot exists because the
  contract is plink2's filter block, not this pipeline's current route, and an atom that dropped it would stop
  being portable.

## Scalars, thresholds, and extension seams

- **[MUST]** A value the native command always requires is an explicit input after the tuple:
  `val window_size, val step_size, val r2` on `--indep-pairwise`
  (`modules/local/plink2/indeppairwise/main.nf:12-14`) and `val n_pcs` on `--pca`
  (`modules/local/plink2/pcawts/main.nf:12`). It is process-global because it is one setting for the run, and it
  never hides in metadata or an `ext.args` default.
- **[MUST]** A scientific threshold never appears in a plink2 atom's interface. It reaches the atom only as native
  optional behaviour through `task.ext.args`, set in `conf/modules/plink2.config`: `--maf` (`:19`), the
  `--check-sex` thresholds and `--split-par` (`:70-79`), `--king-table-filter` (`:96`), the reference-side `--maf`
  and `--geno` (`:125`), and the `--score` column selection (`:159`).
- **[MUST]** `task.ext.args2` exists only where plink2 reads modifiers that must directly follow the command flag,
  and the module says so in a comment at the declaration: `--check-sex`
  (`modules/local/plink2/checksex/main.nf:23-25`), `--hardy` (`modules/local/plink2/hardy/main.nf`), `--pca`
  (`modules/local/plink2/pcawts/main.nf:27-29`), and `--score` (`modules/local/plink2/score/main.nf:24-26`).
  Every other flag travels in `args`. An extension seam never replaces a mandatory interface value.
- **[MUST]** A pipeline-owned decision module takes its threshold as an explicit input, because the threshold is
  the module's policy rather than a tool option. It is tuple-local when one stratum must be listed at several
  thresholds, as the call-rate ladder requires (`modules/local/geno_decisions/main.nf:11-13`), and process-global
  when the run has one value (`modules/local/hwe_decisions/main.nf:12`,
  `modules/local/relatedness_decisions/main.nf:12-13`, `modules/local/ancestry_assign/main.nf:13-14`).
- **[MUST]** Script locals are ordered by dependency: `args`, a genuine `args2`, the staged input mode and prefix,
  the output `prefix`, the four list fragments in slot order, then any role fragment near its consumption. A local
  is defined only when the command or an output declaration consumes it.
- **[MUST]** Assign `prefix` without `def`, because the `output:` declarations resolve it, and derive it as
  `task.ext.prefix ?: "${meta.id}"` in both the script and the stub. A template-backed module assigns every other
  variable its template reads the same way and says so in a comment
  (`modules/local/hwe_decisions/main.nf:24-26`, `modules/local/missingness_ladder/main.nf:25-28`).

## The shared-marker list

The `shared` marker-set mode of the sample checks consumes four products of the ancestry route as inputs
(`subworkflows/local/ancestry_inference/main.nf`, emits `shared_markers` and `reference_keep`), and their shapes
are part of that route's contract.

- **[MUST]** The shared-marker list is a `prune.in` over the harmonised merged reference, with the long-range LD
  regions and every non-autosomal variant excluded before pruning and the reference-side `--maf` and `--geno`
  applied in the pruning run itself, chosen by `sample_qc_shared_reference`: under `pooled`, the route's own
  `PLINK2_INDEPPAIRWISE_REFERENCE` list over every reference sample; under `matched`,
  `PLINK2_INDEPPAIRWISE_MATCHED` over the reference samples of the stratum's super-population (`--keep`),
  except that a super-population of fewer than 50 reference samples takes the pooled list. Its
  IDs are the study's, because the merged reference was renamed to them. It is a variant list in the format
  above and reaches a sample-QC atom only through `--extract`, so it is interchangeable with the study-side
  `prune.in` at that slot.
- **[MUST]** The merged reference fileset that accompanies it is the one the list was pruned on, renamed to the
  study's IDs by `--update-name` and flipped onto the study's strand by `--update-alleles`, so that its IDs and
  alleles agree with the study's and a frequency table computed on it applies to the study fileset without
  further harmonisation. It is unfiltered: every filter is a run-time argument of a statistics run on it.
- **[MUST]** The keep list of the stratum's super-population is built once by the ancestry route
  (`ANCESTRY_REFERENCE_KEEP`) and serves the matched pruning, the frequency table and the reference report
  alike, so the three cannot disagree on the samples.
- **[MUST]** The frequency basis of the `shared`-mode heterozygosity report is one `--freq` table of the reference
  samples of the stratum's `ancestry` super-population over exactly the shared markers
  (`modules/local/ancestry_reference_keep/main.nf` selects the samples from the population table,
  `modules/local/plink2/freq/main.nf` writes the table with the list under `--extract` and the samples under
  `--keep`), read by both `--het` runs through `--read-freq`. The table covers every extracted marker, because a
  marker absent from it silently falls back to the sample's own frequency (verified on 2.0.0a.6.9), and a
  pooled panel is the wrong basis: its frequencies inflate F by the panel's differentiation (measured +0.10 on
  the fixture's five-population panel against +0.00 on the matched samples).
- **[MUST]** The reference report of that mode is `--het` of the same samples over the same markers and the same
  table, so that the two reports differ only in their samples; it is optional on `heterozygosity_plots`, whose
  histogram data then carries a `source` column with both sources binned over one range
  (`modules/local/heterozygosity_plots/templates/heterozygosity_plots.R`).
- **[MUST]** The list, the keep list, the frequency table and the reference report exist only for the strata in
  `shared` mode, and the study-side pruning lists only for those in `study` mode. A consumer that needs one
  of them for every stratum joins with a remainder and substitutes `[]` for the mode that does not produce
  it (`workflows/gwasqc.nf`, the report inputs); a consumer specific to one mode joins strictly within that
  mode's branch (`subworkflows/local/plink_sample_qc_lists/main.nf`).

## Decision-list and table file formats

The pipeline writes two kinds of file, and the difference is a contract, not a style: **a list is what a native
flag reads**, so its format is that flag's format; **a table is what a reviewer reads**, so it is a TSV with a
header. Never merge the two roles into one file.

- **[MUST]** A variant list is one variant ID per line, no header, no quoting
  (`modules/local/geno_decisions/templates/geno_decisions.R:33`,
  `modules/local/hwe_decisions/templates/hwe_decisions.R`,
  `modules/local/ancestry_harmonise/templates/ancestry_harmonise.R:218-219`,
  `modules/local/highld_exclude/main.nf:51`, `modules/local/contig_exclude/main.nf`). This is also what plink2 itself writes for `--write-snplist` and
  `--indep-pairwise`, so a pipeline-owned list and a plink2-produced list are interchangeable in one filter slot.
- **[MUST]** A sample list is one `FID IID` pair per line, **blank-separated**, no header, with a documented
  fallback to a bare `IID` when the source report carries no `FID` column
  (`modules/local/mind_decisions/templates/mind_decisions.R:37-44`,
  `modules/local/sex_check_decisions/templates/sex_check_decisions.R:35`,
  `modules/local/relatedness_decisions/templates/relatedness_decisions.R:108`, `:121`,
  `modules/local/ancestry_assign/templates/ancestry_assign.R:130-134`). Tables in this pipeline are
  tab-separated and lists are blank-separated; state the separator in `meta.yml` rather than leaving it to be
  inferred from a table's.
- **[MUST]** A list written for any other native flag follows that flag's own format verbatim rather than being
  normalised. The allele-update list is the PLINK 1.x five-column `--update-alleles` form — the study ID, the two
  reference alleles, then their complements in the same order, tab-separated, no header — and the rename list the
  default two-column `--update-name` form — old (reference) ID, new (study) ID, tab-separated, no header; each is
  consumed only through its flag, in one run, with the allele update keyed by the new IDs because plink2 renames
  first (`modules/local/ancestry_harmonise/templates/ancestry_harmonise.R:220-228`,
  `modules/local/plink2/pmergelist/main.nf:43-46`).
- **[MUST]** A list is always written, even when it selects nothing, so the channel carries one item per stratum
  and no downstream join needs `remainder`. An empty list is a zero-byte file, never a header-only file and never
  an absent output. Every list-writing template is arranged so the zero-selection case still produces the file
  (`modules/local/highld_exclude/main.nf:51` writes by shell redirection; the R templates write a zero-length
  vector).
- **[MUST]** A decision module emits the list it owns on its own named channel, named for the decision rather than
  for the flag that will consume it: `variant_exclude`, `sample_remove`. The caller decides which slot it reaches,
  which is what lets a list be published without being applied.
- **[MUST]** A table is tab-separated with a header, written with quoting disabled, and is a separate output from
  any list derived from it: the sex-check mismatch table beside the sex removal list
  (`modules/local/sex_check_decisions/main.nf:14-15`), the relatedness pair and individual tables beside the
  duplicate removal list and the mean-kinship outlier list
  (`modules/local/relatedness_decisions/main.nf:16-19`), the harmonisation table and its class summary beside the
  harmonised snplist, the reference extract list, the rename list and the allele-update list
  (`modules/local/ancestry_harmonise/main.nf:18-23`), and the
  assignment, summary, and model tables beside the per-group keep lists and the mismatch removal list
  (`modules/local/ancestry_assign/main.nf:17-21`).
- **[MUST]** A table that classifies a native report's rows passes the report's own columns through unchanged and
  appends its own, so a reviewer can align the two: the mismatch table is the report's columns for the `PROBLEM`
  rows (`modules/local/sex_check_decisions/templates/sex_check_decisions.R:33-34`) and the relatedness pair table
  is the whole kinship table plus `DEGREE` and `RELATIONSHIP`. Consequently such a table's column set is not
  fixed by the pipeline, and its stub derives the header from the report it is given rather than hardcoding
  one (`modules/local/sex_check_decisions/main.nf` and `modules/local/relatedness_decisions/main.nf`, stub
  blocks).
- **[MUST]** A table the pipeline defines itself has a fixed header declared identically in the template, the
  module's stub, and `meta.yml`. A summary table enumerates every category, including the ones with a zero count,
  in one documented order, so the table's shape does not depend on the data
  (`modules/local/ancestry_harmonise/templates/ancestry_harmonise.R:202`, `:247-255`).
- **[MUST]** A per-group output file whose name contains a data value documents which value set generates it and
  in what order, because the caller's `path(...)` glob depends on it: the ancestry keep lists are one file per
  super-population observed among the scored, labelled reference samples, in sorted order, with an empty file for
  a group to which no study sample was assigned and no file for the unassigned
  (`modules/local/ancestry_assign/templates/ancestry_assign.R:83-84`, `:131-133`). The glob output is
  `optional: true`, because zero groups is a legitimate match count, and the stub derives the same set, and the
  per-group columns of the assignment table, from the population table and score header it is given
  (`modules/local/ancestry_assign/main.nf`, stub block).

## Threshold semantics

- **[MUST]** A decision module's comparison against its threshold is documented in `meta.yml` with its exact
  boundary, because the boundary is policy and is not uniform across the pipeline. The live set is: strict `>` for
  the variant- and sample-missingness rates and the call-rate ladder
  (`modules/local/geno_decisions/templates/geno_decisions.R:33`,
  `modules/local/mind_decisions/templates/mind_decisions.R:38`,
  `modules/local/missingness_ladder/templates/missingness_ladder.R:37-39`), which matches plink2's own `--geno`
  and `--mind`; strict `<` for the Hardy-Weinberg p-value floor
  (`modules/local/hwe_decisions/templates/hwe_decisions.R`); inclusive `>=` for each KING degree lower bound
  (0.354, 0.177, 0.0884, 0.0442), as KING's inference table gives the degrees as closed intervals from
  2^-(d+1.5), and strict `>` for the mean-kinship outlier rule
  (`modules/local/relatedness_decisions/templates/relatedness_decisions.R`); inclusive `<=` for the
  parent-offspring IBS0 bound; inclusive `>=` for the ancestry posterior threshold
  (`modules/local/ancestry_assign/templates/ancestry_assign.R:100`); and strict `>` for the centroid rule
  (`:113-117`).
- **[MUST]** Where a pipeline-owned boundary sits at the same value as a plink2 flag's boundary, the two must
  agree or the disagreement must be recorded, because a row plink2 reports at exactly its own boundary then falls
  outside the module's class. The live instance is `--king-table-filter`, which plink2 applies inclusively at
  the default third-degree bound: the inclusive KING bounds above are what keep a pair reported at exactly the
  filter value third-degree rather than unrelated, and a test holds the pair at the bound
  (`modules/local/relatedness_decisions/tests/main.nf.test`, the bare ID1/ID2 case).
- **[MUST]** A rule that can unassign or exclude a record names itself in the output, so every reported count is
  attributable: the assignment table carries a `STATUS` per sample and the summary table carries the `RULE` text
  that produced each row (`modules/local/ancestry_assign/templates/ancestry_assign.R:99-117`, `:139-150`).
- **[MUST]** A missing required column is a hard failure, not an empty result. A template that indexes a report
  by a name that is absent must `stop()` with a message naming the columns it needs and the ones it found, as
  every decision and plot template does
  (`modules/local/geno_decisions/templates/geno_decisions.R`, `modules/local/mind_decisions/templates/mind_decisions.R`,
  `modules/local/hwe_decisions/templates/hwe_decisions.R`,
  `modules/local/missingness_ladder/templates/missingness_ladder.R`,
  `modules/local/relatedness_decisions/templates/relatedness_decisions.R`,
  `modules/local/sex_check_decisions/templates/sex_check_decisions.R:27-29`,
  `modules/local/heterozygosity_plots/templates/heterozygosity_plots.R:34-39`,
  `modules/local/ancestry_assign/templates/ancestry_assign.R:56-58`, `:67-69`, `:74-76`), and each module's
  tests hold one case that asserts the failure. Silently writing an empty decision list with exit status 0 is a
  review finding. _(raised from SHOULD on 2026-09-21, when the last base-R templates gained their guards)_

## Statistics table contracts

- **[MUST]** A plink2 statistics table is consumed as plink2 writes it: tab-separated, one header line, with
  plink2's leading `#` on the first column name only. A consumer strips that `#` from the first name, keeps every
  other name verbatim, and addresses columns **by name, never by position**
  (`modules/local/geno_decisions/templates/geno_decisions.R:17-29` for the base-R idiom,
  `modules/local/sex_check_decisions/templates/sex_check_decisions.R:25-26` for the `data.table` idiom). Do not
  reformat, re-header, or normalise a native report before a consumer reads it.
- **[MUST]** Addressing by name is load-bearing rather than stylistic, because several of these reports have no
  fixed column count: `.smiss` gains per-phenotype columns when a phenotype is loaded, `.sexcheck` gains and
  loses columns with its colset and with the presence of `FID`/`SID`, and a `.sscore` carries one column per
  scored column set. A test asserts such a header with a containment check, not equality
  (`modules/local/plink2/missing/tests/main.nf.test:39`).
- **[MUST]** Every column a module reads must be one the pipeline actually configures plink2 to write, and the
  dependency is recorded at both ends. The live instances are:
  - the chromosome-Y call count and rate of the sex-check report, which exist only because `cols=+ycount` is in
    that process's `ext.args2` (`conf/modules/plink2.config:77`);
  - the sex-check `F` column and the heterozygosity `F` column, which exist only because the input still carries
    chromosome X, which is why pruning runs genome-wide in the `study` mode and the `shared` mode extracts the
    unpruned QC'd set for the sex check rather than the autosomal shared list
    (`modules/local/sex_check_decisions/templates/sex_check_decisions.R:27-29`,
    `modules/local/heterozygosity_plots/templates/heterozygosity_plots.R:37-39`);
  - the three plink2 statistics that refuse a fileset below 50 samples, `--indep-pairwise`, `--check-sex` and
    `--het`, which run on such a stratum only because `conf/modules/plink2.config` lifts the refusal with
    `--bad-ld` and `--bad-freqs` where the marker-set mode makes the stratum's own estimates the user's choice,
    and because `--read-freq` of a covering table lifts it for `--het` on its own (verified on 2.0.0a.6.9 with
    the 12-sample fixture stratum);
  - the Hardy-Weinberg `P` column, which plink2 _renames_ to `MIDP` under a `midp` modifier rather than adding a
    column, so that modifier must stay out of `PLINK2_HARDY`'s `ext.args2`, the seam through which `--hardy`
    modifiers reach plink2 and which the pipeline leaves empty: the atom surfaces the report as plink2 writes it
    and a test asserts the rename (`modules/local/plink2/hardy/tests/main.nf.test`, the `midp` case), and
    `hwe_decisions` stops on the missing `P` rather than excluding nothing
    (`modules/local/hwe_decisions/templates/hwe_decisions.R`, `modules/local/hwe_decisions/tests/main.nf.test`);
  - the allele-weight column positions the `--score` arguments address, which hold only because
    `vcols=chrom,ref,alt` suppresses the provisional-reference column; without it plink2 shifts the weighted
    allele and the weights one column right and the projection silently uses the wrong ones
    (`conf/modules/plink2.config:146`, `:159-160`).
- **[MUST]** The tables the pipeline parses, the atom that produces each, and the columns actually consumed are:
  - `.vmiss` from `--missing` — `ID` and `F_MISS` (`modules/local/geno_decisions/templates/geno_decisions.R:32-33`).
  - `.smiss` from `--missing` — `F_MISS` plus whichever of `FID`, `IID` are present
    (`modules/local/mind_decisions/templates/mind_decisions.R:33-36`). Both outputs are optional on the atom,
    because `variant-only` and `sample-only` are `ext.args` modifiers, and a caller joins on the channel it asked
    for.
  - `.hardy`, and `.hardy.x` for a fileset carrying chromosome X, from `--hardy` — `ID` and `P` from each. The two
    reports are read independently and their failing IDs unioned, not joined, so a variant listed on several lines
    is listed once (`modules/local/hwe_decisions/templates/hwe_decisions.R:35-40`). The chromosome-X report is
    optional at the atom and the caller substitutes `[]` for it through a `remainder: true` join rather than
    assuming it exists (`subworkflows/local/plink_qc_filter_lists/main.nf:123-126`).
  - `.sexcheck` from `--check-sex` — `PEDSEX`, `STATUS`, `F`, plus the ID columns; every other column passes
    through into the mismatch table. The pipeline lists plink2's own `PROBLEM` verdict rather than recomputing it
    (`modules/local/sex_check_decisions/templates/sex_check_decisions.R:27-34`).
  - `.het` from `--het` — `F`, joined to the sex-check report on the ID columns and renamed at the module boundary
    so the two `F` columns cannot be confused
    (`modules/local/heterozygosity_plots/templates/heterozygosity_plots.R:34-42`); the optional reference
    report contributes `F` alone.
  - `.afreq` from `--freq`, and `.acount` under its `counts` modifier (`modules/local/plink2/freq/main.nf`) — read
    by plink2 through `--read-freq`, never parsed by the pipeline; the two are interchangeable at that flag
    (verified on 2.0.0a.6.9: `--het --read-freq` gives byte-identical reports from either).
  - `.kin0` from `--make-king-table` — `KINSHIP`, `IBS0`, and the pair ID columns, `IID1`/`IID2` as the pinned
    plink2 writes them (with `FID1`/`FID2` beside them when the fileset carries family IDs) or `ID1`/`ID2` for a
    report in the bare id colset; every other column passes through into the pair table
    (`modules/local/relatedness_decisions/templates/relatedness_decisions.R`).
  - `.sscore`, and `.sscore.vars` when `list-variants` is configured, from `--score`
    (`modules/local/plink2/score/main.nf:14-15`) — the principal-component columns, discovered by pattern over the
    header and ordered numerically, because their names come from the weight file's own header under `header-read`
    rather than from a fixed schema (`modules/local/ancestry_assign/templates/ancestry_assign.R:61-72`).
  - `.eigenvec.allele`, `.eigenvec`, `.eigenval`, and `.acount` from one `--pca allele-wts` plus `--freq counts`
    run (`modules/local/plink2/pcawts/main.nf:15-18`); the weight file is read by plink2, not by the pipeline, and
    is addressed by column number.
  - `.snplist` from `--write-snplist` and `.prune.in`/`.prune.out` from `--indep-pairwise`, which are variant ID
    lists rather than tables and follow the list format above.
- **[MUST]** A variant file read by a pipeline-owned module is parsed by its extension, and each branch's column
  mapping is explicit: a `.pvar` is re-parsed from its own `#CHROM` header line, a `.bim` positionally
  (`modules/local/ancestry_harmonise/templates/ancestry_harmonise.R`, `read_variants`;
  `modules/local/highld_exclude/main.nf:39-40`; `modules/local/contig_exclude/main.nf`, which takes the ID
  column's position from the `#CHROM` line). The two formats order the allele columns oppositely, so a module
  that compares alleles across two variant files maps them onto one pair of slots the way plink2 itself does when
  it converts between the formats: bim column 5 and pvar `ALT` are A1, bim column 6 and pvar `REF` are A2. A
  bim and a pvar of one fileset then classify alike, and a test holds a bim target against the same reference
  read as a pvar (`modules/local/ancestry_harmonise/tests/main.nf.test`); document the mapping at the interface
  rather than requiring one format.
- **[MUST]** The allele-weight and allele-count tables of one `PLINK2_PCAWTS` run are a matched pair over one
  filtered variant set, and a projection consumes both from the same run: the weight file's column layout is what
  the `--score` column arguments address, and the count file is what `--read-freq` standardises against. Splitting
  the two across runs silently changes the standardisation
  (`modules/local/plink2/pcawts/main.nf:38-40`, `conf/modules/plink2.config:144-146`, `:156-160`).
- **[MUST]** Two `--score` runs whose coordinates are to be compared take the same weight file, the same
  `--read-freq` table, and the same modifiers, and differ only in the samples and the sample lists they receive
  (`subworkflows/local/ancestry_inference/main.nf:133-139`, `conf/modules/plink2.config:155-166`).
- **[SHOULD]** A per-rung or per-scatter statistics table is not published; the gathered product is
  (`conf/modules/plink2.config:44-48`, `conf/modules/qc_decisions.config:26-32`). A caller that gathers such
  tables side by side gives them distinct basenames through `ext.prefix` and passes the ordering key alongside the
  files rather than parsing it back out of a filename
  (`modules/local/missingness_ladder/main.nf:11-13`, `:28`).

## Plot and plot-data bundles

- **[MUST]** Every figure ships as two outputs: a plot-data TSV on its own channel, and the rendered `pdf` and
  `png` as one channel, because the two rendered files always travel together and are consumed as a unit
  (`modules/local/sex_check_decisions/main.nf:16-17`, `modules/local/heterozygosity_plots/main.nf:14-17`,
  `modules/local/relatedness_decisions/main.nf:20-21`, `modules/local/ancestry_assign/main.nf:22-24`).
- **[MUST]** The TSV is the contract-bearing product: it carries the header the figure was drawn from, it is what
  a snapshot asserts, and the rendered files are excluded from content snapshots as nondeterministic bytes
  (`tests/.nftignore`). A figure is never the only record of a number a reviewer needs.
- **[MUST]** A plot-data TSV has a fixed header and a data-independent row count wherever the plot's own geometry
  fixes it: a histogram writes every bin, including the empty ones, even though only the non-empty bins are drawn,
  and a degenerate range falls back to a documented fixed range chosen for that statistic
  (`modules/local/sex_check_decisions/templates/sex_check_decisions.R:43-54`,
  `modules/local/heterozygosity_plots/templates/heterozygosity_plots.R:48`,
  `modules/local/relatedness_decisions/templates/relatedness_decisions.R:124-132`). A fallback range is chosen per
  statistic and is not shared between modules.
- **[MUST]** A module that draws several figures emits each figure's data and rendered pair as separate channels
  rather than one collected bundle, because the figures are semantically distinct
  (`modules/local/heterozygosity_plots/main.nf:14-17`).
- **[MUST]** A report-only stage emits no decision list. Heterozygosity is report-only, so its module emits
  histogram and scatter products and nothing that could reach a removal slot
  (`subworkflows/local/plink_sample_qc_lists/main.nf:112-113`).
- **[MUST]** A plot module publishes its data and rendered files together into the stage directory of the
  statistic they describe (`conf/modules/qc_decisions.config:74-80`), so a figure never lands apart from the table
  it was drawn from.

## Reference-panel and population-table contracts

- **[MUST]** The reference panel is a schema-declared samplesheet of PLINK 1 filesets, not a directory convention
  or a path template: one row per fileset, either a single whole-genome fileset or one per chromosome, with
  `uniqueEntries: ["id"]` and `additionalProperties: false` (`assets/schema_reference.json`). No reference path is
  hardcoded anywhere.
- **[MUST]** The row `id` is both the per-fileset intersect prefix and the merge order. The composition sorts the
  gathered filesets by that id before building the merge list, so the merged reference is deterministic
  (`subworkflows/local/ancestry_inference/main.nf:63-69`).
- **[MUST]** The population table is a schema-declared TSV of `FID`, `IID`, `pop`, and `super_pop`
  (`assets/schema_reference_pop.json`). `super_pop` is the classifier's group vocabulary and the vocabulary a
  stratum's `ancestry` is matched against; its pattern constrains the labels to what can also be a filename
  component, because the per-group keep lists are named after them.
- **[MUST]** The vocabulary is read once at ingress from the table itself and passed as a validated value, never
  reconstructed downstream and never defaulted to a built-in population list
  (`subworkflows/local/utils_nfcore_gwasqc_pipeline/main.nf:117`). The one downstream reader, `ancestry_assign`,
  guards every column it uses (`IID`, `pop`, `super_pop`; `FID` only when the score tables carry one) and stops
  on a missing one (`modules/local/ancestry_assign/templates/ancestry_assign.R:56-58`).
- **[MUST]** The two reference assets are required together: the ancestry stage needs both, and ingress rejects a
  run that requests it with either missing rather than failing later
  (`subworkflows/local/utils_nfcore_gwasqc_pipeline/main.nf:113-118`). When the stage is skipped the reference
  channel is empty and every stratum carries an empty ancestry slot (`workflows/gwasqc.nf:107`,
  `subworkflows/local/utils_nfcore_gwasqc_pipeline/main.nf:131-133`).
- **[MUST]** A reference fileset is validated by the same fileset check as a stratum
  (`subworkflows/local/utils_nfcore_gwasqc_pipeline/main.nf:133`), so both sides of the ancestry route share one
  basename contract.
- **[MUST]** The long-range LD regions are a tracked repository asset with a parameter default and a build-matched
  filename (`assets/high_ld_regions_b38.bed`), passed as a process-global `path` to the module that reads it
  (`modules/local/highld_exclude/main.nf:12`). It is not a per-record tuple member, because it is one resource for
  the run.

## One terminal materialisation and reference-only intermediates

- **[MUST]** The study fileset is written exactly once, by the terminal `--make-bed`, from the original fileset and
  the complete list set (`workflows/gwasqc.nf:145`). No stage of the QC chain or of the ancestry route writes an
  intermediate study fileset, and a component that would need one is wrong for this pipeline: the statistic runs
  on the unfiltered fileset with the lists accumulated so far.
- **[MUST]** The `shared`-mode frequency table and reference report are statistics runs on the merged reference,
  not filesets, and are published beside the study's report (`conf/modules/plink2.config`, `PLINK2_FREQ` and
  `PLINK2_HET_REFERENCE`), because they are the basis a reviewer reads the study's `F` against.
- **[MUST]** The only materialised intermediates are the reference filesets of the ancestry route, and they exist
  because plink2 cannot produce them any other way: the per-fileset restriction to the matched reference IDs
  because `--extract` is applied only after `--pmerge-list` has concatenated its inputs in full, and the merged,
  renamed and harmonised reference because pruning, the decomposition, and the reference projection all read one
  fileset (`subworkflows/local/ancestry_inference/main.nf:42-47`). Neither is filtered: the reference-side
  `--maf` and `--geno` are arguments of the pruning runs, so that the pooled and the matched marker sets are each
  filtered on their own samples. A new intermediate needs the same kind of justification,
  recorded at the call site.
- **[MUST]** A reference intermediate is not published, and an intermediate produced by an alias of a published
  base process must disable publication explicitly, because the base selector's `publishDir` would otherwise reach
  it (`conf/modules/plink2.config:173-183`).
- **[SHOULD]** A stage that only measures emits tables and lists, never a fileset. Ten stats-only runs of the
  call-rate ladder produce one table (`subworkflows/local/plink_qc_filter_lists/main.nf:82-108`).

## Publication identity

- **[MUST]** Publication and prefixes live in `conf/modules/*.config`; no module's `main.nf` declares
  `publishDir` and no module hardcodes a published name. `ext.prefix` owns the published basename, and the default
  remains `meta.id` so a module works uninstructed.
- **[MUST]** A `withName:` selector matches a process and every alias of it, so an alias inherits its base
  process's publication and must re-point or disable it explicitly. The configuration says so at each such
  selector (`conf/modules/plink2.config:117-119`, `:121-128`, `conf/modules/qc_decisions.config:26-32`, `:92-103`).
  A silently inherited `publishDir` on an alias is a review finding.
- **[MUST]** A stratum's products are published under `${params.outdir}/qc/${meta.id}/<stage>` and the terminal
  fileset under `${params.outdir}/genotypes/${meta.id}` (`conf/modules/plink2.config`,
  `conf/modules/qc_decisions.config`). The stage directory is the scientific stage, not the process name, and a
  decision list is published beside the statistic it was derived from; a list derived from the variant table
  alone, the contig exclusion, has a stage directory of its own (`contigs`).
- **[MUST]** The process-wide default publishes nothing (`nextflow.config:301-311`), and every per-family selector
  opts its own processes in. An enabled `publishDir` in `conf/modules/plink2.config` or
  `conf/modules/qc_decisions.config` declares an explicit `pattern`, which is how a run log is never published:
  every plink2 atom emits its `.log` on a channel and no pattern matches it.
- **[SHOULD]** Express "deliberately unpublished" one way per repository. There are two mechanisms and they are
  not interchangeable: an alias of a published base process must carry
  `publishDir = [enabled: false]` (`conf/modules/plink2.config:177`, `conf/modules/qc_decisions.config:31`),
  because the base selector would otherwise reach it, while a process no selector publishes is already suppressed
  by the process-wide default and needs nothing. State which case applies in the selector's comment rather than
  leaving a reader to work out whether an omission is deliberate: "deliberately unpublished as an alias of the
  published X" for the first (`conf/modules/plink2.config`, `PLINK2_MAKEBED_REFERENCE`;
  `conf/modules/qc_decisions.config`, `GENO_DECISIONS_LADDER`) and "unpublished by the process-wide default"
  for the second (`conf/modules/plink2.config`, `PLINK2_MISSING_LADDER`, `PLINK2_MAKEKINGTABLE`,
  `PLINK2_PMERGELIST` and the score aliases; `conf/modules/multiqc.config`, `STRATUM_REPORT`).
- **[MUST]** Where a prefix must distinguish an alias's outputs in the same published directory, `ext.prefix`
  carries the distinguishing token and the module stays unaware of it: `${meta.id}.maf`, `${meta.id}.qc`,
  `${meta.id}.ancestry`, `${meta.id}.ancestry_reference`, `${meta.id}.ancestry_study`, `${meta.id}.reference`
  (`conf/modules/plink2.config`).

## The removal-gate union

- **[MUST]** The gate is one union at one slot, composed in the caller and applied by the terminal materialisation
  (`workflows/gwasqc.nf:135-145`). The mind removal list is always in the union, because the legacy chain always
  applied it; `apply_sample_removals` adds the sex-mismatch and relatedness removal lists; within that gate,
  `ancestry_remove_mismatched` adds the ancestry mismatch list.
- **[MUST]** Because every sample decision is a removal list, the union needs no branching over `--keep` and the
  `keep` slot stays `[]` (`workflows/gwasqc.nf:142`). A future sample decision expressed as a keep-list would
  change the gate's shape and belongs in the route decision, not in a module.
- **[MUST]** A gated list is produced unconditionally and published unconditionally; only its arrival at the
  removal slot is gated. A list the gate excludes is still a public product, and the mean-kinship outlier list is
  published without ever being applied (`subworkflows/local/plink_sample_qc_lists/main.nf:118`).
- **[MUST]** A slot that a skipped stage would leave unfilled is filled with `[]` by the caller, so the gate's
  arity does not depend on which stages ran (`workflows/gwasqc.nf:107`).
- **[SHOULD]** The per-group ancestry keep lists are emitted and published for downstream stratification and are
  not consumed by this pipeline (`subworkflows/local/ancestry_inference/main.nf:169`). Keep them as a public
  product; do not wire them into the gate to give them a consumer.

## Identity tags and version reporting

- **[MUST]** `tag` is `"${meta.id}"` on every module here. It does not repeat the tool or subcommand name, which
  the process name already carries, and it does not add a scatter key: the runtime item is the stratum.
- **[MUST]** A plink2 atom reports its version on the `versions` topic with an `eval` output whose extraction
  yields a bare version string (`modules/local/plink2/missing/main.nf:17`).
- **[MUST]** A template-backed module writes `versions.yml` from inside its template and emits it as
  `path "versions.yml", emit: versions, topic: versions`, because an `eval` output is accepted only for a Bash
  script. Each such module records that reason in a comment at the declaration
  (`modules/local/geno_decisions/main.nf:18-19`). The stub reproduces the same file with the same keys.
- **[MUST]** Every interpreter the module actually invokes is reported, not only the scientific tool: the R
  modules report `r-base` and each library they load, and `highld_exclude` reports `gawk`
  (`modules/local/highld_exclude/main.nf:16`).

Package and container requirements are owned by [`component-containers.md`](component-containers.md); fixture
reuse, assertion, and snapshot policy by [`component-fixtures-and-testing.md`](component-fixtures-and-testing.md);
the generic atomic and composition contracts by [`nf-core-modules.md`](nf-core-modules.md) and
[`nf-core-subworkflows.md`](nf-core-subworkflows.md).
