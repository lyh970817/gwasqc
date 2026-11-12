// Derive the sample QC decision lists and reports of the legacy chain for one PLINK fileset per stratum from
// the lists of the filter chain: the sex check, the heterozygosity report and KING relatedness, each a
// stats-only plink2 run on the original fileset, over the marker set the stratum's mode selects. In `study`
// mode the markers are the stratum's own LD-pruned QC'd variants after the long-range LD and non-autosomal
// exclusion; in `shared` mode they are the harmonised, reference-pruned markers of the ancestry route, with
// the ancestry-matched reference samples as the heterozygosity baseline.
// Pipeline-owned: the R decision modules carry the pipeline's thresholds, so this is not an upstream candidate.

// MODULE: Local to the pipeline
include { PLINK2_INDEPPAIRWISE               } from '../../../modules/local/plink2/indeppairwise/main'
include { HIGHLD_EXCLUDE                     } from '../../../modules/local/highld_exclude/main'
include { PLINK2_FREQ                        } from '../../../modules/local/plink2/freq/main'
include { PLINK2_HET as PLINK2_HET_REFERENCE } from '../../../modules/local/plink2/het/main'
include { PLINK2_CHECKSEX                    } from '../../../modules/local/plink2/checksex/main'
include { SEX_CHECK_DECISIONS                } from '../../../modules/local/sex_check_decisions/main'
include { PLINK2_HET                         } from '../../../modules/local/plink2/het/main'
include { HETEROZYGOSITY_PLOTS               } from '../../../modules/local/heterozygosity_plots/main'
include { PLINK2_MAKEKINGTABLE               } from '../../../modules/local/plink2/makekingtable/main'
include { RELATEDNESS_DECISIONS              } from '../../../modules/local/relatedness_decisions/main'

workflow PLINK_SAMPLE_QC_LISTS {
    take:
    ch_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam), path(extract), [ path(exclude), ... ], path(remove), path(smiss) ]; meta.sample_qc_marker_set is `study` or `shared`; smiss is the sample missingness over the MAF-passing variants before the geno filter, the duplicate rule's basis
    ch_reference // channel: [ val(meta), path(shared_markers), path(pgen), path(pvar), path(psam), path(reference_keep) ], one item per stratum in shared mode: the shared marker list, the merged reference fileset and the reference samples of the stratum's super-population, all from the ancestry route
    high_ld_regions // value: path to the BED of long-range LD regions
    ld_window_size // value: --indep-pairwise window, in variants
    ld_step_size // value: --indep-pairwise step, in variants
    ld_r2 // value: --indep-pairwise r-squared threshold
    relatedness_indiv_sd // value: standard deviations above the cohort mean kinship that flag an individual
    relatedness_po_ibs0_max // value: IBS0 at or below which a first-degree pair is parent-offspring

    main:

    // The variant lists of the filter chain define the QC'd variant set and the mind removals its sample set.
    // No other sample list is applied within this chain: the lists it derives are published, and reach the
    // terminal materialisation only under apply_sample_removals. The two modes prepare their inputs apart and
    // meet at the three plink2 checks, which run once over the union.
    def ch_by_mode = ch_genotypes.branch { meta, _bed, _bim, _fam, _extract, _exclude, _remove, _smiss ->
        shared: meta.sample_qc_marker_set == 'shared'
        study: true
    }

    // STUDY MODE
    //
    // Pruning runs on the QC'd set over every chromosome, so that the sex check sees the pruned chromosome X;
    // the long-range LD and non-autosomal exclusion is applied afterwards, for the heterozygosity and
    // relatedness reports, as the legacy chain ordered the two.

    //
    // MODULE: LD pruning of the QC'd variant set
    //
    PLINK2_INDEPPAIRWISE(
        ch_by_mode.study.map { meta, bed, bim, fam, extract, exclude, remove, _smiss -> [meta, bed, bim, fam, extract, exclude, [], remove] },
        ld_window_size,
        ld_step_size,
        ld_r2,
    )

    def ch_study_by_id = ch_by_mode.study
        .map { meta, bed, bim, fam, _extract, _exclude, remove, _smiss -> [meta.id, meta, bed, bim, fam, remove] }
        .join(PLINK2_INDEPPAIRWISE.out.prune_in.map { meta, prune_in -> [meta.id, prune_in] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: Long-range LD and non-autosomal exclusion list over the pruned variants
    //
    HIGHLD_EXCLUDE(
        ch_study_by_id.map { _id, meta, _bed, bim, _fam, _remove, prune_in -> [meta, bim, prune_in] },
        high_ld_regions,
    )

    def ch_study_checksex_inputs = ch_study_by_id.map { _id, meta, bed, bim, fam, remove, prune_in -> [meta, bed, bim, fam, prune_in, [], [], remove] }
    def ch_study_autosomal_inputs = ch_study_by_id
        .join(HIGHLD_EXCLUDE.out.variant_exclude.map { meta, highld_exclude -> [meta.id, highld_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam, remove, prune_in, highld_exclude -> [meta, bed, bim, fam, prune_in, highld_exclude, [], remove] }
    // The heterozygosity report of the study mode keeps the study's own frequencies as its basis.
    def ch_study_het_inputs = ch_study_autosomal_inputs.map { meta, bed, bim, fam, extract, exclude, keep, remove -> [meta, bed, bim, fam, extract, exclude, keep, remove, []] }

    // SHARED MODE
    //
    // The shared markers already carry the study's QC, the harmonisation, the reference-side MAF and
    // missingness filters, the long-range LD and non-autosomal exclusion and the reference-side pruning, on
    // the pooled or the ancestry-matched reference samples as the run chose, so no study-side pruning runs.
    // The heterozygosity baseline is the reference samples of the stratum's own super-population, selected
    // by the ancestry route: their allele frequencies over the shared markers standardise the study's F
    // through `--read-freq`, and their own report is drawn beneath the study's. The sex check takes every QC-passing
    // chromosome X and Y variant unpruned, because the reference carries no chromosome X and pruning X over a
    // handful of samples is what starved the legacy check.

    def ch_shared_by_id = ch_by_mode.shared
        .map { meta, bed, bim, fam, extract, exclude, remove, _smiss -> [meta.id, meta, bed, bim, fam, extract, exclude, remove] }
        .join(ch_reference.map { meta, shared_markers, pgen, pvar, psam, keep -> [meta.id, shared_markers, pgen, pvar, psam, keep] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: Allele frequencies of the matched reference samples over the shared markers
    //
    PLINK2_FREQ(
        ch_shared_by_id.map { _id, meta, _bed, _bim, _fam, _extract, _exclude, _remove, shared_markers, pgen, pvar, psam, keep -> [meta, pgen, pvar, psam, shared_markers, [], keep, []] }
    )

    def ch_shared_freq_by_id = ch_shared_by_id.join(PLINK2_FREQ.out.afreq.map { meta, afreq -> [meta.id, afreq] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: Heterozygosity report of the matched reference samples over the same markers and frequencies
    //
    PLINK2_HET_REFERENCE(
        ch_shared_freq_by_id.map { _id, meta, _bed, _bim, _fam, _extract, _exclude, _remove, shared_markers, pgen, pvar, psam, keep, afreq -> [meta, pgen, pvar, psam, shared_markers, [], keep, [], afreq] }
    )

    def ch_shared_checksex_inputs = ch_shared_by_id.map { _id, meta, bed, bim, fam, extract, exclude, remove, _shared_markers, _pgen, _pvar, _psam, _keep -> [meta, bed, bim, fam, extract, exclude, [], remove] }
    def ch_shared_het_inputs = ch_shared_freq_by_id.map { _id, meta, bed, bim, fam, _extract, _exclude, remove, shared_markers, _pgen, _pvar, _psam, _keep, afreq -> [meta, bed, bim, fam, shared_markers, [], [], remove, afreq] }
    def ch_shared_king_inputs = ch_shared_by_id.map { _id, meta, bed, bim, fam, _extract, _exclude, remove, shared_markers, _pgen, _pvar, _psam, _keep -> [meta, bed, bim, fam, shared_markers, [], [], remove] }

    // BOTH MODES

    //
    // MODULE: Sex check with chromosome X; the PAR split and thresholds reach plink2 through ext.args
    //
    PLINK2_CHECKSEX(ch_study_checksex_inputs.mix(ch_shared_checksex_inputs))

    //
    // MODULE: Sex mismatch table, removal list and F histogram
    //
    SEX_CHECK_DECISIONS(PLINK2_CHECKSEX.out.sexcheck)

    //
    // MODULE: Heterozygosity report of the study over the autosomal marker set of its mode
    //
    PLINK2_HET(ch_study_het_inputs.mix(ch_shared_het_inputs))

    //
    // MODULE: Heterozygosity histogram, with the reference distribution beneath it in shared mode, and the
    // heterozygosity-against-sex scatter, report only
    //
    // The reference report exists for the shared strata alone, so the study strata contribute an empty slot
    // and the join stays strict; a join with a remainder pads nothing when no stratum is in shared mode.
    def ch_reference_het_by_id = PLINK2_HET_REFERENCE.out.het
        .map { meta, reference_het -> [meta.id, reference_het] }
        .mix(ch_by_mode.study.map { meta, _bed, _bim, _fam, _extract, _exclude, _remove, _smiss -> [meta.id, []] })
    def ch_het_plot_inputs = PLINK2_HET.out.het
        .map { meta, het -> [meta.id, meta, het] }
        .join(PLINK2_CHECKSEX.out.sexcheck.map { meta, sexcheck -> [meta.id, sexcheck] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_reference_het_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, het, sexcheck, reference_het -> [meta, het, sexcheck, reference_het] }

    HETEROZYGOSITY_PLOTS(ch_het_plot_inputs)

    //
    // MODULE: KING kinship table on the same autosomal set, and the matrix of every pair in the same pass; the
    // kinship filter and the matrix request reach plink2 through ext.args
    //
    PLINK2_MAKEKINGTABLE(ch_study_autosomal_inputs.mix(ch_shared_king_inputs))

    //
    // MODULE: Pair classification, duplicate removal list, mean-kinship outliers over the matrix, and the pair
    // and per-individual kinship histograms
    //
    def ch_relatedness_inputs = PLINK2_MAKEKINGTABLE.out.kin0
        .map { meta, kin0 -> [meta.id, meta, kin0] }
        .join(PLINK2_MAKEKINGTABLE.out.king.map { meta, king, king_id -> [meta.id, king, king_id] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_genotypes.map { meta, _bed, _bim, _fam, _extract, _exclude, _remove, smiss -> [meta.id, smiss] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, kin0, king, king_id, smiss -> [meta, kin0, king, king_id, smiss] }

    RELATEDNESS_DECISIONS(
        ch_relatedness_inputs,
        relatedness_indiv_sd,
        relatedness_po_ibs0_max,
    )

    emit:
    prune_in              = PLINK2_INDEPPAIRWISE.out.prune_in // channel: [ val(meta), path(prune_in) ], the strata in study mode
    prune_out             = PLINK2_INDEPPAIRWISE.out.prune_out // channel: [ val(meta), path(prune_out) ], the strata in study mode
    highld_exclude        = HIGHLD_EXCLUDE.out.variant_exclude // channel: [ val(meta), path(highld_exclude) ], the strata in study mode
    reference_afreq       = PLINK2_FREQ.out.afreq // channel: [ val(meta), path(afreq) ], the strata in shared mode
    reference_het         = PLINK2_HET_REFERENCE.out.het // channel: [ val(meta), path(reference_het) ], the strata in shared mode
    sexcheck              = PLINK2_CHECKSEX.out.sexcheck // channel: [ val(meta), path(sexcheck) ]
    sex_mismatch          = SEX_CHECK_DECISIONS.out.mismatch // channel: [ val(meta), path(sex_mismatch) ]
    sex_remove            = SEX_CHECK_DECISIONS.out.sample_remove // channel: [ val(meta), path(sex_remove) ]
    sex_check_hist_plot   = SEX_CHECK_DECISIONS.out.hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    het                   = PLINK2_HET.out.het // channel: [ val(meta), path(het) ]
    het_hist              = HETEROZYGOSITY_PLOTS.out.hist_data // channel: [ val(meta), path(hist_data) ]
    het_sex_scatter       = HETEROZYGOSITY_PLOTS.out.scatter_data // channel: [ val(meta), path(scatter_data) ]
    het_hist_plot         = HETEROZYGOSITY_PLOTS.out.hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    het_sex_scatter_plot  = HETEROZYGOSITY_PLOTS.out.scatter_plot // channel: [ val(meta), path(pdf), path(png) ]
    kin0                  = PLINK2_MAKEKINGTABLE.out.kin0 // channel: [ val(meta), path(kin0) ]
    relatedness_pairs     = RELATEDNESS_DECISIONS.out.pairs // channel: [ val(meta), path(pairs) ]
    relatedness_indiv     = RELATEDNESS_DECISIONS.out.indiv // channel: [ val(meta), path(indiv) ]
    relatedness_remove    = RELATEDNESS_DECISIONS.out.sample_remove // channel: [ val(meta), path(relatedness_remove) ]
    relatedness_outliers  = RELATEDNESS_DECISIONS.out.outliers // channel: [ val(meta), path(outliers) ]
    relatedness_hist_plot = RELATEDNESS_DECISIONS.out.hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    relatedness_indiv_hist_plot = RELATEDNESS_DECISIONS.out.indiv_hist_plot // channel: [ val(meta), path(pdf), path(png) ]
}
