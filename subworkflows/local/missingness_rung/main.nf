// Apply one rung of the cumulative call-rate ladder to one PLINK fileset per stratum, as the legacy
// Iterative_Missingness.sh applied it: the rung's variant threshold over the variants and samples the previous
// rung kept, then its sample threshold over the variants that survive it, both thresholds 1 - call rate. Each
// rung's lists are cumulative and are the next rung's starting point; nothing is materialised, because every
// `--missing` run reads the unfiltered fileset with the lists carried so far.
// Pipeline-owned: the R decision modules carry the pipeline's thresholds, so this is not an upstream candidate.

// MODULE: Local to the pipeline
include { PLINK2_MISSING as PLINK2_MISSING_RUNG_VARIANTS } from '../../../modules/local/plink2/missing/main'
include { GENO_DECISIONS as GENO_DECISIONS_RUNG          } from '../../../modules/local/geno_decisions/main'
include { PLINK2_MISSING as PLINK2_MISSING_RUNG_SAMPLES  } from '../../../modules/local/plink2/missing/main'
include { MIND_DECISIONS as MIND_DECISIONS_RUNG          } from '../../../modules/local/mind_decisions/main'

workflow MISSINGNESS_RUNG {
    take:
    ch_lists // channel: [ val(meta), path(bed), path(bim), path(fam), path(maf_snplist), path(geno_exclude), path(mind_remove) ], the previous rung's cumulative lists, [] before the first rung
    call_rate // value: the rung's call rate in percent; the variant and the sample threshold are both 1 - call_rate / 100

    main:

    // The rung joins the metadata as a scatter key: it gives each rung's runs and lists a distinct identity,
    // and its consumers read it to order the rungs. A later rung overwrites it.
    def threshold = (100 - call_rate) / 100
    def ch_rung_by_id = ch_lists.map { meta, bed, bim, fam, maf_snplist, geno_exclude, mind_remove -> [meta.id, meta + [call_rate: call_rate], bed, bim, fam, maf_snplist, geno_exclude, mind_remove] }

    //
    // MODULE: Variant missingness over the MAF-passing variants and the samples the previous rung kept
    //
    PLINK2_MISSING_RUNG_VARIANTS(
        ch_rung_by_id.map { _id, meta, bed, bim, fam, maf_snplist, geno_exclude, mind_remove -> [meta, bed, bim, fam, maf_snplist, geno_exclude, [], mind_remove] }
    )

    //
    // MODULE: The rung's cumulative exclusion list, the previous rung's followed by its own
    //
    GENO_DECISIONS_RUNG(
        PLINK2_MISSING_RUNG_VARIANTS.out.vmiss
            .map { meta, vmiss -> [meta.id, vmiss] }
            .join(ch_rung_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .map { _id, vmiss, meta, _bed, _bim, _fam, _maf_snplist, geno_exclude, _mind_remove -> [meta, vmiss, threshold, geno_exclude] }
    )

    def ch_rung_geno_by_id = ch_rung_by_id.join(GENO_DECISIONS_RUNG.out.variant_exclude.map { meta, geno_exclude -> [meta.id, geno_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: Sample missingness over the variants the rung keeps and the samples the previous rung kept
    //
    PLINK2_MISSING_RUNG_SAMPLES(
        ch_rung_geno_by_id.map { _id, meta, bed, bim, fam, maf_snplist, _carried_geno_exclude, mind_remove, geno_exclude -> [meta, bed, bim, fam, maf_snplist, geno_exclude, [], mind_remove] }
    )

    //
    // MODULE: The rung's cumulative removal list, the previous rung's followed by its own
    //
    MIND_DECISIONS_RUNG(
        PLINK2_MISSING_RUNG_SAMPLES.out.smiss
            .map { meta, smiss -> [meta.id, smiss] }
            .join(ch_rung_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .map { _id, smiss, meta, _bed, _bim, _fam, _maf_snplist, _geno_exclude, mind_remove -> [meta, smiss, threshold, mind_remove] }
    )

    def ch_rung_lists = ch_rung_geno_by_id
        .join(MIND_DECISIONS_RUNG.out.sample_remove.map { meta, mind_remove -> [meta.id, mind_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam, maf_snplist, _carried_geno_exclude, _carried_mind_remove, geno_exclude, mind_remove -> [meta, bed, bim, fam, maf_snplist, geno_exclude, mind_remove] }

    emit:
    lists = ch_rung_lists // channel: [ val(meta), path(bed), path(bim), path(fam), path(maf_snplist), path(geno_exclude), path(mind_remove) ], meta.call_rate naming the rung
    smiss = PLINK2_MISSING_RUNG_SAMPLES.out.smiss // channel: [ val(meta), path(smiss) ], over the variants and samples the rung's variant threshold leaves
}
