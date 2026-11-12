/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// MODULE: Local to the pipeline
include { PLINK2_MAKEBED         } from '../modules/local/plink2/makebed/main'
include { STRATUM_REPORT         } from '../modules/local/stratum_report/main'
include { QC_SUMMARY             } from '../modules/local/qc_summary/main'

// SUBWORKFLOW: Local to the pipeline
include { PLINK_QC_FILTER_LISTS  } from '../subworkflows/local/plink_qc_filter_lists'
include { PLINK_SAMPLE_QC_LISTS  } from '../subworkflows/local/plink_sample_qc_lists'
include { ANCESTRY_INFERENCE     } from '../subworkflows/local/ancestry_inference'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_gwasqc_pipeline'

// MODULE: Installed directly from nf-core/modules
include { MULTIQC                } from '../modules/nf-core/multiqc/main'

// SUBWORKFLOW: Consisting entirely of nf-core/modules
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'

// PLUGIN
include { paramsSummaryMap       } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow GWASQC {
    take:
    ch_samplesheet // channel: [ val(meta), path(bed), path(bim), path(fam) ]
    ch_reference // channel: [ val(meta), path(bed), path(bim), path(fam) ], one item per reference fileset; empty when ancestry is skipped
    maf // value: minor allele frequency threshold, applied by PLINK2_WRITESNPLIST through ext.args and recorded in the report
    geno // value: maximum per-variant missing-call rate; under `iterative`, the last rung of the call-rate ladder applied
    mind // value: maximum per-sample missing-call rate; under `iterative`, equal to geno
    hwe // value: Hardy-Weinberg exact-test p-value floor
    missingness_mode // value: `iterative`, the cumulative call-rate ladder applied up to the call rate 1 - geno, or `single`, geno and then mind once
    high_ld_regions // value: path to the BED of long-range LD regions
    genome_build // value: genome build of the study, which the reference panel must share
    reference_pop_data // value: path to the TSV of FID, IID, pop and super_pop per reference sample, or null when ancestry is skipped
    ld_window_size // value: --indep-pairwise window, in variants
    ld_step_size // value: --indep-pairwise step, in variants
    ld_r2 // value: --indep-pairwise r-squared threshold
    relatedness_indiv_sd // value: standard deviations above the cohort mean kinship that flag an individual
    relatedness_po_ibs0_max // value: IBS0 at or below which a first-degree pair is parent-offspring
    skip_ancestry // boolean: skip the ancestry inference against the reference panel
    ancestry_ld_window_size // value: --indep-pairwise window on the merged reference, in variants
    ancestry_ld_step_size // value: --indep-pairwise step on the merged reference, in variants
    ancestry_ld_r2 // value: --indep-pairwise r-squared threshold on the merged reference
    ancestry_n_pcs // value: number of reference principal components computed and projected
    ancestry_prob_threshold // value: class probability at or above which a study sample is assigned
    ancestry_sd_filter // value: standard deviations of the centroid rule, or null when the rule is off
    apply_sample_removals // boolean: apply the sex, relatedness and ancestry removal lists to the QC'd fileset
    ancestry_remove_mismatched // boolean: under apply_sample_removals, also remove the samples not assigned to the stratum's ancestry
    sample_qc_marker_set // value: marker set of the sample checks, auto, study or shared
    sample_qc_shared_reference // value: reference samples the shared marker set is filtered and pruned on, pooled or matched
    small_n_threshold // value: under auto, the post-mind sample count below which a stratum uses the shared marker set
    ld_min_retained_fraction // value: fraction of the QC'd variants below which study-mode pruning is reported as collapsed
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    //
    // SUBWORKFLOW: Non-standard contig, MAF, missingness and Hardy-Weinberg filter lists, per stratum
    //
    // The contig exclusion is applied at the MAF run, so the MAF keep-list that every later run extracts, the
    // terminal materialisation's included, carries the standard chromosomes only.
    PLINK_QC_FILTER_LISTS(
        ch_samplesheet,
        geno,
        mind,
        hwe,
        missingness_mode,
    )

    def ch_samplesheet_by_id = ch_samplesheet.map { meta, bed, bim, fam -> [meta.id, meta, bed, bim, fam] }
    def ch_filter_lists_by_id = ch_samplesheet_by_id
        .join(PLINK_QC_FILTER_LISTS.out.maf_snplist.map { meta, snplist -> [meta.id, snplist] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.geno_exclude.map { meta, geno_exclude -> [meta.id, geno_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.hwe_exclude.map { meta, hwe_exclude -> [meta.id, hwe_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.mind_remove.map { meta, mind_remove -> [meta.id, mind_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // The marker set of the sample checks, decided per stratum once the mind list exists
    //
    // Under `auto` a stratum with fewer samples than the threshold after the mind filter takes the `shared`
    // set, the reference-pruned markers of the ancestry route, because pruning its own variants over so few
    // samples collapses; every other stratum, and every stratum under a forced mode, takes the mode as given.
    // The decision travels in the metadata as `meta.sample_qc_marker_set`: the sample QC chain branches on it
    // per stratum and the report records it. A stratum sent to `shared` without the ancestry route is rejected
    // here; ingress rejected the cases that the input count alone decides.
    def ch_strata_by_id = ch_filter_lists_by_id.map { id, meta, bed, bim, fam, maf_snplist, geno_exclude, hwe_exclude, mind_remove ->
        def samples_after_mind = fam.countLines() - mind_remove.countLines()
        def mode = sample_qc_marker_set == 'auto' ? (samples_after_mind < small_n_threshold ? 'shared' : 'study') : sample_qc_marker_set
        if (mode == 'shared' && skip_ancestry) {
            error("[nf-core/gwasqc] ERROR: stratum '${meta.id}' has ${samples_after_mind} samples after the mind filter, fewer than --small_n_threshold ${small_n_threshold}, so --sample_qc_marker_set auto selects the shared marker set, which needs --reference_panel and --reference_pop_data without --skip_ancestry; pass both, or force --sample_qc_marker_set study")
        }
        [id, meta + [sample_qc_marker_set: mode], bed, bim, fam, maf_snplist, geno_exclude, hwe_exclude, mind_remove]
    }

    //
    // SUBWORKFLOW: Ancestry inference against the reference panel, per stratum
    //
    // The stratum reaches the reference as its QC'd variant set, the filter chain's lists, and its samples
    // are projected with the mind removals applied; the mismatch removal list is the one product the
    // terminal materialisation may consume, and the shared marker list, the merged reference fileset and the
    // ancestry-matched reference samples are what the shared marker set of the sample checks is built on.
    // When the stage is skipped every stratum carries an empty slot and no stratum is in shared mode.
    def ch_ancestry_remove_by_id = ch_samplesheet.map { meta, _bed, _bim, _fam -> [meta.id, []] }
    // [ id, summary, mismatch_remove, [ png, ... ] ] for the report; every slot empty when the stage is skipped
    def ch_ancestry_report_by_id = ch_samplesheet.map { meta, _bed, _bim, _fam -> [meta.id, [], [], []] }
    // [ meta, shared_markers, pgen, pvar, psam, reference_keep ] for the strata in shared mode
    def ch_shared_reference = channel.empty()
    if (!skip_ancestry) {
        ANCESTRY_INFERENCE(
            ch_strata_by_id.map { _id, meta, bed, bim, fam, maf_snplist, geno_exclude, hwe_exclude, mind_remove ->
                [meta, bed, bim, fam, maf_snplist, [geno_exclude, hwe_exclude], mind_remove]
            },
            ch_reference,
            file(reference_pop_data),
            file(high_ld_regions),
            genome_build,
            ancestry_ld_window_size,
            ancestry_ld_step_size,
            ancestry_ld_r2,
            ancestry_n_pcs,
            ancestry_prob_threshold,
            ancestry_sd_filter ?: 0,
            sample_qc_shared_reference,
        )
        ch_ancestry_remove_by_id = ANCESTRY_INFERENCE.out.mismatch_remove.map { meta, mismatch_remove -> [meta.id, mismatch_remove] }
        ch_ancestry_report_by_id = ANCESTRY_INFERENCE.out.summary
            .map { meta, summary -> [meta.id, summary] }
            .join(ch_ancestry_remove_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .join(ANCESTRY_INFERENCE.out.pc1_pc2_plot.map { meta, _pdf, png -> [meta.id, png] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .join(ANCESTRY_INFERENCE.out.pc3_pc4_plot.map { meta, _pdf, png -> [meta.id, png] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .map { id, summary, mismatch_remove, pc1_pc2, pc3_pc4 -> [id, summary, mismatch_remove, [pc1_pc2, pc3_pc4]] }
        // The ancestry route restores the stratum's own map at every gather, so its products carry the mode;
        // the shared markers and the keep list exist for the shared strata alone.
        ch_shared_reference = ANCESTRY_INFERENCE.out.shared_markers
            .map { meta, shared_markers -> [meta.id, meta, shared_markers] }
            .join(ANCESTRY_INFERENCE.out.reference_genotypes.filter { meta, _pgen, _pvar, _psam -> meta.sample_qc_marker_set == 'shared' }.map { meta, pgen, pvar, psam -> [meta.id, pgen, pvar, psam] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .join(ANCESTRY_INFERENCE.out.reference_keep.map { meta, reference_keep -> [meta.id, reference_keep] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .map { _id, meta, shared_markers, pgen, pvar, psam, reference_keep -> [meta, shared_markers, pgen, pvar, psam, reference_keep] }
    }

    //
    // SUBWORKFLOW: Sex check, heterozygosity and relatedness lists and reports, per stratum, on the marker
    // set its mode selects
    //
    // The duplicate rule compares the sample missingness over the MAF-passing variants before the geno filter,
    // the report the legacy chain compared.
    def ch_sample_qc_inputs = ch_strata_by_id
        .join(PLINK_QC_FILTER_LISTS.out.smiss_maf.map { meta, smiss -> [meta.id, smiss] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam, maf_snplist, geno_exclude, hwe_exclude, mind_remove, smiss ->
            [meta, bed, bim, fam, maf_snplist, [geno_exclude, hwe_exclude], mind_remove, smiss]
        }

    PLINK_SAMPLE_QC_LISTS(
        ch_sample_qc_inputs,
        ch_shared_reference,
        file(high_ld_regions),
        ld_window_size,
        ld_step_size,
        ld_r2,
        relatedness_indiv_sd,
        relatedness_po_ibs0_max,
    )

    //
    // MODULE: Materialise the QC'd fileset exactly once
    //
    // Variant lists: `--extract` keeps the MAF keep-list and `--exclude` drops the union of the geno and HWE
    // exclusions, so a variant survives only when it passed all three. Sample lists: `--remove` drops the mind
    // removals, which the legacy chain applied unconditionally; the sex-mismatch and relatedness removals join
    // the `--remove` set only under `apply_sample_removals`, as the legacy chain never applied them, and the
    // ancestry mismatch removals join it under the same gate when `ancestry_remove_mismatched` holds. Every
    // sample decision is a removal list, so the gate is one union at one slot and `--keep` stays empty.
    def ch_makebed_inputs = ch_strata_by_id
        .join(PLINK_SAMPLE_QC_LISTS.out.sex_remove.map { meta, sex_remove -> [meta.id, sex_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_SAMPLE_QC_LISTS.out.relatedness_remove.map { meta, relatedness_remove -> [meta.id, relatedness_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_ancestry_remove_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam, maf_snplist, geno_exclude, hwe_exclude, mind_remove, sex_remove, relatedness_remove, ancestry_remove ->
            def gated = [sex_remove, relatedness_remove] + (ancestry_remove_mismatched && ancestry_remove ? [ancestry_remove] : [])
            def remove = apply_sample_removals ? [mind_remove] + gated : mind_remove
            [meta, bed, bim, fam, maf_snplist, [geno_exclude, hwe_exclude], [], remove]
        }

    PLINK2_MAKEBED(ch_makebed_inputs)

    //
    // MODULE: Per-stratum QC summary row and MultiQC fragments, from the lists, tables and figures above
    //
    // Every count the report carries is read from a published list or table, never from a log; the figures
    // are gathered by the report section they belong to. The QC'd fileset closes the row with what left. The
    // study-side pruning lists exist only for the strata in study mode and the shared marker list only for
    // those in shared mode, so the strata of the other mode contribute an empty slot to each and every join
    // stays strict: a join with a remainder pads nothing when the other channel is empty, which is what a
    // run with every stratum in one mode produces.
    def ch_variant_qc_images_by_id = PLINK_QC_FILTER_LISTS.out.vmiss_hist_plot
        .map { meta, _pdf, png -> [meta.id, png] }
        .join(PLINK_QC_FILTER_LISTS.out.smiss_hist_plot.map { meta, _pdf, png -> [meta.id, png] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.ladder_plot.map { meta, _pdf, png -> [meta.id, png] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.hwe_hist_plot.map { meta, _pdf, png -> [meta.id, png] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.hwe_window_plot.map { meta, _pdf, png -> [meta.id, png] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { id, vmiss_hist, smiss_hist, ladder, hwe_hist, hwe_window -> [id, [vmiss_hist, smiss_hist, ladder, hwe_hist, hwe_window]] }
    def ch_heterozygosity_images_by_id = PLINK_SAMPLE_QC_LISTS.out.het_hist_plot
        .map { meta, _pdf, png -> [meta.id, png] }
        .join(PLINK_SAMPLE_QC_LISTS.out.het_sex_scatter_plot.map { meta, _pdf, png -> [meta.id, png] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { id, het_hist, het_sex_scatter -> [id, [het_hist, het_sex_scatter]] }
    // [ id, [] ] for the strata of each mode, the empty slot of the lists the other mode produces
    def ch_study_empty_by_id = ch_strata_by_id
        .filter { _id, meta, _bed, _bim, _fam, _maf_snplist, _geno_exclude, _hwe_exclude, _mind_remove -> meta.sample_qc_marker_set == 'study' }
        .map { id, _meta, _bed, _bim, _fam, _maf_snplist, _geno_exclude, _hwe_exclude, _mind_remove -> [id, []] }
    def ch_shared_empty_by_id = ch_strata_by_id
        .filter { _id, meta, _bed, _bim, _fam, _maf_snplist, _geno_exclude, _hwe_exclude, _mind_remove -> meta.sample_qc_marker_set == 'shared' }
        .map { id, _meta, _bed, _bim, _fam, _maf_snplist, _geno_exclude, _hwe_exclude, _mind_remove -> [id, []] }
    // [ id, prune_in, highld_exclude, shared_markers, shared_reference, n_reference_matched ], one item per
    // stratum, each list slot empty for the mode that does not produce it; the reference used and the size of
    // the matched group are those the ancestry route chose, NA for a stratum in study mode
    def ch_marker_lists_by_id = PLINK_SAMPLE_QC_LISTS.out.prune_in
        .map { meta, prune_in -> [meta.id, prune_in] }
        .mix(ch_shared_empty_by_id)
        .join(PLINK_SAMPLE_QC_LISTS.out.highld_exclude.map { meta, highld_exclude -> [meta.id, highld_exclude] }.mix(ch_shared_empty_by_id), by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_shared_reference.map { meta, shared_markers, _pgen, _pvar, _psam, _reference_keep -> [meta.id, shared_markers, meta.shared_reference, meta.n_reference_matched] }.mix(ch_study_empty_by_id.map { id, empty -> [id, empty, 'NA', 'NA'] }), by: 0, failOnDuplicate: true, failOnMismatch: true)

    def ch_report_inputs = ch_strata_by_id
        .map { id, meta, _bed, bim, fam, maf_snplist, geno_exclude, hwe_exclude, mind_remove -> [id, meta, bim, fam, maf_snplist, geno_exclude, mind_remove, hwe_exclude] }
        .join(PLINK_QC_FILTER_LISTS.out.contig_exclude.map { meta, contig_exclude -> [meta.id, contig_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.missingness_ladder.map { meta, ladder -> [meta.id, ladder] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_marker_lists_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_SAMPLE_QC_LISTS.out.sex_mismatch.map { meta, sex_mismatch -> [meta.id, sex_mismatch] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_SAMPLE_QC_LISTS.out.het.map { meta, het -> [meta.id, het] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_SAMPLE_QC_LISTS.out.relatedness_pairs.map { meta, pairs -> [meta.id, pairs] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_SAMPLE_QC_LISTS.out.relatedness_remove.map { meta, relatedness_remove -> [meta.id, relatedness_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_SAMPLE_QC_LISTS.out.relatedness_outliers.map { meta, outliers -> [meta.id, outliers] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_ancestry_report_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK2_MAKEBED.out.bed.map { meta, _bed, bim, fam -> [meta.id, bim, fam] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_variant_qc_images_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_SAMPLE_QC_LISTS.out.sex_check_hist_plot.map { meta, _pdf, png -> [meta.id, [png]] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_heterozygosity_images_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_SAMPLE_QC_LISTS.out.relatedness_hist_plot.map { meta, _pdf, png -> [meta.id, [png]] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bim, fam, maf_snplist, geno_exclude, mind_remove, hwe_exclude, contig_exclude, ladder, prune_in, highld_exclude, shared_markers, shared_reference, n_reference_matched, sex_mismatch, het, relatedness_pairs, relatedness_remove, relatedness_outliers, ancestry_summary, ancestry_mismatch_remove, ancestry_images, qc_bim, qc_fam, variant_qc_images, sex_check_images, heterozygosity_images, relatedness_images ->
            [meta, fam, bim, contig_exclude, maf_snplist, geno_exclude, mind_remove, hwe_exclude, ladder, prune_in, highld_exclude, shared_markers, shared_reference, n_reference_matched, sex_mismatch, het, relatedness_pairs, relatedness_remove, relatedness_outliers, ancestry_summary, ancestry_mismatch_remove, qc_bim, qc_fam, variant_qc_images, sex_check_images, heterozygosity_images, relatedness_images, ancestry_images]
        }

    STRATUM_REPORT(
        ch_report_inputs,
        maf,
        geno,
        mind,
        hwe,
        missingness_mode,
        ld_min_retained_fraction,
        sample_qc_shared_reference,
        apply_sample_removals,
        ancestry_remove_mismatched,
    )

    //
    // MODULE: Cross-stratum summary, published at the run root, and the per-stage MultiQC tables cut from it
    //
    QC_SUMMARY(STRATUM_REPORT.out.summary.map { _meta, summary -> summary }.collect())

    ch_multiqc_files = ch_multiqc_files.mix(STRATUM_REPORT.out.multiqc.map { _meta, fragments -> fragments })
    ch_multiqc_files = ch_multiqc_files.mix(QC_SUMMARY.out.multiqc)

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'nf_core_' + 'gwasqc_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'gwasqc'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    emit:
    genotypes      = PLINK2_MAKEBED.out.bed // channel: [ val(meta), path(bed), path(bim), path(fam) ]
    summary        = QC_SUMMARY.out.summary // channel: path(gwasqc_summary.tsv)
    multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions // channel: [ path(versions.yml) ]
}
