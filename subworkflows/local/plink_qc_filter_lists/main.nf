// Derive the variant and sample filter lists of the MAF, missingness and Hardy-Weinberg chain for one PLINK
// fileset per stratum from stats-only plink2 runs, without materialising an intermediate fileset.
// Pipeline-owned: the R decision modules carry the pipeline's thresholds, so this is not an upstream candidate.

// MODULE: Local to the pipeline
include { PLINK2_WRITESNPLIST   } from '../../../modules/local/plink2/writesnplist/main'
include { PLINK2_MISSING        } from '../../../modules/local/plink2/missing/main'
include { MISSINGNESS_DECISIONS } from '../../../modules/local/missingness_decisions/main'
include { PLINK2_HARDY          } from '../../../modules/local/plink2/hardy/main'
include { HWE_DECISIONS         } from '../../../modules/local/hwe_decisions/main'

workflow PLINK_QC_FILTER_LISTS {
    take:
    ch_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ]
    geno // value: maximum per-variant missing-call rate
    mind // value: maximum per-sample missing-call rate
    hwe // value: Hardy-Weinberg exact-test p-value floor

    main:

    // Every plink2 run below starts from the unfiltered stratum fileset and receives the lists accumulated so
    // far; plink2 applies `--extract`, `--exclude` and `--remove` before it computes a report, so each report
    // describes the filtered set without a filtered fileset ever being written.

    //
    // MODULE: MAF keep-list; the threshold is native optional behaviour and reaches plink2 through ext.args
    //
    PLINK2_WRITESNPLIST(
        ch_genotypes.map { meta, bed, bim, fam -> [meta, bed, bim, fam, [], [], [], []] }
    )

    def ch_genotypes_by_id = ch_genotypes.map { meta, bed, bim, fam -> [meta.id, meta, bed, bim, fam] }
    def ch_maf_snplist_by_id = PLINK2_WRITESNPLIST.out.snplist.map { meta, snplist -> [meta.id, snplist] }

    //
    // MODULE: Missingness reports over the MAF-passing variants
    //
    def ch_missing_inputs = ch_genotypes_by_id
        .join(ch_maf_snplist_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam, snplist -> [meta, bed, bim, fam, snplist, [], [], []] }

    PLINK2_MISSING(ch_missing_inputs)

    //
    // MODULE: geno and mind decision lists plus the call-rate ladder, from the one --missing run
    //
    def ch_decision_inputs = PLINK2_MISSING.out.vmiss
        .map { meta, vmiss -> [meta.id, meta, vmiss] }
        .join(PLINK2_MISSING.out.smiss.map { meta, smiss -> [meta.id, smiss] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, vmiss, smiss -> [meta, vmiss, smiss] }

    MISSINGNESS_DECISIONS(ch_decision_inputs, geno, mind)

    //
    // MODULE: Hardy-Weinberg reports on the missingness-filtered set, as the legacy chain measured them
    //
    def ch_hardy_inputs = ch_genotypes_by_id
        .join(ch_maf_snplist_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(MISSINGNESS_DECISIONS.out.variant_exclude.map { meta, geno_exclude -> [meta.id, geno_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(MISSINGNESS_DECISIONS.out.sample_remove.map { meta, mind_remove -> [meta.id, mind_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam, snplist, geno_exclude, mind_remove -> [meta, bed, bim, fam, snplist, geno_exclude, [], mind_remove] }

    PLINK2_HARDY(ch_hardy_inputs)

    //
    // MODULE: HWE exclusion list; the chromosome X report exists only for filesets that carry chromosome X
    //
    def ch_hwe_inputs = PLINK2_HARDY.out.hardy
        .map { meta, hardy -> [meta.id, meta, hardy] }
        .join(PLINK2_HARDY.out.hardy_x.map { meta, hardy_x -> [meta.id, hardy_x] }, by: 0, remainder: true)
        .map { _id, meta, hardy, hardy_x -> [meta, hardy, hardy_x ?: []] }

    HWE_DECISIONS(ch_hwe_inputs, hwe)

    emit:
    maf_snplist        = PLINK2_WRITESNPLIST.out.snplist // channel: [ val(meta), path(snplist) ]
    vmiss              = PLINK2_MISSING.out.vmiss // channel: [ val(meta), path(vmiss) ]
    smiss              = PLINK2_MISSING.out.smiss // channel: [ val(meta), path(smiss) ]
    geno_exclude       = MISSINGNESS_DECISIONS.out.variant_exclude // channel: [ val(meta), path(geno_exclude) ]
    mind_remove        = MISSINGNESS_DECISIONS.out.sample_remove // channel: [ val(meta), path(mind_remove) ]
    missingness_ladder = MISSINGNESS_DECISIONS.out.ladder // channel: [ val(meta), path(ladder) ]
    hardy              = PLINK2_HARDY.out.hardy // channel: [ val(meta), path(hardy) ]
    hardy_x            = PLINK2_HARDY.out.hardy_x // channel: [ val(meta), path(hardy_x) ], optional
    hwe_exclude        = HWE_DECISIONS.out.variant_exclude // channel: [ val(meta), path(hwe_exclude) ]
}
