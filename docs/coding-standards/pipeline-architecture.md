# Pipeline architecture standards

Applies to pipeline-owned orchestration, routes, and helpers. Atomic component and reusable-subworkflow
interfaces remain owned by [`nf-core-modules.md`](nf-core-modules.md),
[`nf-core-subworkflows.md`](nf-core-subworkflows.md), and
[`gwas-component-contracts.md`](gwas-component-contracts.md); user-facing parameter contracts remain owned by
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
[`gwas-component-contracts.md`](gwas-component-contracts.md).

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
- The iterative-missingness ladder is computed once, in R, from the single `--missing` report: at each call
  rate from 90 % to 99 % it counts the variants, then the samples, not already dropped at an earlier rung. The
  legacy sweep re-ran plink after every rung on a shrinking fileset, so its per-sample rates were measured over
  the surviving variants and vice versa; the marginal rates of one report cannot reproduce that recomputation,
  and the ladder is defined on the single report by design. The same holds for the mind list: it is measured
  over the MAF-passing variants, where the legacy chain measured it over the geno-passing ones.
