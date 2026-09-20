// Infer the ancestry of every sample of one PLINK fileset per stratum against a labelled reference panel: each
// reference fileset is restricted to the stratum's QC'd variant set, the intersect is harmonised onto the
// stratum's strand and merged into one reference fileset, that fileset is pruned and decomposed, reference
// and study samples are projected onto its components with one weight file, and a classifier trained on the
// reference labels assigns every study sample a super-population.
// Pipeline-owned: the R modules carry the harmonisation and assignment policy, so this is not an upstream
// candidate.

// MODULE: Local to the pipeline
include { PLINK2_MAKEBED as PLINK2_MAKEBED_REFERENCE             } from '../../../modules/local/plink2/makebed/main'
include { ANCESTRY_HARMONISE                                     } from '../../../modules/local/ancestry_harmonise/main'
include { PLINK2_PMERGELIST                                      } from '../../../modules/local/plink2/pmergelist/main'
include { HIGHLD_EXCLUDE as HIGHLD_EXCLUDE_REFERENCE             } from '../../../modules/local/highld_exclude/main'
include { PLINK2_INDEPPAIRWISE as PLINK2_INDEPPAIRWISE_REFERENCE } from '../../../modules/local/plink2/indeppairwise/main'
include { PLINK2_PCAWTS                                          } from '../../../modules/local/plink2/pcawts/main'
include { PLINK2_SCORE as PLINK2_SCORE_REFERENCE                 } from '../../../modules/local/plink2/score/main'
include { PLINK2_SCORE as PLINK2_SCORE_STUDY                     } from '../../../modules/local/plink2/score/main'
include { ANCESTRY_ASSIGN                                        } from '../../../modules/local/ancestry_assign/main'

workflow ANCESTRY_INFERENCE {
    take:
    ch_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam), path(extract), [ path(exclude), ... ], path(remove) ]
    ch_reference // channel: [ val(meta), path(bed), path(bim), path(fam) ], one item per reference fileset
    reference_pop_data // value: path to the TSV of FID, IID, pop and super_pop per reference sample
    high_ld_regions // value: path to the BED of long-range LD regions
    ld_window_size // value: --indep-pairwise window on the merged reference, in variants
    ld_step_size // value: --indep-pairwise step, in variants
    ld_r2 // value: --indep-pairwise r-squared threshold
    n_pcs // value: number of principal components computed and projected
    prob_threshold // value: posterior probability at or above which a study sample is assigned
    sd_filter // value: standard deviations of the centroid rule, 0 when the rule is off

    main:

    // The study fileset is never materialised: its QC'd variant set reaches the reference as the filter
    // chain's lists, and its samples are projected from the original fileset with the pruned list. The
    // reference is materialised twice, and only the reference: once per fileset restricted to the stratum's
    // variants, because plink2 applies `--extract` only after `--pmerge-list` has concatenated its inputs in
    // full (verified on 2.0.0a.6.9), and once merged, harmonised and filtered, because pruning, the
    // decomposition and the reference projection all read that one fileset.

    //
    // MODULE: Every reference fileset restricted to the stratum's QC'd variant set, one run per stratum and
    // fileset; the reference-side MAF and missingness filters reach plink2 through ext.args
    //
    // The scatter key joins the stratum and the fileset; the stratum metadata is restored at the gather.
    def ch_reference_filesets = ch_reference.toList().map { rows -> [rows] }
    def ch_intersect_inputs = ch_genotypes
        .combine(ch_reference_filesets)
        .flatMap { meta, _bed, _bim, _fam, extract, exclude, _remove, rows ->
            rows.collect { row ->
                def (reference_meta, reference_bed, reference_bim, reference_fam) = row
                def meta_intersect = meta + [id: "${meta.id}.${reference_meta.id}", stratum: meta.id, reference: reference_meta.id, n_reference: rows.size()]
                [meta_intersect, reference_bed, reference_bim, reference_fam, extract, exclude, [], []]
            }
        }

    PLINK2_MAKEBED_REFERENCE(ch_intersect_inputs)

    def ch_genotypes_by_id = ch_genotypes.map { meta, bed, bim, fam, extract, exclude, remove -> [meta.id, meta, bed, bim, fam, extract, exclude, remove] }

    // [ id, [ bed, ... ], [ bim, ... ], [ fam, ... ] ], the filesets in reference id order
    def ch_intersects_by_id = PLINK2_MAKEBED_REFERENCE.out.bed
        .map { meta, bed, bim, fam -> [groupKey(meta.stratum, meta.n_reference), [meta.reference, bed, bim, fam]] }
        .groupTuple(by: 0)
        .map { key, filesets ->
            def ordered = filesets.toSorted { fileset -> fileset[0] }
            [key.getGroupTarget(), ordered.collect { fileset -> fileset[1] }, ordered.collect { fileset -> fileset[2] }, ordered.collect { fileset -> fileset[3] }]
        }

    //
    // MODULE: Harmonisation of the intersect against the stratum's variant file
    //
    ANCESTRY_HARMONISE(
        ch_genotypes_by_id.join(ch_intersects_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true).map { _id, meta, _bed, bim, _fam, _extract, _exclude, _remove, _beds, bims, _fams -> [meta, bim, bims] }
    )

    def ch_harmonised_by_id = ANCESTRY_HARMONISE.out.snplist.map { meta, snplist -> [meta.id, snplist] }

    //
    // MODULE: One merged reference fileset, restricted to the harmonised variants and flipped onto the
    // stratum's strand by the update list
    //
    def ch_merge_inputs = ch_intersects_by_id
        .join(ch_genotypes_by_id.map { id, meta, _bed, _bim, _fam, _extract, _exclude, _remove -> [id, meta] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_harmonised_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ANCESTRY_HARMONISE.out.flip_update.map { meta, flip_update -> [meta.id, flip_update] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, beds, bims, fams, meta, snplist, flip_update -> [meta, beds, bims, fams, snplist, [], [], [], flip_update] }

    PLINK2_PMERGELIST(ch_merge_inputs)

    def ch_merged_by_id = PLINK2_PMERGELIST.out.pgen.map { meta, pgen, pvar, psam -> [meta.id, meta, pgen, pvar, psam] }

    //
    // MODULE: Long-range LD and non-autosomal exclusion list over the merged reference, applied before pruning
    // as the legacy ancestry branch ordered the two
    //
    HIGHLD_EXCLUDE_REFERENCE(
        ch_merged_by_id.join(ch_harmonised_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true).map { _id, meta, _pgen, pvar, _psam, snplist -> [meta, pvar, snplist] },
        high_ld_regions,
    )

    //
    // MODULE: LD pruning of the merged reference outside the regions and off the sex chromosomes
    //
    PLINK2_INDEPPAIRWISE_REFERENCE(
        ch_merged_by_id.join(HIGHLD_EXCLUDE_REFERENCE.out.variant_exclude.map { meta, highld_exclude -> [meta.id, highld_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true).map { _id, meta, pgen, pvar, psam, highld_exclude -> [meta, pgen, pvar, psam, [], highld_exclude, [], []] },
        ld_window_size,
        ld_step_size,
        ld_r2,
    )

    def ch_pruned_reference_by_id = ch_merged_by_id.join(PLINK2_INDEPPAIRWISE_REFERENCE.out.prune_in.map { meta, prune_in -> [meta.id, prune_in] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: Principal components of the pruned reference with per-allele weights and the allele counts of
    // the same variants; the weight-file layout reaches plink2 through ext.args2
    //
    PLINK2_PCAWTS(
        ch_pruned_reference_by_id.map { _id, meta, pgen, pvar, psam, prune_in -> [meta, pgen, pvar, psam, prune_in, [], [], []] },
        n_pcs,
    )

    def ch_projection_by_id = PLINK2_PCAWTS.out.allele_weights
        .map { meta, allele_weights -> [meta.id, allele_weights] }
        .join(PLINK2_PCAWTS.out.acount.map { meta, acount -> [meta.id, acount] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: Projection of the reference samples and of the study samples with the same weights, the same
    // reference allele counts and the same modifiers, so that the two sets of coordinates share one scale;
    // the mind removals apply to the study run and no other sample list does
    //
    PLINK2_SCORE_REFERENCE(
        ch_pruned_reference_by_id.join(ch_projection_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true).map { _id, meta, pgen, pvar, psam, prune_in, allele_weights, acount -> [meta, pgen, pvar, psam, prune_in, [], [], [], allele_weights, acount] }
    )

    PLINK2_SCORE_STUDY(
        ch_genotypes_by_id.join(PLINK2_INDEPPAIRWISE_REFERENCE.out.prune_in.map { meta, prune_in -> [meta.id, prune_in] }, by: 0, failOnDuplicate: true, failOnMismatch: true).join(ch_projection_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true).map { _id, meta, bed, bim, fam, _extract, _exclude, remove, prune_in, allele_weights, acount -> [meta, bed, bim, fam, prune_in, [], [], remove, allele_weights, acount] }
    )

    //
    // MODULE: Classifier on the reference coordinates, assignment of the study samples, keep-lists, the
    // mismatch removal list, the summary and the projection plots
    //
    ANCESTRY_ASSIGN(
        PLINK2_SCORE_REFERENCE.out.sscore.map { meta, reference_scores -> [meta.id, meta, reference_scores] }.join(PLINK2_SCORE_STUDY.out.sscore.map { meta, study_scores -> [meta.id, study_scores] }, by: 0, failOnDuplicate: true, failOnMismatch: true).map { _id, meta, reference_scores, study_scores -> [meta, reference_scores, study_scores] },
        reference_pop_data,
        prob_threshold,
        sd_filter,
    )

    emit:
    harmonisation         = ANCESTRY_HARMONISE.out.table // channel: [ val(meta), path(harmonisation) ]
    harmonisation_summary = ANCESTRY_HARMONISE.out.summary // channel: [ val(meta), path(harmonisation_summary) ]
    harmonised_snplist    = ANCESTRY_HARMONISE.out.snplist // channel: [ val(meta), path(snplist) ]
    flip_update           = ANCESTRY_HARMONISE.out.flip_update // channel: [ val(meta), path(flip_update) ]
    reference_genotypes   = PLINK2_PMERGELIST.out.pgen // channel: [ val(meta), path(pgen), path(pvar), path(psam) ]
    highld_exclude        = HIGHLD_EXCLUDE_REFERENCE.out.variant_exclude // channel: [ val(meta), path(highld_exclude) ]
    prune_in              = PLINK2_INDEPPAIRWISE_REFERENCE.out.prune_in // channel: [ val(meta), path(prune_in) ]
    allele_weights        = PLINK2_PCAWTS.out.allele_weights // channel: [ val(meta), path(allele_weights) ]
    eigenval              = PLINK2_PCAWTS.out.eigenval // channel: [ val(meta), path(eigenval) ]
    reference_scores      = PLINK2_SCORE_REFERENCE.out.sscore // channel: [ val(meta), path(sscore) ]
    reference_variants    = PLINK2_SCORE_REFERENCE.out.variants // channel: [ val(meta), path(sscore_vars) ], when list-variants is configured
    study_scores          = PLINK2_SCORE_STUDY.out.sscore // channel: [ val(meta), path(sscore) ]
    study_variants        = PLINK2_SCORE_STUDY.out.variants // channel: [ val(meta), path(sscore_vars) ], when list-variants is configured
    assignment            = ANCESTRY_ASSIGN.out.assignment // channel: [ val(meta), path(assignment) ]
    summary               = ANCESTRY_ASSIGN.out.summary // channel: [ val(meta), path(summary) ]
    model                 = ANCESTRY_ASSIGN.out.model // channel: [ val(meta), path(model) ]
    keep_lists            = ANCESTRY_ASSIGN.out.keep_lists // channel: [ val(meta), [ path(keep), ... ] ]
    mismatch_remove       = ANCESTRY_ASSIGN.out.sample_remove // channel: [ val(meta), path(mismatch_remove) ]
    pca_data              = ANCESTRY_ASSIGN.out.pca_data // channel: [ val(meta), path(pca_data) ]
}
