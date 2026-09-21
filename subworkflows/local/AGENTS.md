# Local subworkflows

`plink_qc_filter_lists`, `plink_sample_qc_lists`, `ancestry_inference` and `utils_nfcore_gwasqc_pipeline` are
pipeline-owned. `plink_qc_filter_lists`, `plink_sample_qc_lists` and `ancestry_inference` compose the pipeline's
decision modules, so they carry scientific policy and are measured against `pipeline-architecture.md` and
`nextflow-code-style.md` rather than the reusable-composition contract; they are not component-library
submission candidates.

An upstream-bound subworkflow added here must provide meaningful multi-step composition of upstream-prepared
modules only and must follow the canonical subworkflow, genotype-QC-contract, fixture, and component-test standards
indexed by `CODING_STANDARDS.md`. Pipeline-owned compositions must not appear in its dependency graph.

Pipeline nf-test discovery of a local subworkflow is regression coverage, not proof of component-submission
readiness.
