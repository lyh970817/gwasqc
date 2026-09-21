# Local modules

The PLINK 2 family under `plink2/` holds upstream-bound atomic candidates and must follow the canonical module,
GWAS-contract, container, fixture, and component-test standards indexed by `CODING_STANDARDS.md`. Use the
corresponding `nf-core-*` skills for task procedure. Keep them free of pipeline routing, scientific policy,
publication, and reuse identity: a threshold reaches a plink2 atom only as native optional behaviour through
`ext.args` (or `ext.args2` where plink2 reads modifiers that must follow the command flag, as `plink2/checksex`
does), never as a module input.

`geno_decisions`, `mind_decisions`, `missingness_ladder`, `missingness_plots`, `hwe_decisions`, `hwe_plots`,
`highld_exclude`, `sex_check_decisions`, `heterozygosity_plots`, `relatedness_decisions`, `ancestry_harmonise`,
`ancestry_assign`, `stratum_report` and `qc_summary` are pipeline-owned. They carry the pipeline's decision
policy (thresholds are explicit inputs; `ancestry_assign` reads the stratum's `meta.ancestry` to decide the
mismatch list), draw its review figures, or assemble its report from the published lists and tables, so they
follow `pipeline-architecture.md` and `nextflow-code-style.md` and are not component-library submission
candidates. Do not transfer their semantics into an upstream-bound atom. A bash template of a pipeline-owned
module carries no shebang: a shebang makes Nextflow bypass `process.shell`, and with it the strict-mode flags
that turn a failing command into a failed task.

Pipeline nf-test discovery of a local module is regression coverage, not proof of component-submission
readiness. Run component submission validation in the writable `nf-core/modules` submission worktree.
