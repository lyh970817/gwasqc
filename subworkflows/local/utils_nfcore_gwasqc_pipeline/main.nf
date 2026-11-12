//
// Subworkflow with functionality specific to the nf-core/gwasqc pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN   } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap        } from 'plugin/nf-schema'
include { samplesheetToList       } from 'plugin/nf-schema'
include { paramsHelp              } from 'plugin/nf-schema'
include { completionEmail         } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary       } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE   } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {
    take:
    version // boolean: Display version and exit
    validate_params // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir //  string: The output directory where the results will be saved
    input //  string: Path to input samplesheet
    reference_panel //  string: Path to the reference panel samplesheet, or null
    reference_pop_data //  string: Path to the reference population table, or null
    skip_ancestry // boolean: Skip the ancestry inference, which needs both reference files
    apply_sample_removals // boolean: Apply the sample removal lists to the QC'd fileset
    ancestry_remove_mismatched // boolean: Under apply_sample_removals, remove the samples not assigned to the stratum's ancestry
    sample_qc_marker_set //  string: Marker set of the sample checks, auto, study or shared
    small_n_threshold // integer: Under auto, the post-mind sample count below which a stratum uses the shared marker set
    missingness_mode //  string: How the missingness thresholds are applied, iterative or single
    geno //  number: Maximum per-variant missing-call rate
    mind //  number: Maximum per-sample missing-call rate
    help // boolean: Display help message and exit
    help_full // boolean: Show the full help message
    show_hidden // boolean: Show hidden parameters in the help message

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE(
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1,
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //

    def before_text = ""
    def after_text = ""
    before_text = """
-\033[2m----------------------------------------------------\033[0m-
                                        \033[0;32m,--.\033[0;30m/\033[0;32m,-.\033[0m
\033[0;34m        ___     __   __   __   ___     \033[0;32m/,-._.--~\'\033[0m
\033[0;34m  |\\ | |__  __ /  ` /  \\ |__) |__         \033[0;33m}  {\033[0m
\033[0;34m  | \\| |       \\__, \\__/ |  \\ |___     \033[0;32m\\`-._,-`-,\033[0m
                                        \033[0;32m`._,._,\'\033[0m
\033[0;35m  nf-core/gwasqc ${workflow.manifest.version}\033[0m
-\033[2m----------------------------------------------------\033[0m-
"""
    after_text = """${workflow.manifest.doi ? "\n* The pipeline\n" : ""}${workflow.manifest.doi.tokenize(",").collect { doi -> "    https://doi.org/${doi.trim().replace('https://doi.org/', '')}" }.join("\n")}${workflow.manifest.doi ? "\n" : ""}
* The nf-core framework
    https://doi.org/10.1038/s41587-020-0439-x

* Software dependencies
    https://github.com/nf-core/gwasqc/blob/master/CITATIONS.md
"""
    if (monochrome_logs) {
        before_text = before_text.replaceAll(/\033\[[0-9;]*m/, '')
    }

    command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN(
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        before_text,
        after_text,
        command,
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE(
        nextflow_cli_args
    )

    //
    // Validate the missingness thresholds against the mode that applies them
    //
    // The iterative mode applies the legacy call-rate ladder, which steps whole call-rate percentages from 90
    // and applies one threshold to variants and samples at each rung, so the last rung it applies is named by
    // a geno and mind that are equal and a whole percentage on the ladder.
    if (missingness_mode == 'iterative') {
        validateIterativeMissingness(geno, mind)
    }

    //
    // Validate the reference assets and read the super-population vocabulary of the population table
    //
    // The ancestry stage needs both reference files, and a stratum's ancestry label is matched against the
    // super-populations of the population table: under the removal gate a label outside that vocabulary would
    // list every sample of the stratum for removal, so it is rejected before anything runs; without the gate
    // the mismatch list is only published, so the label is merely warned about.
    //
    // The shared marker set of the sample checks is the ancestry route's, so it needs the reference too: a
    // forced `shared` without the reference is rejected here, and under `auto` a stratum whose input already
    // holds fewer samples than the threshold is certain to select `shared`, so it is rejected here as well;
    // a stratum that only falls below the threshold through the mind removals is rejected when the mode is
    // decided, after the filter chain.
    //
    def super_pops = null
    if (!skip_ancestry) {
        if (!reference_panel || !reference_pop_data) {
            error("[nf-core/gwasqc] ERROR: --reference_panel and --reference_pop_data are both required for ancestry inference; pass both, or set --skip_ancestry")
        }
        super_pops = samplesheetToList(reference_pop_data, "${projectDir}/assets/schema_reference_pop.json").collect { row -> row[3] }.unique().sort()
    }
    else if (sample_qc_marker_set == 'shared') {
        error("[nf-core/gwasqc] ERROR: --sample_qc_marker_set shared takes the sample-check markers from the ancestry route, so it needs --reference_panel and --reference_pop_data without --skip_ancestry; pass both, or choose --sample_qc_marker_set study")
    }
    def ancestry_label_is_fatal = !skip_ancestry && ((apply_sample_removals && ancestry_remove_mismatched) || sample_qc_marker_set == 'shared')

    //
    // Create channel from input file provided through params.input
    //
    def ch_samplesheet = channel.fromList(samplesheetToList(input, "${projectDir}/assets/schema_input.json"))
        .map { meta, bed, bim, fam -> validateInputFileset(meta, bed, bim, fam) }
        .map { meta, bed, bim, fam -> validateAncestryLabel(meta, bed, bim, fam, super_pops, ancestry_label_is_fatal) }
        .map { meta, bed, bim, fam -> validateSmallStratumHasReference(meta, bed, bim, fam, skip_ancestry, sample_qc_marker_set, small_n_threshold) }

    //
    // Create channel from the reference panel samplesheet provided through params.reference_panel
    //
    def ch_reference = skip_ancestry
        ? channel.empty()
        : channel.fromList(samplesheetToList(reference_panel, "${projectDir}/assets/schema_reference.json")).map { meta, bed, bim, fam -> validateInputFileset(meta, bed, bim, fam) }

    emit:
    samplesheet = ch_samplesheet // channel: [ val(meta), path(bed), path(bim), path(fam) ]
    reference   = ch_reference // channel: [ val(meta), path(bed), path(bim), path(fam) ], empty when ancestry is skipped
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {
    take:
    email //  string: email address
    email_on_fail //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    multiqc_report //  string: Path to MultiQC report

    main:
    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def multiqc_reports = multiqc_report.toList()

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(
                summary_params,
                email,
                email_on_fail,
                plaintext_email,
                outdir,
                monochrome_logs,
                multiqc_reports.getVal(),
            )
        }

        completionSummary(monochrome_logs)
    }

    workflow.onError {
        log.error("Pipeline failed. Please refer to troubleshooting docs for common issues: https://nf-co.re/docs/running/troubleshooting")
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Validate one samplesheet fileset, of a stratum or of the reference panel. plink2 addresses a PLINK 1
// fileset by a single prefix, so the three staged members must share one basename; a mismatch is a
// samplesheet error that the native tool would only report as a missing file.
//
def validateInputFileset(meta, bed, bim, fam) {
    def members = [bed, bim, fam]
    if (members.collect { member -> member.baseName }.unique().size() != 1) {
        error("[nf-core/gwasqc] ERROR: Please check the samplesheet -> the bed, bim and fam files of '${meta.id}' must share one basename, found: ${members.collect { member -> member.name }.join(', ')}")
    }
    return [meta, bed, bim, fam]
}

//
// Check one stratum's ancestry label against the super-populations of the reference population table, when
// ancestry inference runs. The label decides which assigned samples count as mismatches, so a label outside
// the vocabulary is fatal when the mismatch list is applied and a warning when it is only published.
//
def validateAncestryLabel(meta, bed, bim, fam, super_pops, fatal) {
    if (super_pops != null && !(meta.ancestry in super_pops)) {
        def message = "the ancestry label '${meta.ancestry}' of stratum '${meta.id}' is not a super-population of --reference_pop_data (${super_pops.join(', ')})"
        if (fatal) {
            error("[nf-core/gwasqc] ERROR: Please check input samplesheet -> ${message}; under --apply_sample_removals with --ancestry_remove_mismatched every sample of the stratum would be removed")
        }
        log.warn("[nf-core/gwasqc]: ${message}; every sample of the stratum will be listed as an ancestry mismatch")
    }
    return [meta, bed, bim, fam]
}

//
// Reject, before anything runs, thresholds the iterative ladder cannot apply: its last rung is the call rate
// 1 - geno, which must be a whole percentage from 90 to 99, and a rung applies one threshold to variants and
// samples, so mind must equal geno.
//
def validateIterativeMissingness(geno, mind) {
    def call_rate = 100 * (1 - (geno as double))
    def rung = Math.round(call_rate) as int
    if (Math.abs(call_rate - rung) > 1e-9 || rung < 90 || rung > 99 || Math.abs((geno as double) - (mind as double)) > 1e-12) {
        error("[nf-core/gwasqc] ERROR: --missingness_mode iterative applies the call-rate ladder from 90 % up to the call rate 1 - --geno, with one threshold for variants and samples at each rung, so --geno and --mind must be equal and one of 0.01, 0.02, ..., 0.10 (got --geno ${geno}, --mind ${mind}); choose such a pair, or --missingness_mode single for any other")
    }
}

//
// Reject, before anything runs, a stratum that `auto` is certain to send to the shared marker set while the
// ancestry route is skipped: the post-mind count can only be at or below the input count, so an input below
// the threshold decides the mode already. The residual case, a stratum that the mind removals take below the
// threshold, is decided and rejected in the workflow once the mind list exists.
//
def validateSmallStratumHasReference(meta, bed, bim, fam, skip_ancestry, sample_qc_marker_set, small_n_threshold) {
    if (skip_ancestry && sample_qc_marker_set == 'auto') {
        def samples = fam.countLines()
        if (samples < small_n_threshold) {
            error("[nf-core/gwasqc] ERROR: stratum '${meta.id}' has ${samples} samples, fewer than --small_n_threshold ${small_n_threshold}, so --sample_qc_marker_set auto selects the shared marker set, which needs --reference_panel and --reference_pop_data without --skip_ancestry; pass both, or force --sample_qc_marker_set study")
        }
    }
    return [meta, bed, bim, fam]
}

//
// Generate methods description for MultiQC
//
def toolCitationText() {
    // TODO nf-core: Optionally add in-text citation tools to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "Tool (Foo et al. 2023)" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def citation_text = ["Tools used in the workflow included:", "MultiQC (Ewels et al. 2016)", "."].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // TODO nf-core: Optionally add bibliographic entries to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = ["<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    }
    else {
        meta["doi_text"] = ""
    }
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine = new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
