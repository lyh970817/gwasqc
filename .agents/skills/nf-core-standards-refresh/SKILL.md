---
name: nf-core-standards-refresh
description: Refresh or verify the ignored docs/nf-core-standards cache from current primary nf-core sources. Do not use for changing canonical repository standards or lifecycle skills.
---

# Refresh the nf-core standards cache

The cache's own `docs/nf-core-standards/index.md` is the topic/source inventory: it records which primary
source each topic was distilled from and when. There is no separate tracked source manifest. Read
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md) for precedence.

Primary sources are the current nf-core documentation site (the component, pipeline, and container
specifications) and the upstream `nf-core/modules` and `nf-core/tools` repositories. The read-only `.references`
checkouts, the reference pipelines and the companion `nf-core/modules` checkout, are corroborating examples of
current practice only; a checkout never substitutes for the specification it illustrates, and a candidate's own
mirrored work there is not its precedent.

## Write boundary

Write only under ignored `docs/nf-core-standards/` unless the user explicitly asks to change the skills or the
canonical standards. Do not commit generated cache files.

## Procedure

1. Record repository status and preserve unrelated changes.
2. Fetch each source that the index maps to a selected topic, or that the user's request names for a new topic,
   from primary nf-core documentation or its upstream repository. Verify moved URLs; do not replace a primary
   source with a blog, issue anecdote, or community summary.
3. Rebuild only the selected topic files. Each starts with a title, fetch date, and source list, then distills
   concise task-oriented rules. Separate upstream rules from repository-specific mechanics.
4. Update `docs/nf-core-standards/index.md` with source mapping, fetch date, and topic routing, so it remains
   the inventory the next refresh reads. Do not mirror raw pages or long passages.
5. Check changed cache files for whitespace and broken source references. If the user also authorized tracked
   guidance changes, run `git diff --check` on those exact tracked paths.

Report changed cache topics, fetch date, source failures or moves, and any skill procedure or canonical standard
that now appears stale. Do not commit unless explicitly asked.
