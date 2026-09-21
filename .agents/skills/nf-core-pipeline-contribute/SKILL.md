---
name: nf-core-pipeline-contribute
description: Implement or prepare a contribution to this existing nf-core/gwasqc pipeline. Use for component installation or wiring, schema or method configuration, public pipeline docs, relevant lint/tests, or a change routed onto the pipeline's personal track. Apply only the procedure steps relevant to the requested delta. Do not use for submitting a component to nf-core/modules.
---

# Contribute to the pipeline

Read
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md) and the applicable
pipeline topics indexed by `CODING_STANDARDS.md`. Apply `dual-track-commit` before commit or branch
synchronization in this repository.

## Procedure

1. Classify the requested delta against the personal-only/portable boundary and resolve the tracker issue it
   serves. This pipeline is not a registered nf-core pipeline and has no public PR target, so do not create or
   assume one; an upstream contribution here means a component submission, which the submission skills own.
2. When installing or updating a shared component, use `nf-core modules install <component>` or
   `nf-core subworkflows install <component>` so `modules.json` records provenance; do not hand-copy installed
   components. Skip this step for changes that do not install or update a component.
3. When composition changes, wire the affected inputs and outputs. Put per-process extension arguments,
   prefixes, resources, and publication in the relevant method-family `conf/modules/*.config`, not an installed
   component.
4. When user-visible parameters change, update `nextflow_schema.json` with the current schema builder and revise
   the affected public documentation. Do not manufacture schema or documentation churn for an unrelated delta.
5. Add a `CHANGELOG.md` entry only when the requested contribution and the pipeline's live release convention
   require one; use the current development or unreleased section.
6. Select validation from the changed surface: use the pipeline test procedure for affected routes, run the
   relevant configured lint gates, and add a direct smoke run only when the change warrants it. Record skipped
   gates rather than implying that every contribution has the same test surface.
7. For commits or branch synchronization, apply `dual-track-commit`, which owns the branch topology and the
   reviewer-facing text boundary.
8. Before closing the linked issue, when practical, delete issue-specific generated audit and evidence documents
   without an ongoing named consumer.
9. Report the applicable CI and local gate results before asking for review, and perform no external action the
   user has not explicitly requested.
10. Close the linked tracker issue after the contribution is integrated into `personal` and its required
    verification is complete.

Report repository and branch; which procedure steps applied or were inapplicable; actual installed,
wired, schema, config, documentation, or changelog changes; fallback topics consulted; exact validation results;
CI state; generated documents retained or deleted; linked tracker issue and closure state; and skipped tests or
profiles.
