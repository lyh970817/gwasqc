# Pipeline architecture standards

Applies to pipeline-owned orchestration, routes, and helpers. Atomic component and reusable-subworkflow
interfaces remain owned by [`nf-core-modules.md`](nf-core-modules.md),
[`nf-core-subworkflows.md`](nf-core-subworkflows.md), and
[`qc-component-contracts.md`](qc-component-contracts.md); user-facing parameter contracts remain owned by
[`configuration-and-schema.md`](configuration-and-schema.md).

## Ingress and representation

- **[MUST]** Validate external manifests, parameters, and their relationships at pipeline ingress. Downstream
  stages consume the resulting trusted internal contract without revalidating it.
- **[MUST]** Representation adapters change representation only. Preserve the native result and its semantics;
  normalize or assemble output only when a consumer requires that product.

## Work, identity, and cardinality

- **[MUST]** Select scientific work explicitly. A route runs only the requested methods and analyses.
- **[MUST]** The scientific stage that performs reusable work owns its identity and reuse decision. Keep
  publication, retention, and restart/resume semantics separate from that decision.
- **[MUST]** Where a consumer requires ordered inputs, preserve and document the corresponding cardinality and
  order through scatter, gather, and assembly.

## Execution boundaries

- **[MUST]** Introduce a process only for an active native-program invocation or a concrete execution boundary.
  Keep channel reshaping and pure orchestration in the caller or route that owns it.
- **[MUST]** Keep a pipeline-owned route, helper, or adapter only while it has an active caller and consumer.

## Genotype QC route

Decided 2026-09-20 with the foundation milestone of the legacy port; the tuple contract itself is owned by
[`qc-component-contracts.md`](qc-component-contracts.md).

- **[MUST]** A stratum is one PLINK 1 `[ val(meta), path(bed), path(bim), path(fam) ]` tuple carrying
  `meta.id` and `meta.ancestry`, exactly as the samplesheet row declares it. The fileset is consumed natively:
  plink2 atoms select `--bfile` or `--pfile` from the staged extension, so a PGEN samplesheet route would pass
  its tuple through the same interface unconverted. Nothing converts bed to pgen or back before the terminal
  materialisation.
- **[MUST]** QC is list-accumulating. Every statistic (`--missing`, `--hardy`, and the later `--het`,
  `--check-sex`, KING) runs on the unfiltered stratum fileset and receives the lists accumulated so far as
  inputs; plink2 applies `--extract`, `--exclude`, `--keep` and `--remove` before it computes, so each report
  describes the filtered set without a filtered fileset. The QC'd fileset is written exactly once, by the
  terminal `--make-bed`, from the original fileset and the complete list set. No intermediate bed/bim/fam
  exists anywhere in the chain.
- **[MUST]** Lists combine with plink2's native semantics, stated once here: files given to one flag are
  concatenated, so `--extract` keeps the union of its keep-lists, `--exclude` drops the union of its
  exclusion lists, and `--remove` drops the union of its removal lists; a variant survives only when it is in
  the extract set and in no exclude set, and a sample only when it is in no remove set. The foundation chain
  therefore passes the MAF keep-list to `--extract`, the geno and HWE exclusions to `--exclude`, and the mind
  removals to `--remove`. Decision lists that the legacy chain never applied (sex, heterozygosity, relatedness,
  ancestry) join `--remove` only under `apply_sample_removals`.
- **[MUST]** Decision lists are derived from published statistics by pipeline-owned modules that take their
  thresholds as explicit inputs; a threshold reaches a plink2 atom only as native optional behaviour through
  `ext.args`. Comparisons are strict, as plink2's own `--geno`, `--mind`, `--maf` and `--hwe` are.
- **[MUST]** Missingness follows the legacy order exactly, and does so with lists because plink2 writes the
  `--missing` report before it applies `--geno` (verified on 2.0.0a.6.9: `--geno 0.10 --missing` reports every
  variant; `--mind` is applied before the report). One `--missing` run over the MAF-passing variants yields the
  variant report and, from it, the geno exclusion list; a second run with that list under `--exclude` yields
  the sample report over the geno-retained variants and, from it, the mind removal list. A sample's rate is
  therefore measured over the variants that survive geno, as the legacy `--geno` then `--mind` filesets
  measured it, and a sample at the threshold over all variants can survive once its missing calls in excluded
  variants no longer count.
- The call-rate ladder, 90 % to 99 %, applies each rate from the base fileset, geno then mind, as the legacy
  `Iterative_Missingness.sh` did: per rung, the geno exclusion list at that rate is derived from the base
  variant report, one `--missing` run with that list under `--exclude` yields the rung's sample report, and the
  table records the variants and samples each rung removes and leaves. Ten stats-only runs, no fileset.
- **[MUST]** The sample QC chain runs on a marker set chosen per stratum, and the choice is made once, after the
  mind list exists, and carried as `meta.sample_qc_marker_set`: `study` or `shared` as forced, and under
  `auto` `shared` for a stratum with fewer than `small_n_threshold` samples after the mind filter. The
  `shared` mode needs the ancestry route, so a forced `shared` under `skip_ancestry`, and a stratum whose
  input count alone decides it will need it, are rejected at ingress, and the residual case when the mode is
  decided. _(decided 2026-09-21 with the small-n milestone, issue #2)_
- **[MUST]** In the `study` mode the chain keeps the legacy ordering: `--indep-pairwise` prunes the QC'd set over
  every chromosome; the long-range LD regions (the tracked GRCh38 asset, derived from the legacy awk rules) and
  every non-autosomal variant are then listed for exclusion among the pruned variants. The sex check runs on
  the pruned set with chromosome X, splitting the pseudo-autosomal regions and applying its thresholds in the
  one `--check-sex` run (verified: `--split-par b38`, `--extract` and `--check-sex` combine on a `--bfile`
  input, so nothing is materialised); heterozygosity and KING relatedness run on the pruned autosomal set
  outside the regions. A stratum whose pruning kept fewer than `ld_min_retained_fraction` of its QC'd variants
  is noted in its summary row, because pairwise r-squared over a few dozen samples collapses the set (the
  11-sample legacy stratum kept 0.5 %); nothing is re-decided.
- **[MUST]** In the `shared` mode nothing is pruned on the study side. Heterozygosity and KING relatedness run on
  a marker set the ancestry route builds from the harmonised merged reference, outside the long-range LD
  regions and on the autosomes, chosen by `sample_qc_shared_reference`: `pooled` (the default until real small
  strata have been measured, issue #5) is the route's own post-high-LD `prune.in`, filtered and pruned on
  every reference sample; `matched` reruns `--maf`, `--geno` and `--indep-pairwise` in one stats-only run on
  the reference samples of the stratum's super-population (`--keep`, verified on 2.0.0a.6.9 to compute the
  filters over the kept samples and to equal the two-step extract-then-prune). The pooled filters therefore
  sit on the pruning run, not on the restriction, so that a matched set is not pre-restricted by them. The
  ancestry decomposition uses the pooled set either way. The heterozygosity report of the study and that of the reference samples of the
  stratum's own super-population are computed over those markers against one `--freq` table of those reference
  samples through `--read-freq`, so that the study cannot define its own baseline and the two reports differ
  only in their samples; the sex check runs on every QC-passing chromosome X and Y variant unpruned, because
  the reference carries no chromosome X and pruning X over a handful of samples is what starved the legacy
  check. The reference samples are selected from the population table by the stratum's `ancestry` label; a
  pooled panel is not a substitute, as its frequencies inflate F by the panel's differentiation.
- **[MUST]** The mind removals apply to every study-side run of either mode; no other sample list does. plink2
  refuses `--indep-pairwise`, `--check-sex` and `--het` below 50 samples; the configuration lifts the refusal
  with `--bad-ld` on the study-side pruning and `--bad-freqs` on the sex check and the `study`-mode
  heterozygosity report, never on a reference-side run, because there the stratum's own estimates are the
  user's explicit choice and the collapse note is the safety net (verified on 2.0.0a.6.9 with the 12-sample
  fixture stratum, which prunes to 4.8 % under `--bad-ld`).
- **[MUST]** Sex mismatches are plink2's own `PROBLEM` calls, tabled with the report's header and listed for
  removal. Heterozygosity is report-only. Relatedness pairs are classified on KING's inference boundaries; the
  removal list holds one member of each duplicate/MZ pair, the one with the higher missing-call rate over the
  geno-retained variants, and the mean-kinship outlier list is published without ever being applied. Under
  `apply_sample_removals`, the sex-mismatch, relatedness and ancestry mismatch removal lists join the mind list
  in the terminal `--remove`; every sample decision is a removal list, so the gate is one union at one slot and
  `--keep` stays empty.

### Ancestry route

Decided 2026-09-20 with the ancestry milestone of the legacy port.

- **[MUST]** The reference panel is a schema-declared samplesheet of PLINK 1 filesets, one whole-genome fileset
  or one per chromosome, and its population table a schema-declared TSV of `FID`, `IID`, `pop` and
  `super_pop`; the `super_pop` labels are the classifier's groups and the vocabulary of the samplesheet
  `ancestry` column. No reference path or population list is hardcoded anywhere.
- **[MUST]** The stratum reaches the reference as its QC'd variant set, the filter chain's lists, not as a
  separate target QC: the legacy `nrow(fam) > 100` switch, which dropped the MAF and HWE filters on small
  targets, chose which filters to _compute_, and the pipeline has computed them for every stratum before
  ancestry runs. The study fileset is never materialised; its samples are projected from the original fileset
  with the pruned list under `--extract` and the mind removals under `--remove`, and no other sample list.
- **[MUST]** Harmonisation runs on the variant tables, before any genotype is read, and is by normalised
  chromosome, position and alleles, independent of the IDs: a `chr` prefix is dropped and `X`, `Y`, `XY`, `MT`
  read as `23` to `26`; A/T and C/G pairs are dropped even when the alleles agree; a study ID repeated among the
  QC'd variants or a matched reference ID repeated in the panel is `duplicate_id`, because plink2 addresses
  variants by ID; several candidates at a position that do not leave exactly one allele-compatible reference
  variant, or one claimed by several study variants, are `duplicate_position`; the study side is never
  flipped. The reference panel is read in chunks keeping only rows at a study position or with a study ID, so a
  whole-genome panel never sits in memory (10 million variants: 98 s, about 1.1 GB).
- **[MUST]** The genome build is checked, not lifted: when more than half of the IDs the stratum shares with
  the panel sit at another chromosome or position, harmonisation stops naming the counts and `genome_build`,
  because position matching against a panel on another build keeps only a coincidental remainder. Liftover is
  a preparation step outside the pipeline.
- **[MUST]** The reference is the one materialised intermediate of the route, and it is materialised twice
  per stratum: once per fileset restricted by `--extract` to the reference IDs of the harmonised variants,
  because plink2 applies `--extract` only after `--pmerge-list` has concatenated its inputs in full (verified
  on 2.0.0a.6.9), and once merged, renamed to the study's IDs by `--update-name` and flipped onto the study's
  strand by `--update-alleles`, because pruning, the decomposition and the reference projection all read that
  fileset. The rename belongs to the merge, not to the restriction, and the flip list is keyed by the study
  IDs: plink2 applies `--update-name` before `--extract` and keys `--update-alleles` by the new IDs, alone and
  under `--pmerge-list` (verified on 2.0.0a.6.9). Neither fileset is published and neither is filtered. The
  reference-side filters are the pipeline's `--maf` and `--geno` on the pruning run, never `--hwe`: on a pooled
  multi-population panel that test measures population structure.
- **[MUST]** The flip list is exactly what `--update-alleles` applies to the reference, and nothing else is
  changed. The long-range LD and non-autosomal exclusion is applied to the merged reference before
  `--indep-pairwise`, as the legacy ancestry branch ordered the two.
- **[MUST]** Projection follows the plink2 recipe: `--freq counts` and `--pca allele-wts vcols=chrom,ref,alt`
  in one run over the pruned reference, then one `--score <weights> 2 5 header-read no-mean-imputation
variance-standardize` with `--read-freq` of those counts for the reference samples and for the study samples
  alike, so that both sets of coordinates share one scale and the study is standardised with the reference's
  frequencies rather than its own.
- **[MUST]** Assignment is linear discriminant analysis on the projected reference coordinates with equal group
  priors; a study sample is assigned when its largest posterior reaches `ancestry_prob_threshold` and is
  otherwise unassigned, and the optional centroid rule (`ancestry_sd_filter`, off by default) unassigns rather
  than relabels. Every count the summary reports names the rule that produced it. The mismatch removal list
  holds the study samples not assigned to the stratum's `ancestry`, the unassigned included, and joins the
  terminal `--remove` under `apply_sample_removals` when `ancestry_remove_mismatched` holds; a stratum label
  outside the reference vocabulary is rejected at ingress under that gate and warned about otherwise.
