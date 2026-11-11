# Configuration and parameter-schema standards

Applies to `nextflow.config`, `conf/*.config`, `nextflow_schema.json`, `assets/*.json`, and `.nf-core.yml`.

---

## 1. `nextflow.config`

- **[MUST]** Every config file — including every `conf/test*.config` — opens with the same two-tier banner.
  mag breaks this in 4 of its 9 test configs by using `========` instead, and it reads as drift:

  ```groovy
  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      nf-core/gwasqc Nextflow config file
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      Default config options for all compute environments
  ------------------------------------------------------------------------------------------
  */
  ```

  _(all three)_

- **[MUST]** Organise `params { }` into comment-headed subgroups, each header unique and used once. The live
  set, in order, is `// Input options`, `// Reference options`, `// QC thresholds`, `// LD pruning options`,
  `// Sample QC options`, `// Ancestry options`, `// MultiQC options`, then the three boilerplate groups
  below. mag repeats two headers non-contiguously — a navigability defect. Align `=` within each subgroup,
  not globally across the whole block. _(all three)_

- **[MUST]** The params block ends with the same three boilerplate groups, in order:
  `// Boilerplate options` → `// Config options` → `// Schema validation default options`. _(all three)_

- **[MUST]** `process.shell` pinned to strict bash, with the per-flag comments retained: _(all three)_

  ```groovy
  process.shell = ["bash", "-C", "-e", "-u", "-o", "pipefail"]
  ```

- **[MUST]** `validation.defaultIgnoreParams` — the nf-schema key. Never the deprecated
  `validationSchemaIgnoreParams`, and never the `nf-validation` plugin. _(verified: all three use
  `defaultIgnoreParams`, zero occurrences of the legacy key)_

- **[MUST]** `docker.runOptions`, `cleanup`, and `nextflow.enable.configProcessNamesValidation = true` live
  inside profile blocks (`docker`, `debug`), never at top level. The top-level default is
  `nextflow.enable.configProcessNamesValidation = false` with the standard explanatory comment.
  _(all three)_

- **[MUST]** `includeConfig` order: `conf/base.config` first and unconditional → test-profile includes
  inside `profiles { }` → institutional custom configs behind the offline guard → module configs last.
  _(all three)_

- **[MUST]** `manifest { }` carries `name`, `contributors[]` (with `github` and `orcid`), `homePage`,
  `description`, `mainScript`, `defaultBranch`, `nextflowVersion` pinned with the `!>=` strict prefix,
  `version`, `doi`. _(all three)_

- **[MUST]** Standard profile set present and in the conventional order: `debug, conda, mamba, docker,
arm64, emulate_amd64, singularity, podman, shifter, charliecloud, apptainer, wave`, then
  pipeline-specific profiles, then `test*` profiles last. _(all three)_

- **[MUST]** All four of `timeline`, `report`, `trace`, `dag` enabled, writing under
  `${params.outdir}/pipeline_info/` with `${params.trace_report_suffix}`. _(all three)_

- **[MUST]** `env { }` sets exactly `PYTHONNOUSERSITE`, `R_PROFILE_USER`, `R_ENVIRON_USER`,
  `JULIA_DEPOT_PATH`. _(all three, identical)_

- **[MUST]** All container registries default to `'quay.io'`. _(all three)_

## 2. Parameter naming and defaults

- **[MUST]** `snake_case` throughout. No camelCase params anywhere in any of the three.
- **[MUST]** Never default a string or path param to `''`. Use `null` for an optional file/path or a
  tri-state selector, `false` for a genuine binary toggle, and a real literal where a sensible default
  exists. The live tri-state is `ancestry_sd_filter = null`: the centroid rule is off, and any number
  switches it on at that many standard deviations. _(verified: zero `''` defaults across all three)_
- **[MUST]** Pick one toggle polarity per feature area and hold it. mag mixes `skip_binqc` with sibling
  `run_busco` / `run_checkm` for the _same_ feature area — the clearest naming defect in the reference set.
  - `skip_*` — stage is on by default, prefix turns it off. `skip_ancestry` is the only stage toggle here.
  - `run_*` / `use_*` — stage is off by default, prefix turns it on. None exists yet.
- **[MUST]** A gate that changes what a stage's product is _used for_ is not a stage toggle and is named for
  the action instead: `apply_sample_removals` (default `false`) and `ancestry_remove_mismatched` (default
  `true`, and read only inside that gate). Both stages run either way and publish either way; only the
  arrival of a removal list at `--remove` changes, so neither takes a `skip_*` or `run_*` prefix. Say so at
  the declaration, because the pair's polarities differ and the reason is the legacy behaviour they
  reproduce.
- **[MUST]** `save_*` for "persist an intermediate that is normally discarded", always boolean, default
  `false`. _(all three)_ None exists here: the published set is decided by scientific stage in
  `conf/modules/*.config`, not by a parameter.
- **[SHOULD]** Name a scientific threshold after the native flag it becomes, with no prefix, when the
  pipeline owns exactly one value of it for the run: `maf`, `geno`, `mind` and `hwe` become plink2's
  `--maf`, `--geno`, `--mind` and `--hwe`, so a user who knows plink2 needs no mapping table. Do not do this
  for a value the pipeline computes with itself rather than passing through.
- **[SHOULD]** Otherwise prefix by the stage that consumes the parameter, and keep the prefix exact: `ld_*`
  for the main pruning, `ancestry_ld_*` for the reference pruning, `sex_check_*` for the four `--check-sex`
  modifiers, `relatedness_*` for the KING classification. A stage that reuses a setting at a second scale
  gets its own prefixed copy, because the two values are independent.
- **[SHOULD]** Name file/path params by role rather than by format: `reference_panel` for the panel
  samplesheet, `reference_pop_data` for its label table, `high_ld_regions` for the region asset. None of the
  three reference pipelines is fully internally consistent; sarek's `<tool>_<artifact>` scheme is the
  cleanest model.
- Notes on rules with no live instance: a tool-choice enum param takes a `_tool` suffix (mag is consistent,
  rnaseq mixes `ribo_removal_tool` with bare `aligner`), and a pipeline with more than about ten combinable
  optional tools may use one regex-validated CSV-string param instead of per-tool booleans (sarek's
  `tools`). Neither applies here — every stage runs one implementation and every toggle keeps its own schema
  `description` and `help_text`, which a CSV token cannot carry. None of the three demonstrates a
  deprecated-param shim either; if one is needed, take it from the current `nf-core/tools` template.

## 3. `conf/base.config`

- **[MUST]** No `check_max()` function. It is fully retired — verified absent from all three.
- **[MUST]** No `resourceLimits` in `base.config`. Resource _capping_ belongs in `conf/test*.config`;
  `base.config` defines label-based _scaling_ only. _(all three, once terminology is normalised)_
- **[MUST]** Default (unlabelled) process resources set as `task.attempt`-scaled closures, before any
  label block. _(all three)_
- **[MUST]** All six standard labels present with strictly increasing cpu/memory/time:
  `process_single` < `process_low` < `process_medium` < `process_high`; plus `process_long` (time only) and
  `process_high_memory` (memory only). _(all three)_
- **[MUST]** `errorStrategy` retries on the standard transient exit statuses and finishes otherwise, with
  `maxErrors = '-1'`. _(all three)_
- **[MUST]** `withLabel:` blocks precede `withName:` blocks, and selectors in `base.config` are bare process
  names or bare regex alternations — never fully-qualified `WORKFLOW:SUBWORKFLOW:PROCESS` paths.
  _(all three)_
- **[MUST]** Remove the template's `// TODO nf-core: Check the defaults for all processes` comment once
  defaults are actually reviewed. Both rnaseq and sarek still carry it, unresolved.
- **[SHOULD]** A `process_gpu` label is a legitimate non-template extension where GPU-capable tools exist —
  all three independently converged on the same name and shape.

## 4. Module configs (`conf/modules/*.config`)

- **[MUST]** One config file per method family under `conf/modules/`, loaded by `includeConfig` from
  `nextflow.config`. There is no `conf/modules.config`.

  This reverses the rule this section originally carried, which required the single file. The property being
  bought is not a line count: it is that a stage ships as a **new file** rather than as an edit to a file
  every other stage also edits, which is a merge-conflict and review-scope property. The live split is two
  stage families plus reporting — `conf/modules/plink2.config` for the plink2 statistics and the terminal
  materialisation, `conf/modules/qc_decisions.config` for the pipeline-owned R and gawk decision and plot
  modules, and `conf/modules/multiqc.config` for the cross-stratum summary and the report — and each arrived
  in its own milestone of the legacy port, the ancestry route extending the first two rather than adding a
  third. The split is 2 of 3 in the reference set (rnaseq 32 files, sarek 39) so it is not exotic; mag's
  monolith is 41,970 bytes, which is what the single file becomes.

  Two obligations come with it, both verified against `nf-core pipelines lint` 4.1.0.dev0:
  - `.nf-core.yml` needs **both** `lint.files_exist: - conf/modules.config` (the `files_exist` check lists
    it as a required file) and `lint.modules_config: false` (the `modules_config` check reads the file to
    match `withName:` selectors against the workflow scripts). rnaseq and sarek both carry exactly this
    pair. One without the other still fails.
  - The process-wide default `publishDir` moves to `nextflow.config`, because it belongs to no method
    family. It is set `enabled: false` there: the published layout is organised by scientific stage, which
    no process-name-derived path can produce, and each per-family file opts its own processes in. sarek
    declines to have a default at all; mag keeps one and disables it. Do **not** leave a
    process-name-derived default enabled — it silently publishes every new module's intermediates under
    `outdir/<first-word-of-process-name>/`.

- **[MUST]** Order the `includeConfig` lines by pipeline stage and say so in a comment: a later file's
  `withName` selector wins where two match the same process. _(rnaseq's wording, worth copying verbatim)_
- **[MUST]** Each file uses the config banner defined in §1, followed by a `// STAGE NAME` comment.
- **[MUST]** Build multi-flag `ext.args` as a list joined and trimmed, never by string concatenation:

  ```groovy
  ext.args2 = {
      [
          "max-female-xf=${params.sex_check_max_female_xf}",
          "min-male-xf=${params.sex_check_min_male_xf}",
          "max-female-ycount=${params.sex_check_max_female_ycount}",
          "min-male-ycount=${params.sex_check_min_male_ycount}",
          'cols=+ycount',
      ].join(' ').trim()
  }
  ```

  _(all three; verified 12 / 6 / 16 occurrences of the `.join(' ').trim()` idiom)_

- **[MUST]** Suppress publishing of `versions.yml` with the verbatim idiom wherever a selector publishes
  without a `pattern`: _(all three; 8 / 31 / 30 occurrences)_

  ```groovy
  saveAs: { filename -> filename.equals('versions.yml') ? null : filename }
  ```

  Here that is the process-wide default and `MULTIQC`. Every other selector states an explicit `pattern`
  instead, which excludes `versions.yml` and the plink2 run logs by construction; do not add both, and do
  not publish with neither.

- **[MUST]** Order `withName:` blocks by pipeline stage within a file, and load
  `conf/modules/multiqc.config` last. _(all three)_
- **[MUST]** Use bare quoted process-name selectors by default (`withName: 'PLINK2_WRITESNPLIST'`), and
  distinguish call sites by **module alias** rather than by a fully-qualified `.*:SUBWORKFLOW:PROCESS` path,
  which appears nowhere in this repository: `PLINK2_MISSING_VARIANTS`, `PLINK2_MISSING_SAMPLES`,
  `PLINK2_MISSING_LADDER`, `PLINK2_MAKEBED_REFERENCE`, `PLINK2_INDEPPAIRWISE_REFERENCE`,
  `PLINK2_SCORE_REFERENCE`, `PLINK2_SCORE_STUDY`, `GENO_DECISIONS_LADDER`, `HIGHLD_EXCLUDE_REFERENCE`. An
  alias carries the distinction into the trace and the work directory too. Always quote the selector — sarek
  has one unquoted bare symbol and it is inconsistent with every other line in the repo. A regex alternation
  of aliases (`'PLINK2_SCORE_REFERENCE|PLINK2_SCORE_STUDY'`) is the right form for a setting two aliases must
  share exactly.
- **[MUST]** A selector matches a process **and every alias of it**, so one on the base name reaches each
  alias. An alias that must not inherit the base's publication re-points it or carries
  `publishDir = [enabled: false]`, and the comment at the selector says which case applies — live on
  `PLINK2_MAKEBED_REFERENCE` and `GENO_DECISIONS_LADDER`.
- **[SHOULD]** Prefer ternaries inside `ext.args` / `ext.prefix` / `publishDir.enabled` closures over
  top-level `if (params.x) { }` blocks wrapping a `withName:` block. mag has zero such `if` blocks.
- **[SHOULD]** `ext.prefix` as a static string for simple cases; as a closure interpolating the meta fields
  that actually distinguish the output when a process fans out across several axes
  (`{ "${meta.id}.ladder${meta.call_rate}" }` for one rung of the call-rate ladder).
- **[SHOULD]** A further `// STAGE NAME` banner comment per stage inside a file that covers more than one —
  `// ANCESTRY REFERENCE` in `plink2.config` and `// ANCESTRY` in `qc_decisions.config`.

## 5. `conf/test*.config`

- **[MUST]** Set `process.resourceLimits` near the top of every non-`_full` test config
  (`[cpus: 4, memory: '15.GB', time: '1.h']` or similar). _(all three)_
- **[MUST]** Keep `params { }` minimal: `config_profile_name`, `config_profile_description`, test-data
  paths, and only the feature flags that specific scenario needs. Never redefine unrelated defaults.
  _(all three)_
- **[MUST]** 1:1 naming between profile name and config filename (`test_full` ↔
  `conf/test_full.config`). _(all three)_
- **[MUST]** A `conf/test*.config` that is not itself a profile but a shared include of several test
  profiles is named for the role it resolves, not for a profile, and says at the top which profiles include
  it and why the work cannot live in each of them. `conf/test_fixtures.config` resolves the fixture
  samplesheet's relative fileset paths against the fixture base before nf-schema validates them, and is
  included by both `test` and `test_full`. A value set through `-c` is not visible to a profile expression,
  so a resolver of this kind belongs in an `includeConfig`, not in `tests/nextflow.config`.
- **[MUST]** A test profile whose subject is a cohort relationship, not a method option, replaces the cohort
  in its own config and reads the same fixture source: `test_alt_contig` includes `conf/test.config`, so the
  shared resolver chooses the base, and then writes its two-stratum samplesheet and its reference
  samplesheet against that base, as the resolver writes the reference samplesheet. A `-c` config cannot do
  this, because the profile's resolved base is not visible to it.
- **[SHOULD]** Pin test-data paths to a specific `nf-core/test-datasets` commit rather than a branch, so CI
  is reproducible. _(rnaseq)_ The live default `pipelines_testdata_base_path` is branch-pinned rather than
  commit-pinned; the fixture is generated deterministically and its planted defects are asserted by name, so
  a silent fixture change fails the pipeline test rather than passing it.
- **[SHOULD]** A small `process { withName: X { ext.args = ... } }` block inside a test config is acceptable
  and expected for CI determinism (fixed seeds, disabled timestamps). _(all three)_

## 6. `nextflow_schema.json`

- **[MUST]** `"$schema": "https://json-schema.org/draft/2020-12/schema"` and `"$defs"` — never the legacy
  `"definitions"` key. _(verified: all three)_
- **[MUST]** Top-level key order: `$schema`, `$id`, `title`, `description`, `type`, `$defs`, `allOf`.
  _(all three)_
- **[MUST]** `allOf` references groups in exactly the same order they are declared in `$defs`.
  _(all three, no exceptions)_
- **[MUST]** Every `$defs` group has a `fa_icon`, including pipeline-authored groups. mag gives icons only
  to the four template groups and none to its ten own groups; sarek is the model here.
- **[MUST]** Every `description` is a capitalised sentence ending in a period. mag violates this in 45 of
  173 descriptions — treat it as a checkable rule, not a suggestion.
- **[MUST]** Only `input_output_options` declares a group-level `required` array, and it lists exactly
  `["input", "outdir"]`. Every other input path is individually optional in JSON Schema, because whether it
  is needed depends on another parameter: the two reference paths are required unless `--skip_ancestry`, and
  that relationship is cross-parameter runtime validation (§7), not an unconditional JSON-Schema
  requirement. Never encode it as one.
- **[MUST]** `hidden: true` is reserved for `institutional_config_options` and `generic_options`
  boilerplate, plus at most one or two genuinely internal knobs. Never on a user-facing scientific or
  tool parameter, and never on `help`, `help_full`, `show_hidden`, `multiqc_title`, or
  `multiqc_methods_description`. _(all three)_ Verified live: every parameter of the six pipeline groups is
  visible, and every hidden parameter is template boilerplate.
- **[MUST]** `outdir` is `type: string`, `format: directory-path`, listed in `required`, never `hidden`,
  never given a `default`. _(all three)_
- **[MUST]** A parameter whose default is a `${projectDir}`-interpolated path records that expression
  verbatim as its schema `default`, so the generated parameter documentation names the shipped asset, and
  takes the `nextflow_config.config_defaults` exemption in `.nf-core.yml` (§8) because lint cannot resolve
  it. `high_ld_regions` is the live instance.
- **[MUST]** Constrain a value by `enum` when the vocabulary is closed and owned by the tool
  (`genome_build`, whose codes are exactly what plink2 `--split-par` accepts), and by `minimum` / `maximum`
  on every numeric threshold, so an out-of-range value fails before anything runs. Do not write an `enum`
  for a vocabulary the user supplies: the super-population labels come from `--reference_pop_data` itself
  and are validated against that file at ingress instead.
- **[SHOULD]** Keep the standard group names and put them in the conventional position:
  `input_output_options` first, the reference group early, `institutional_config_options` and
  `generic_options` last, pipeline-stage groups in between and in pipeline order. The live order is
  `input_output_options`, `reference_options`, `qc_threshold_options`, `ld_pruning_options`,
  `sample_qc_options`, `ancestry_options`, then the two template groups. The group is `reference_options`
  rather than `reference_genome_options` because the igenomes feature is skipped and the references are a
  panel and a region file, not a genome.
- Note: none of the three encodes cross-parameter conditional logic (`if`/`then`, `dependentRequired`) in
  `nextflow_schema.json` — that lives in runtime validation. Input schemas use it only for relationships
  local to one row.

## 7. `assets/schema_*.json`

### Pipeline relational-input contract

Three input files, three schemas, and one Groovy validation pass at ingress
(`subworkflows/local/utils_nfcore_gwasqc_pipeline/main.nf`). The schemas own what a single row must look
like; the Groovy pass owns every relationship a row cannot see.

- **[MUST]** `--input` (`assets/schema_input.json`) declares one stratum per row with the columns
  `id,ancestry,bed,bim,fam`. It is required unconditionally: there is no run without it.
- **[MUST]** `--reference_panel` (`assets/schema_reference.json`) declares one PLINK 1 fileset of the
  ancestry reference panel per row, with the columns `id,bed,bim,fam` — a whole-genome panel is one row, a
  per-chromosome panel one row per chromosome. `--reference_pop_data`
  (`assets/schema_reference_pop.json`) is the tab-separated label table of that panel, with the columns
  `FID`, `IID`, `pop` and `super_pop`. The two are an inseparable pair: the ancestry stage needs both, and
  ingress rejects a run that requests it with either missing rather than failing later. `--skip_ancestry`
  drops both.
- **[MUST]** A reference fileset carries no ancestry. The population table, not the panel samplesheet,
  labels reference samples, and `super_pop` is the only vocabulary the pipeline reads from it.
- **[MUST]** `meta` is always an **array**, even for a single field. A stratum row declares `meta: ["id"]`
  and `meta: ["ancestry"]` and nothing else; a reference row declares `meta: ["id"]` alone. The population
  table declares no `meta` at all, because it is consumed as a whole file — once at ingress for the sorted
  unique `super_pop` vocabulary and once per stratum by the classifier — never as a per-row channel item.
  rnaseq has one bare-string `"meta": "percent_mapped"` and it is a copy-paste defect.
  _(all three otherwise)_
- **[MUST]** Row-uniqueness uses the nf-schema keyword `uniqueEntries`, **not** the generic JSON-Schema
  `uniqueItems`, and it is placed at the **top level** of the schema, as a sibling of `items`:
  `uniqueEntries: ["id"]` in both `schema_input.json` and `schema_reference.json`. sarek places it _inside_
  `items`, where nf-schema discards it silently with no error and no warning, so that usage is a no-op
  rather than a precedent. `uniqueItems` only expresses whole-row uniqueness and is the wrong tool in every
  case. _(verified: `uniqueEntries` used in sarek and mag, `uniqueItems` appears zero times in all three)_
  - Its message names neither a column nor a file row and renders the offending pair as a Groovy map —
    measured against nf-schema 2.5.1: `-> Entry 2: Detected duplicate entries: [id:dup_id]`. That is
    accepted here because `id` is the output prefix of every file a stratum produces and the merge order of
    the reference panel, so a terse message that fires before anything runs beats a late collision. Where a
    spec instead requires every validation error to name the offending row and field, keep the duplicate
    check in the Groovy pass and do not add `uniqueEntries`.
- **[MUST]** `additionalProperties: false` on the `items` of a samplesheet whose columns define an identity,
  so an extra or misspelled column is an error rather than a silently ignored one — set on
  `schema_input.json` and `schema_reference.json`. It is deliberately absent from
  `schema_reference_pop.json`: that table is a third-party asset that commonly carries further columns, none
  of which the pipeline reads.
- **[MUST]** Every property carries a specific, human-readable `errorMessage` quoting the allowed values or
  extensions. mag omits it on two columns and those are the ones that produce unhelpful failures.
- **[MUST]** Every file-referencing column has `"format": "file-path"` and `"exists": true`. _(all three)_
- **[MUST]** Each input schema's `$id` and `title` match its own filename and the parameter it validates.
  mag's `schema_assembly_input.json` copies both verbatim from another schema — check this explicitly
  whenever more than one `assets/*.json` schema exists.
- **[MUST]** Use `enum` for a closed vocabulary and an **anchored** `pattern` otherwise. Every identifier
  and label column here is an anchored pattern, because the vocabulary is the user's: `"^\\S+$"` for an
  `id`, `FID`, `IID` or `pop`, and `"^[A-Za-z0-9][A-Za-z0-9_.-]*$"` for an `ancestry` and a `super_pop`. The
  narrower pattern on the two matched labels is load-bearing rather than cosmetic: a `super_pop` becomes a
  component of a published keep-list filename. mag's `assembler` column uses a bare alternation regex with
  no `^`/`$` anchors where an `enum` was correct.
- **[SHOULD]** ID patterns as `"^\\S+$"`; file patterns anchored and extension-specific
  (`"^\\S+\\.bed$"`), allowing an optional directory prefix but forbidding spaces.
- **[SHOULD]** `dependentRequired` for "column A requires column B"; `anyOf` for "at least one input family
  per row". _(sarek and mag)_ Neither is needed here: every column of every row is required.

### What the Groovy ingress pass owns

- **[MUST]** The three members of a fileset must share one basename, because plink2 addresses a fileset by a
  single prefix. JSON Schema validates each path independently and cannot compare them, so
  `validateInputFileset` checks it in Groovy and names the stratum and the three filenames it found. The
  same function validates a reference row, so both sides of the ancestry route share one basename contract.
  Never repair a mismatch downstream with `stageAs`, a rename, or a symlink.
- **[MUST]** A stratum's `ancestry` is checked against the sorted unique `super_pop` set read from
  `--reference_pop_data`, by `validateAncestryLabel`, and only when ancestry inference runs. The severity
  follows the consequence: a label outside the vocabulary lists **every** sample of the stratum as an
  ancestry mismatch, so it is **fatal** when that list would be applied — `--apply_sample_removals` with
  `--ancestry_remove_mismatched` — and a **warning** when the list is only published. Record the rule at the
  check; it is the one place where a parameter's value turns an ingress error into a log line.
- **[MUST]** The vocabulary is read once, here, from the table itself, and passed downstream as a validated
  value. Never reconstruct it later and never fall back to a built-in population list.
- **[MUST]** Validate the reference pair's presence here too — both paths, or `--skip_ancestry` — with one
  message naming all three parameters. Discovering it after the QC chain has run wastes the run.
- **[MUST]** Downstream stages consume the resulting trusted contract without revalidating it. A second
  check of an ingress-validated property is a review finding, not defensive depth.

## 8. `.nf-core.yml`

- **[MUST]** Keep `files_exist` and `files_unchanged` in sync with the actual repository. Both rnaseq and
  sarek list files they no longer contain (`awstest.yml` after replacement, `ci.yml` after renaming) —
  stale exemptions that mask real lint signal. An exemption for a file the repository intends never to have
  is not stale; an exemption for one it merely used to have is. The live `files_exist` list is exactly three
  entries: `conf/igenomes.config` and `conf/igenomes_ignored.config`, which follow from
  `template.skip_features: igenomes`, and `conf/modules.config`, which §4 explains.
- **[MUST]** Every exemption carries a comment saying what makes it permanent, and an exemption that comes
  in a required pair says so at both halves — `files_exist: conf/modules.config` and `modules_config: false`
  are useless apart.
- **[SHOULD]** Treat the count of lint exemptions as a proxy for template-deviation risk. mag needs two
  keys, sarek four, rnaseq five, and that ordering tracks how far each has drifted; this pipeline needs three
  (`files_exist`, `modules_config`, `nextflow_config`), all documented here. Justify every new one in the
  review that introduces it.
- **[SHOULD]** `nextflow_config.config_defaults` is the right exemption when a param's schema default
  genuinely cannot match the live value (a `${projectDir}`-interpolated default, or a deliberately-nulled
  default whose real value is documented in a comment above it). _(rnaseq and mag)_ The live instance is
  `params.high_ld_regions`, whose default is `"${projectDir}/assets/high_ld_regions_b38.bed"`; the schema
  records the same expression as a literal string so that the generated parameter documentation names the
  shipped asset.
