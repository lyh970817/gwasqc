---
name: repository-domain-docs
description: Route design, naming, architecture, or domain-model work through this repository's ignored local domain notes and decision records. Use when a task introduces or changes domain terminology, boundaries, invariants, or architecture. Do not use for mechanical edits, tests, formatting, or component contracts already owned by canonical standards.
---

# Consult repository domain documentation

Read `docs/agents/domain.md` when it exists in the active local checkout, then follow its routing to the
relevant domain context and decision records. `.gitignore` reserves `docs/agents/`, `docs/adr/`, `CONTEXT.md`,
and `CONTEXT-MAP.md` for exactly this material: it is intentionally ignored local state, so do not copy its
contents into this skill, relocate it, or start tracking it as part of an instruction-maintenance task. Stable
tracked contracts live in `CODING_STANDARDS.md` and the topics it indexes, and take precedence.

Report any applicable terminology or decision-record constraint that materially changes the task. If the routed
local files are absent, continue without proposing them as prerequisite work.
