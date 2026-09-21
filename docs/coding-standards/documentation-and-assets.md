# Documentation, assets, and auxiliary scripts

Applies to `README.md`, `docs/usage.md`, `docs/output.md`, `CHANGELOG.md`, `CITATIONS.md`, `assets/`, and
`bin/`.

This is the one area where the three reference pipelines are least consistent with each other, and each
carries verifiable defects. Several rules below are therefore **stricter than any of the three actually
achieve** — they are marked `(stricter than all three)` and exist because the observed variance is drift,
not design.

---

## 1. README.md

- **[MUST]** Logo block, identical in all three but for filenames: _(all three)_

  <!-- prettier-ignore -->
  ```text
  <h1>
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/nf-core-gwasqc_logo_dark.png">
      <img alt="nf-core/gwasqc" src="docs/images/nf-core-gwasqc_logo_light.png">
    </picture>
  </h1>
  ```

- **[MUST]** Three badge groups, blank-line separated, in this order: CI/status (Codespaces, CI, linting,
  AWS CI, Zenodo DOI, nf-test) → runtime/tooling (Nextflow version, template version, conda, docker,
  singularity, Seqera Platform launch) → community (Slack, Bluesky, Mastodon, YouTube). _(all three)_
  Do not append non-template badges — mag adds two and one of them is not even a link.
- **[MUST]** Section order, all as sentence-case `##` headings: Introduction → Pipeline summary → Usage →
  Scope → Legacy pipeline → Pipeline output → Credits → Contributions and Support → Citations. The first
  three and the last four are the shared nf-core core _(all three; sarek and mag carry the separate
  "Pipeline summary" section and it is the clearer of the two layouts — rnaseq folds a 16-item numbered list
  into Introduction instead)_. The two inserted sections are this pipeline's own:
  - **Scope** states in one paragraph what the release does _not_ do, so a reader does not infer it from
    silence — the PLINK-format route only, the deferred VCZ route, pre-QC batch merging out of scope, and the
    removal lists that are published rather than applied. A deferral recorded only in an issue is invisible
    to someone reading the repository.
  - **Legacy pipeline** names `GLAD_EDGI_NBR_qc_workflows/` as the read-only archive of the bash and R
    pipeline this one ports and states that nothing in it is executed. A tracked directory of
    runnable-looking scripts the pipeline never calls is otherwise the most misleading thing in the tree.
- **[MUST]** Spell it "Contributions and Support", not "Contributions & Support". _(2/3)_
- **[MUST]** The Usage section contains all four ingredients: a `> [!NOTE]` pointing at the nf-co.re setup
  docs, a fenced samplesheet CSV example and a fenced reference-panel CSV example, a fenced `bash` run
  command using `--input` / `--reference_panel` / `--reference_pop_data` / `--outdir` / `-profile`, and a
  `> [!WARNING]` about not using `-c` to set parameters. Preserve the nf-core boilerplate wording verbatim.
  Where a parameter of the run command is droppable, say which flag drops it — `--skip_ancestry` drops the
  two reference parameters — rather than showing a second command.
- **[MUST]** The Credits section names the authors and nothing else. Delete the template's
  "We thank the following people…" scaffold rather than leaving it standing above an empty list, and never
  fill it with a name that cannot be verified from the repository's own history.
- **[MUST]** The Citations section ends with the nf-core framework citation (Ewels et al., Nat Biotechnol
  2020, doi:10.1038/s41587-020-0439-x) and a pointer to `CITATIONS.md`. _(all three)_
- **[MUST]** The contributing link resolves to a file that exists. It is `docs/CONTRIBUTING.md` here;
  `.github/CONTRIBUTING.md` is the nf-core default and is absent from this repository. rnaseq's README links
  to contributing guidelines with neither file present. _(2/3)_
- **[MUST]** No `<!-- TODO nf-core: ... -->` comment survives into a release. Each one marks a sentence the
  template could not write; leaving it is indistinguishable from having nothing to say. The template's
  Zenodo-DOI citation comment goes with them once there is no DOI to add.

## 2. docs/usage.md

- **[MUST]** Opens with the nf-co.re website redirect banner and the "parameters are generated from the
  schema" note. _(all three)_
- **[MUST]** These sections are present: samplesheet input; a samplesheet format table; the reference panel
  and its population table; Running the pipeline; Updating; Reproducibility; core Nextflow arguments
  (`-profile`, `-resume`, `-c`); custom configuration and resource requests; nf-core/configs; running in the
  background; memory/CPU notes. _(all three, plus the reference section this pipeline needs)_
- **[MUST]** A Column/Description pipe table per declared input file. mag omits it and shows columns
  only as backticked lists, which is harder to scan. _(2/3)_
- **[MUST]** Every parameter of `nextflow_schema.json` that is not `hidden: true` appears somewhere in this
  file as a backticked `--flag`; the hidden institutional and generic boilerplate stays covered by the
  template prose. This is checkable mechanically and is the one rule that keeps the file from drifting behind
  the schema. The schema owns each parameter's full description, so one mention in the prose of the stage
  that consumes it is enough.
- **[MUST]** State every threshold's boundary exactly as implemented, in one place, including which
  comparisons are strict and which inclusive. A reader cannot infer a boundary from a flag name, and the
  boundaries are not uniform across the pipeline.
- **[MUST]** **Use GitHub-native alerts exclusively** — `> [!NOTE]`, `> [!WARNING]`, `> [!TIP]`,
  `> [!IMPORTANT]`. Never Docusaurus `:::note` fences, never `> **NB:**`.
  _(stricter than all three — verified mixing within a single file in every pipeline: rnaseq 7 GitHub
  alerts against 11 Docusaurus fences, sarek 5 against 2, mag 8 against 4. This is unresolved migration
  debt, not a style choice; GitHub alerts render correctly on GitHub without a Docusaurus site.)_
- **[MUST]** Every code fence carries a language tag, and data and params examples carry a title:
  ` ```bash `, ` ```csv title="samplesheet.csv" `, ` ```csv title="reference_panel.csv" `,
  ` ```tsv title="ref_pop.tsv" `, ` ```yaml title="params.yaml" `. _(all three use titled data examples;
  filenames follow this pipeline's contract and match the shipped `assets/` examples)_
- **[MUST]** Reference params in prose as backticked double-dash flags, for example `` `--reference_panel` ``.
  _(all three)_
- **[MUST]** A `> [!WARNING]` for each tool option a user could plausibly add through `ext.args` that would
  silently change a parsed column rather than failing — the `midp` modifier of `PLINK2_HARDY` is the live
  instance. A warning of this kind names the option, what the tool does to the report, and what the pipeline
  then does.
- **[MUST]** No duplicated sections. sarek repeats its custom-configuration and nf-core/configs content
  under two different headings.
- **[MUST]** Nothing in this file names a local path, a checkout or worktree, an unpublished branch, a
  development shell, or the tooling used to write it: the public reviewer boundary of
  [`contribution-boundaries.md`](contribution-boundaries.md) applies to every user-facing document.
- **[SHOULD]** Ship complete, valid samplesheet, reference-panel and population-table examples inline, and
  link the tracked `assets/` copies so a user can start from a file rather than from a fence.

## 3. docs/output.md

- **[MUST]** Every tool section wraps its file list in this exact skeleton — the single most consistent
  convention found anywhere in the reference set _(verified: 43 / 64 / 55 occurrences)_:

  <!-- prettier-ignore -->
  ```text
  <details markdown="1">
  <summary>Output files</summary>

  - `genotypes/<id>/`
    - `<id>.qc.bed`: PLINK 1 binary genotype table after all variant and sample lists were applied.

  </details>
  ```

  The blank lines after `<summary>` and before `</details>` are required for the bullet list to render,
  and the tags sit at column 0 rather than being indented. Check for stray or duplicated closing tags, and
  for `<details markdown = "1">` with stray spaces (sarek has one).

- **[MUST]** Output-file bullets follow ``- `filename`: Description.`` _(all three)_
- **[MUST]** Every published file is listed, and the authoritative source is the tree the pipeline test
  asserts: the `layout` map of `tests/default.nf.test` per stratum stage, plus the terminal fileset, the
  run-root summary, `multiqc/` and `pipeline_info/`. A file published and undocumented, or documented and
  unpublished, is a review finding at either end; check the test and this document against each other.
- **[MUST]** A file published only under a condition states that condition in its own bullet, in terms of the
  data or the parameter that decides it rather than of a process. A per-group file whose count depends on the
  data states which value set generates it and what the empty and unmatched cases produce.
- **[MUST]** Link each tool inline on first mention, immediately after opening its `<details>` block.
  _(all three)_
- **[MUST]** Intro paragraph, then a "Pipeline overview" list of stages, then per-stage sections, then
  MultiQC, then Pipeline information listing the `pipeline_info/` artifacts this pipeline actually writes,
  which are not the template's names: `nextflow.config` suffixes four of them with
  `${params.trace_report_suffix}` and writes the DAG as HTML, so the live set is
  `execution_timeline_<suffix>.html`, `execution_report_<suffix>.html`, `execution_trace_<suffix>.txt`,
  `pipeline_dag_<suffix>.html`, `params_<suffix>.json`, `nf_core_gwasqc_software_mqc_versions.yml`, and the
  `pipeline_report.html` / `pipeline_report.txt` email artefacts. Copying the template's
  `pipeline_dag.svg` / `software_versions.yml` / `params.json` list is the default defect here.
  _(all three carry the section; none of their file lists is verified against their own config)_
- **[SHOULD]** Render "Pipeline overview" as a nested TOC of anchor links rather than a flat stage list —
  it doubles as navigation once the file passes a few hundred lines. _(2/3: rnaseq and sarek)_
- **[SHOULD]** Where the pipeline publishes one summary table, document its columns as a pipe table and say
  for each column which published file it was counted from, so a number in a report can be traced without
  reading the module.

## 4. CHANGELOG.md

- **[MUST]** Header states the format the file actually follows, **and the body matches that claim**.
  rnaseq's preamble claims Keep a Changelog and then never uses its vocabulary — the exact
  documented-versus-actual mismatch to avoid.
- **[MUST]** Use the Keep a Changelog section headings: `### Added`, `### Changed`, `### Fixed`,
  `### Removed`, `### Deprecated`. Do not backtick-wrap them as mag does (`` ### `Added` ``).
  _(2/3 use the vocabulary; rnaseq substitutes eleven pipeline-specific headings instead)_
- **[MUST]** Only headings with entries appear. An empty `### Deprecated` left standing reads as an
  unfinished file rather than as a statement that nothing was deprecated, and Keep a Changelog itself asks
  for the sections that apply. `### Dependencies` is the exception to the vocabulary: it is the nf-core
  heading for the version table below and is kept because every reference pipeline uses it.
- **[MUST]** One version-heading format, fixed for the life of the file, and named in the preamble.
  **None of the three is worth copying** — rnaseq uses bracket+date with no codename, sarek a codename with
  no date, and mag's own format drifts release to release (`v`-prefix, hyphen placement, and brackets all
  vary). The chosen form here is `## [<version>] - <YYYY-MM-DD>`, the version linked to its release tag once
  one exists and the date a `[date]` placeholder while the version is still in development.
- **[MUST]** PR links as `[#NNNN](https://github.com/nf-core/gwasqc/pull/NNNN) - Description`. _(all three)_
- **[MUST]** Include a dependency-version table whenever tool versions change, with the columns
  `| Dependency | Old version | New version |`, and check every row against the module `environment.yml`
  files rather than against the previous table. A tool a module only _invokes_ from another tool's image,
  and therefore reports without declaring, is listed with that provenance stated. _(all three, minor
  column-name drift)_
- **[SHOULD]** No persistent "Unreleased" heading is required — all three land entries directly under the
  next release heading (grep-confirmed absent everywhere). Whichever convention is chosen, document it in
  the preamble accurately.

## 5. CITATIONS.md

- **[MUST]** Structure: `# nf-core/gwasqc: Citations` → pipeline / nf-core / Nextflow citation blockquotes →
  `## Pipeline tools` → optional `## R packages` → `## Software packaging/containerisation tools`.
  _(all three)_
- **[MUST]** The final section heading is exactly `## Software packaging/containerisation tools` — British
  spelling — listing Anaconda, Bioconda, BioContainers, Docker, Singularity. This is the single most
  consistent string across all three repos. _(all three)_
- **[MUST]** Per-tool entry format, the blockquote indented by two spaces so that it belongs to its bullet:
  _(all three)_

  ```markdown
  - [PLINK 2](https://doi.org/10.1186/s13742-015-0047-8)

    > Chang CC, Chow CC, Tellier LC, Vattikuti S, Purcell SM, Lee JJ. Second-generation PLINK: rising to
    > the challenge of larger and richer datasets. GigaScience. 2015;4(1):7. doi: 10.1186/s13742-015-0047-8.
    > PubMed PMID: 25722852; PubMed Central PMCID: PMC4342193.
  ```

  An unindented blockquote renders as a sibling of the list rather than as part of the entry; check every
  entry, not only the new one. A link-only entry with no citation blockquote is acceptable for a tool
  without a paper. _(all three)_

- **[MUST]** `## Pipeline tools` entries are strictly alphabetical, and so is `## R packages`. All three
  intend this and all three have stragglers appended out of order — check the tail of each section
  specifically.
- **[MUST]** List only what the pipeline invokes. A tool named in a comparison or considered and rejected is
  not a pipeline tool. A scientific method implemented inside another tool is cited where the method's own
  paper is what a reader needs — KING is cited for the kinship estimator although plink2 computes it.

## 6. assets/

- **[MUST]** One schema per declared input file, and every schema shipped: `schema_input.json`,
  `schema_reference.json` and `schema_reference_pop.json`. Their field contracts are owned by
  [`configuration-and-schema.md`](configuration-and-schema.md).
- **[MUST]** Ship an example of every samplesheet that validates against its schema — `samplesheet.csv` and
  `reference_panel.csv` — and link both from `docs/usage.md`. A tab-separated table whose example would be
  indistinguishable from a real asset is shown inline in the documentation instead.
- **[MUST]** If `assets/multiqc_config.yml` exists _(present in sarek and mag; rnaseq has none — verified)_:
  - `report_section_order` pins the three standard keys with the negative orders the template uses, under
    the ids this pipeline's report actually emits: `nf-core-gwasqc-methods-description: -1000`,
    `software_versions: -1001`, `nf-core-gwasqc-summary: -1002`. Pipeline-owned sections are ordered in the
    same map, and `custom_content.order` lists the stage parents in pipeline order; a comment states that a
    section's order sorts ascending within its stage, because the two mechanisms are easy to confuse.
  - `export_plots: true` and `disable_version_detection: true`.
  - `fn_clean_sample_names: false` wherever a table's row names are pipeline identifiers — stratum ids and
    sample ids here — which MultiQC's file-name cleaning would otherwise trim into collisions. State the
    reason in a comment; the failure it prevents is silent.
  - `custom_logo` either names a file that exists in `assets/` or is absent. mag's points at
    `mag_logo_mascot_light.png` while the real asset is `nf-core-mag_logo_light.png`. This pipeline declares
    none: `--multiqc_logo` remains the per-run override.
  - `report_comment` carries **no hardcoded release string**. Both sarek and mag hardcode one and both go
    stale. _(stricter than both)_ The live comment links the repository tree and the output documentation and
    names no version, so nothing in it has to be updated at release time.
- **[MUST]** `methods_description_template.yml`, if present, uses the standard key set (`id`, `description`,
  `section_name`, `section_href`, `plot_type: "html"`) and `${...}` Groovy placeholders. _(2/3)_
- **[SHOULD]** Email and sendmail templates keep the standard Groovy conditional
  (`<% if (!success){ ... } %>`), CID-embedded logo in the HTML variant, and base64 76-column embedding in
  the text variant. _(all three)_ The logo they embed, `assets/nf-core-gwasqc_logo_light.png`, is tracked
  separately from the README's `docs/images/` pair and both must exist.
- **[MUST]** A tracked scientific asset states its provenance in its own header and its build in its
  filename: `high_ld_regions_b38.bed` records the legacy awk rules it was derived from. An asset whose
  derivation lives only in a commit message cannot be checked against a cohort.
- Note: `multiqc_config.yml`, `methods_description_template.yml`, and Slack/Teams notification payloads
  (`adaptivecard.json`, `slackreport.json`) are **optional**. Their absence alone is not a review finding.

## 7. bin/ scripts

- **[MUST]** Prefer a module over a new `bin/` script. Only add a script when the logic genuinely cannot
  live in a module — rnaseq's `bin/` has shrunk to three files precisely because helpers migrated into
  modules. Script count is not a target: the three repos hold 3, 1 and 12, and this pipeline holds none,
  because every script is a module template and so is versioned, containerised and tested with the process
  that runs it.
- **[MUST]** `#!/usr/bin/env python3`, never bare `#!/usr/bin/env python`.
  _(stricter than all three — rnaseq and mag are each internally inconsistent about this)_
- **[MUST]** A license header line: `# Written by <Name> and released under the MIT license.` _(2/3)_
- **[MUST]** `argparse` for the CLI, with `def main(): ...` and
  `if __name__ == "__main__": sys.exit(main())`. _(dominant in all three but violated by individual scripts
  in each — treat as hard here)_
- **[MUST]** Pick `print()` or `logging` and hold it across the whole `bin/` directory. `print()` dominates
  the reference set; `logging` appears in exactly one script across all three repos.
  _(stricter than all three)_
- **[MUST]** R scripts: `#!/usr/bin/env Rscript`, `optparse` for arguments, explicit
  `stop("...", call. = FALSE)` checks for required arguments, and **one** naming case throughout — rnaseq's
  R script mixes dot.case, camelCase, and PascalCase in a single file. _(2/3 have R at all)_ A module's R
  template takes its arguments through Nextflow's template variables rather than `optparse`, and the
  `stop()` requirement applies to it unchanged: a missing required input column is a hard failure, never an
  empty result written with exit status 0.
- **[SHOULD]** Double-quoted strings; guard index access on positional arguments (mag's `split_fasta.py`
  has none).
- Notes on absences, none of which are review findings: no script in any of the three carries type hints;
  docstrings are sparse everywhere; only one script of roughly sixteen implements `--version`; and there
  are **no shell scripts in `bin/` in any of the three** (verified).

## 8. Prose style

- **[TOOLING]** Prettier configuration owns Markdown wrapping and layout. Review its execution evidence rather
  than source line length.
- **[MUST]** Inline links only — `[text](url)`. Reference-style `[text][ref]` links appear zero times
  across README, usage, output, and CITATIONS in all three repos. This is the cleanest rule in the set.
  _(all three)_
- **[MUST]** Sentence case for all headings. _(1/3 — mag is the only one that holds it; rnaseq and sarek
  both drift into Title Case within a single file. Chosen deliberately.)_
- **[MUST]** Backtick every CLI flag, file path, and samplesheet column name. _(all three)_
- **[SHOULD]** Second person for user-facing instructions ("You will need to create a samplesheet…").
  _(all three)_
- **[SHOULD]** Be consistent about whether a tool is written as a backticked name or an inline link within
  a given document. All three mix the two for the same tool in different places.
- **[SHOULD]** British spelling, matching the mandated `containerisation` heading in `CITATIONS.md`. Be
  aware this is unenforced and unenforceable without tooling: British and American forms coexist
  mid-paragraph in all three repos ("analyse"/"normalizes", "customise"/"customized",
  "summarises"/"summarizing"). Do not spend review time on it — if consistency matters, add a spellcheck
  config, which none of the three has.
