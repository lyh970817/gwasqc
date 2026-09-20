# Local modules

The PLINK 2 family under `plink2/` holds upstream-bound atomic candidates and must follow the canonical module,
GWAS-contract, container, fixture, and component-test standards indexed by `CODING_STANDARDS.md`. Use the
corresponding `nf-core-*` skills for task procedure. Keep them free of pipeline routing, scientific policy,
publication, and reuse identity: a threshold reaches a plink2 atom only as native optional behaviour through
`ext.args`, never as a module input.

`missingness_decisions` and `hwe_decisions` are pipeline-owned. They carry the pipeline's decision policy
(thresholds are explicit inputs), so they follow `pipeline-architecture.md` and `nextflow-code-style.md` and are
not component-library submission candidates. Do not transfer their semantics into an upstream-bound atom.

Pipeline nf-test discovery of a local module is regression coverage, not proof of component-submission
readiness. Run component submission validation in the writable `nf-core/modules` submission worktree.
