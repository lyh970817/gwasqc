---
name: dual-track-commit
description: Route commits in this repository across its personal development track and its upstream nf-core/modules submission track. Use for commit, amend, split, cherry-pick, merge, rebase, or synchronization work that may mix personal development infrastructure with portable pipeline or upstream-bound component changes.
---

# Route dual-track commits

Read the track classification and public boundary in
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md).

This repository has one pipeline branch track, local `personal`, and no public pipeline PR. Its upstream track
is the component library: a focused `nf-core/modules` submission of a PLINK 2 atom, prepared in a separate
writable `nf-core/modules` checkout. Do not invent an `nf-core/gwasqc` `dev` or `master` PR target, and do not
treat the upstream submission as a branch of this repository.

## Resolve the tracks

1. Inspect live remotes, branches, worktrees, dirty state, and branch tips in both checkouts. Confirm which
   `nf-core/modules` branch and worktree, if any, the task involves; never infer one from a component's local
   path.
2. Use separate clean worktrees. Record starting tips and preserve pre-existing changes.
3. Create an exhaustive hunk ledger using the canonical personal-only/portable classification. Split mixed files
   by hunk and assign each hunk exactly once.

## Commit on `personal`

1. Group commits by concept and commit portable pipeline hunks before the personal-only hunks that depend on
   them, so each commit stands on its own.
2. Before every commit, scan the staged diff for content that the public reviewer boundary excludes from
   reviewer-facing files: machine paths, worktree names, environment overrides, private tracker references,
   agent or Nix material in `README.md`, `CHANGELOG.md`, `CITATIONS.md`, `docs/usage.md`, or `docs/output.md`.
   Personal-only paths belong in their own commits, not in a reviewer-facing file.
3. Merge a temporary branch into `personal` only after verifying that it carries nothing which must never be
   tracked, `.scratch/` above all. Rewrite the branch first rather than merging and reverting.

## Transfer to the upstream component track

1. Copy only the portable atomic component contract into the `nf-core/modules` worktree: `main.nf`, `meta.yml`,
   `environment.yml`, and the component's own tests. Pipeline routing, publication, reuse identity, private
   tracker context, local fixture discovery, agent tooling, and machine-specific paths do not transfer.
2. Base commit grouping and reviewer wording on the diff against that repository's current upstream `master`,
   not on this repository's history. Do not narrate the local port.
3. This transfer does not create a commit on `personal`, and an upstream submission is not required to be
   mirrored back into this repository's history.
4. Route readiness evidence to `nf-core-submission-test` and reviewer-facing text to `nf-core-submission-pr`.

## Conflicts

1. On a merge or rebase conflict, preserve the conflict state while inspecting the index stages, worktree
   result, relevant history, and hunk ledger. Derive the intended result from the canonical invariant: the
   portable behavior plus the already-classified personal-only additions. Do not decide from path names or
   `ours`/`theirs` labels alone.
2. Resolve and continue without asking only when classification and intent are unambiguous and the resolution is
   mechanically implied by that invariant: keep the newer version of portable, generated, or reviewer-facing
   content; or combine the portable behavior with an established personal-only extension without changing its
   scope or precedence. Before continuing, inspect the staged resolution and verify both the portable behavior
   and the unchanged personal-only boundary.
3. Keep the conflict state intact and request explicit instructions when classification is ambiguous, product
   behavior is incompatible, personal-only semantics would be lost or expanded, the public boundary is
   uncertain, the strategy is destructive or history-changing, or the intended result is not mechanically
   implied by the track invariant. Never feed personal-only content into an upstream submission.

## Verify and report

Verify clean worktrees, per-commit and aggregate `git diff --check`, the reviewer-facing text boundary, logical
commit ordering, and relevant portable validation. Push only when authorized, and push `personal` only once
every intended change is merged into it and every merged temporary branch and worktree is cleaned up; use
`--force-with-lease` only for explicitly authorized history rewriting after recording the remote tip.

Report starting and final tips in every checkout, commit mapping, hunk classification, the boundary scan result,
validation scope, clean state, unpushed commits, and every unresolved gate.
