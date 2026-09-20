# Local subworkflows

`plink_qc_filter_lists` and `utils_nfcore_gwasqc_pipeline` are pipeline-owned. `plink_qc_filter_lists` composes
the pipeline's decision modules, so it carries scientific policy and is measured against
`pipeline-architecture.md` and `nextflow-code-style.md` rather than the reusable-composition contract; it is not
a component-library submission candidate.

An upstream-bound subworkflow added here must provide meaningful multi-step composition of upstream-prepared
modules only and must follow the canonical subworkflow, GWAS-contract, fixture, and component-test standards
indexed by `CODING_STANDARDS.md`. Pipeline-owned compositions must not appear in its dependency graph.

Pipeline nf-test discovery of a local subworkflow is regression coverage, not proof of component-submission
readiness.
