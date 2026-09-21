#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/gwasqc
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/nf-core/gwasqc
    Website: https://nf-co.re/gwasqc
    Slack  : https://nfcore.slack.com/channels/gwasqc
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { GWASQC                  } from './workflows/gwasqc'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_gwasqc_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_gwasqc_pipeline'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow NFCORE_GWASQC {
    take:
    samplesheet // channel: samplesheet read in from --input
    reference // channel: reference filesets read in from --reference_panel, empty when ancestry is skipped

    main:

    //
    // WORKFLOW: Run pipeline
    //
    GWASQC(
        samplesheet,
        reference,
        params.maf,
        params.geno,
        params.mind,
        params.hwe,
        params.high_ld_regions,
        params.reference_pop_data,
        params.ld_window_size,
        params.ld_step_size,
        params.ld_r2,
        params.relatedness_indiv_sd,
        params.relatedness_po_ibs0_max,
        params.skip_ancestry,
        params.ancestry_ld_window_size,
        params.ancestry_ld_step_size,
        params.ancestry_ld_r2,
        params.ancestry_n_pcs,
        params.ancestry_prob_threshold,
        params.ancestry_sd_filter,
        params.apply_sample_removals,
        params.ancestry_remove_mismatched,
        params.sample_qc_marker_set,
        params.small_n_threshold,
        params.ld_min_retained_fraction,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir,
    )

    emit:
    multiqc_report = GWASQC.out.multiqc_report // channel: /path/to/multiqc_report.html
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {
    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    PIPELINE_INITIALISATION(
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.reference_panel,
        params.reference_pop_data,
        params.skip_ancestry,
        params.apply_sample_removals,
        params.ancestry_remove_mismatched,
        params.sample_qc_marker_set,
        params.small_n_threshold,
        params.help,
        params.help_full,
        params.show_hidden,
    )

    //
    // WORKFLOW: Run main workflow
    //
    NFCORE_GWASQC(
        PIPELINE_INITIALISATION.out.samplesheet,
        PIPELINE_INITIALISATION.out.reference,
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION(
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
        NFCORE_GWASQC.out.multiqc_report,
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
