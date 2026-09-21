---
name: gwasqc-pipeline-test
description: Run or debug this nf-core/gwasqc pipeline's fixture-backed nf-test scenarios or full local suite. Use for tests under tests/, colocated local component tests, the GWASQC_TEST_FIXTURES resolver, nf-test-parallel, native sharding, snapshot staleness, or pipeline-behaviour validation. Do not use for upstream component submission tests.
---

# Test the gwasqc pipeline

Read the root `AGENTS.md` and
[`ci-and-testing.md`](../../../docs/coding-standards/ci-and-testing.md). `nf-test.config`,
`conf/test_fixtures.config`, `tests/nextflow.config`, `shell.nix`, and `.github/workflows/nf-test.yml` own the
exact commands, versions, and matrices; inspect those live files rather than trusting a remembered value.

## Resolve fixtures

`conf/test_fixtures.config` owns fixture resolution and both `conf/test.config` and `conf/test_full.config`
load it. It reads the `GWASQC_TEST_FIXTURES` environment variable first and otherwise falls back to
`params.pipelines_testdata_base_path`, whose pipeline default is the remote `gwasqc` branch of
`nf-core/test-datasets`; either value is normalised to a trailing slash. From that base the profile derives
`params.input`, `params.reference_panel`, and `params.reference_pop_data`, materialising the two samplesheets
under the JVM temporary directory with the fixture paths resolved into them.

The resolver reports a missing fixture samplesheet on stderr and continues, so the run fails later as an
nf-schema validation error. Read that warning before diagnosing a schema failure as a pipeline defect.

Set `GWASQC_TEST_FIXTURES` to a local checkout of the fixture branch for an offline run or a modified fixture
copy, or to the raw URL of a fork branch to test unmerged fixtures; `.github/workflows/nf-test.yml` carries the
same variable, empty by default, for CI. The pipeline default in `nextflow.config` is the one knob to change when
the fixtures move. Neither `shell.nix` nor `.envrc` exports it, so supply it per invocation, and never commit a local
fixture path.

## Run the requested scope

`nf-test.config` sets `testsDir = "."`, `configFile = "tests/nextflow.config"`, and `profile = "test"`, and
ignores `modules/nf-core/**/tests/*` and `subworkflows/nf-core/**/tests/*`. The vendored template component
tests are therefore outside discovery by design, not tolerated failures; do not re-enable them to explain a
missing test. Because a profile is already declared, append the runtime profile instead of replacing it:

```console
nf-test test tests/<scenario>.nf.test --profile +docker
```

Pipeline scenarios live flat in `tests/` and carry `tag "pipeline"` plus a scenario tag. Tests colocated with
`modules/local/**` and `subworkflows/local/**` are discovered as regression coverage. Discover the current
filenames and tags before a focused run rather than assuming a tag exists.

For broad validation use the development shell's wrapper, which runs the native shards concurrently and gives
each shard its own `NFT_WORKDIR`:

```console
nf-test-parallel 3 --verbose
```

`NFT_PROFILE` selects its profile and defaults to `+docker`. Without the wrapper, run each native shard
directly with `nf-test test --profile=+docker --shard i/n`, a distinct `NFT_WORKDIR` per shard, and aggregated
exit statuses.

A local suite run is not CI evidence. CI derives its shard count from a dry run, tests only what changed since
the merge base, and repeats the matrix across the `conda`, `docker`, and `singularity` profiles and more than
one Nextflow version before a fan-in job decides the result. Name the profiles you did not run.

## Snapshots and stopping

After broad shard validation, apply the canonical unsharded-suite trigger in `ci-and-testing.md`. When it
requires an unsharded run, confirm and remove obsolete snapshot entries deliberately; do not use
`--wipe-snapshot` for routine validation. `tests/.nftignore` excludes the nondeterministic output, the plot
files among it, from content snapshots; extend it rather than weakening an assertion.

The development shell and the CI workflow pin nf-test independently, so record the nf-test and Nextflow
versions actually used and report a drift between them as an environment finding.

Report exact scope, profile, fixture source, tool versions, commands, pass/fail counts, snapshot warnings, and
environment blockers.
