// Derive the sample QC decision lists and reports of the legacy chain for one PLINK fileset per stratum from
// the lists of the filter chain: LD pruning, the long-range LD and non-autosomal exclusion, the sex check, the
// heterozygosity report and KING relatedness, each a stats-only plink2 run on the original fileset.
// Pipeline-owned: the R decision modules carry the pipeline's thresholds, so this is not an upstream candidate.

// MODULE: Local to the pipeline
include { PLINK2_INDEPPAIRWISE  } from '../../../modules/local/plink2/indeppairwise/main'
include { HIGHLD_EXCLUDE        } from '../../../modules/local/highld_exclude/main'
include { PLINK2_CHECKSEX       } from '../../../modules/local/plink2/checksex/main'
include { SEX_CHECK_DECISIONS   } from '../../../modules/local/sex_check_decisions/main'
include { PLINK2_HET            } from '../../../modules/local/plink2/het/main'
include { HETEROZYGOSITY_PLOTS  } from '../../../modules/local/heterozygosity_plots/main'
include { PLINK2_MAKEKINGTABLE  } from '../../../modules/local/plink2/makekingtable/main'
include { RELATEDNESS_DECISIONS } from '../../../modules/local/relatedness_decisions/main'

workflow PLINK_SAMPLE_QC_LISTS {
    take:
    ch_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam), path(extract), [ path(exclude), ... ], path(remove), path(smiss) ]
    high_ld_regions // value: path to the BED of long-range LD regions
    ld_window_size // value: --indep-pairwise window, in variants
    ld_step_size // value: --indep-pairwise step, in variants
    ld_r2 // value: --indep-pairwise r-squared threshold
    relatedness_indiv_sd // value: standard deviations above the cohort mean kinship that flag an individual
    relatedness_po_ibs0_max // value: IBS0 at or below which a first-degree pair is parent-offspring

    main:

    // The variant lists of the filter chain define the QC'd variant set and the mind removals its sample set.
    // Pruning runs on that set over every chromosome, so that the sex check sees the pruned chromosome X; the
    // long-range LD and non-autosomal exclusion is applied afterwards, for the heterozygosity and relatedness
    // reports, as the legacy chain ordered the two. No other sample list is applied within this chain: the
    // lists it derives are published, and reach the terminal materialisation only under apply_sample_removals.

    //
    // MODULE: LD pruning of the QC'd variant set
    //
    PLINK2_INDEPPAIRWISE(
        ch_genotypes.map { meta, bed, bim, fam, extract, exclude, remove, _smiss -> [meta, bed, bim, fam, extract, exclude, [], remove] },
        ld_window_size,
        ld_step_size,
        ld_r2,
    )

    def ch_pruned_by_id = ch_genotypes
        .map { meta, bed, bim, fam, _extract, _exclude, remove, smiss -> [meta.id, meta, bed, bim, fam, remove, smiss] }
        .join(PLINK2_INDEPPAIRWISE.out.prune_in.map { meta, prune_in -> [meta.id, prune_in] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: Long-range LD and non-autosomal exclusion list over the pruned variants
    //
    HIGHLD_EXCLUDE(
        ch_pruned_by_id.map { _id, meta, _bed, bim, _fam, _remove, _smiss, prune_in -> [meta, bim, prune_in] },
        high_ld_regions,
    )

    //
    // MODULE: Sex check on the pruned set with chromosome X; the PAR split and thresholds reach plink2 through ext.args
    //
    PLINK2_CHECKSEX(
        ch_pruned_by_id.map { _id, meta, bed, bim, fam, remove, _smiss, prune_in -> [meta, bed, bim, fam, prune_in, [], [], remove] }
    )

    //
    // MODULE: Sex mismatch table, removal list and F histogram
    //
    SEX_CHECK_DECISIONS(PLINK2_CHECKSEX.out.sexcheck)

    def ch_autosomal_by_id = ch_pruned_by_id.join(HIGHLD_EXCLUDE.out.variant_exclude.map { meta, highld_exclude -> [meta.id, highld_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
    def ch_autosomal_inputs = ch_autosomal_by_id.map { _id, meta, bed, bim, fam, remove, _smiss, prune_in, highld_exclude -> [meta, bed, bim, fam, prune_in, highld_exclude, [], remove] }

    //
    // MODULE: Heterozygosity report on the pruned autosomal set outside the long-range LD regions
    //
    PLINK2_HET(ch_autosomal_inputs)

    //
    // MODULE: Heterozygosity histogram and heterozygosity-against-sex scatter, report only
    //
    def ch_het_plot_inputs = PLINK2_HET.out.het
        .map { meta, het -> [meta.id, meta, het] }
        .join(PLINK2_CHECKSEX.out.sexcheck.map { meta, sexcheck -> [meta.id, sexcheck] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, het, sexcheck -> [meta, het, sexcheck] }

    HETEROZYGOSITY_PLOTS(ch_het_plot_inputs)

    //
    // MODULE: KING kinship table on the same set; the kinship filter reaches plink2 through ext.args
    //
    PLINK2_MAKEKINGTABLE(ch_autosomal_inputs)

    //
    // MODULE: Pair classification, duplicate removal list, mean-kinship outliers and kinship histogram
    //
    def ch_relatedness_inputs = PLINK2_MAKEKINGTABLE.out.kin0
        .map { meta, kin0 -> [meta.id, meta, kin0] }
        .join(ch_pruned_by_id.map { id, _meta, _bed, _bim, _fam, remove, smiss, _prune_in -> [id, smiss, remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, kin0, smiss, remove -> [meta, kin0, smiss, remove] }

    RELATEDNESS_DECISIONS(
        ch_relatedness_inputs,
        relatedness_indiv_sd,
        relatedness_po_ibs0_max,
    )

    emit:
    prune_in              = PLINK2_INDEPPAIRWISE.out.prune_in // channel: [ val(meta), path(prune_in) ]
    prune_out             = PLINK2_INDEPPAIRWISE.out.prune_out // channel: [ val(meta), path(prune_out) ]
    highld_exclude        = HIGHLD_EXCLUDE.out.variant_exclude // channel: [ val(meta), path(highld_exclude) ]
    sexcheck              = PLINK2_CHECKSEX.out.sexcheck // channel: [ val(meta), path(sexcheck) ]
    sex_mismatch          = SEX_CHECK_DECISIONS.out.mismatch // channel: [ val(meta), path(sex_mismatch) ]
    sex_remove            = SEX_CHECK_DECISIONS.out.sample_remove // channel: [ val(meta), path(sex_remove) ]
    sex_check_hist_plot   = SEX_CHECK_DECISIONS.out.hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    het                   = PLINK2_HET.out.het // channel: [ val(meta), path(het) ]
    het_sex_scatter       = HETEROZYGOSITY_PLOTS.out.scatter_data // channel: [ val(meta), path(scatter_data) ]
    het_hist_plot         = HETEROZYGOSITY_PLOTS.out.hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    het_sex_scatter_plot  = HETEROZYGOSITY_PLOTS.out.scatter_plot // channel: [ val(meta), path(pdf), path(png) ]
    kin0                  = PLINK2_MAKEKINGTABLE.out.kin0 // channel: [ val(meta), path(kin0) ]
    relatedness_pairs     = RELATEDNESS_DECISIONS.out.pairs // channel: [ val(meta), path(pairs) ]
    relatedness_indiv     = RELATEDNESS_DECISIONS.out.indiv // channel: [ val(meta), path(indiv) ]
    relatedness_remove    = RELATEDNESS_DECISIONS.out.sample_remove // channel: [ val(meta), path(relatedness_remove) ]
    relatedness_outliers  = RELATEDNESS_DECISIONS.out.outliers // channel: [ val(meta), path(outliers) ]
    relatedness_hist_plot = RELATEDNESS_DECISIONS.out.hist_plot // channel: [ val(meta), path(pdf), path(png) ]
}
