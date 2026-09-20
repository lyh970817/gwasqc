/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// MODULE: Local to the pipeline
include { PLINK2_MAKEBED         } from '../modules/local/plink2/makebed/main'

// SUBWORKFLOW: Local to the pipeline
include { PLINK_QC_FILTER_LISTS  } from '../subworkflows/local/plink_qc_filter_lists'
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
    geno // value: maximum per-variant missing-call rate
    mind // value: maximum per-sample missing-call rate
    hwe // value: Hardy-Weinberg exact-test p-value floor
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    //
    // SUBWORKFLOW: MAF, missingness and Hardy-Weinberg filter lists, per stratum
    //
    PLINK_QC_FILTER_LISTS(
        ch_samplesheet,
        geno,
        mind,
        hwe,
    )

    //
    // MODULE: Materialise the QC'd fileset exactly once
    //
    // Variant lists: `--extract` keeps the MAF keep-list and `--exclude` drops the union of the geno and HWE
    // exclusions, so a variant survives only when it passed all three. Sample lists: `--remove` drops the mind
    // removals, which the legacy chain applied unconditionally. The sex, heterozygosity, relatedness and ancestry
    // decision lists of later milestones join the `--remove` set here, and only under
    // `params.apply_sample_removals`; nothing produces them yet.
    def ch_makebed_inputs = ch_samplesheet
        .map { meta, bed, bim, fam -> [meta.id, meta, bed, bim, fam] }
        .join(PLINK_QC_FILTER_LISTS.out.maf_snplist.map { meta, snplist -> [meta.id, snplist] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.geno_exclude.map { meta, geno_exclude -> [meta.id, geno_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.hwe_exclude.map { meta, hwe_exclude -> [meta.id, hwe_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(PLINK_QC_FILTER_LISTS.out.mind_remove.map { meta, mind_remove -> [meta.id, mind_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam, maf_snplist, geno_exclude, hwe_exclude, mind_remove ->
            [meta, bed, bim, fam, maf_snplist, [geno_exclude, hwe_exclude], [], mind_remove]
        }

    PLINK2_MAKEBED(ch_makebed_inputs)

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
    multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions // channel: [ path(versions.yml) ]
}
