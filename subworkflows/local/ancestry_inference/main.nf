// Infer the ancestry of every sample of one PLINK fileset per stratum against a labelled reference panel: the
// stratum's QC'd variants are matched to the reference by position and alleles on the variant tables alone,
// each reference fileset is restricted to the matched variants by its own IDs, the intersects are merged,
// renamed to the stratum's IDs and flipped onto its strand, the merged reference is filtered, pruned and
// decomposed, reference and study samples are projected onto its components with one weight file, and a
// classifier trained on the reference labels assigns every study sample a super-population. For the strata
// whose sample checks take the shared marker set, the route also selects the reference samples of the
// stratum's super-population and, when the shared markers are to be chosen on them, prunes those samples.
// Pipeline-owned: the R modules carry the harmonisation and assignment policy, so this is not an upstream
// candidate.

// MODULE: Local to the pipeline
include { ANCESTRY_HARMONISE                                     } from '../../../modules/local/ancestry_harmonise/main'
include { PLINK2_MAKEBED as PLINK2_MAKEBED_REFERENCE             } from '../../../modules/local/plink2/makebed/main'
include { PLINK2_PMERGELIST                                      } from '../../../modules/local/plink2/pmergelist/main'
include { HIGHLD_EXCLUDE as HIGHLD_EXCLUDE_REFERENCE             } from '../../../modules/local/highld_exclude/main'
include { PLINK2_INDEPPAIRWISE as PLINK2_INDEPPAIRWISE_REFERENCE } from '../../../modules/local/plink2/indeppairwise/main'
include { ANCESTRY_REFERENCE_KEEP                                } from '../../../modules/local/ancestry_reference_keep/main'
include { PLINK2_INDEPPAIRWISE as PLINK2_INDEPPAIRWISE_MATCHED   } from '../../../modules/local/plink2/indeppairwise/main'
include { PLINK2_PCAWTS                                          } from '../../../modules/local/plink2/pcawts/main'
include { PLINK2_SCORE as PLINK2_SCORE_REFERENCE                 } from '../../../modules/local/plink2/score/main'
include { PLINK2_SCORE as PLINK2_SCORE_STUDY                     } from '../../../modules/local/plink2/score/main'
include { ANCESTRY_ASSIGN                                        } from '../../../modules/local/ancestry_assign/main'

workflow ANCESTRY_INFERENCE {
    take:
    ch_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam), path(extract), [ path(exclude), ... ], path(remove) ]; a stratum whose meta.sample_qc_marker_set is `shared` also gets the shared-marker products
    ch_reference // channel: [ val(meta), path(bed), path(bim), path(fam) ], one item per reference fileset
    reference_pop_data // value: path to the TSV of FID, IID, pop and super_pop per reference sample
    high_ld_regions // value: path to the BED of long-range LD regions
    genome_build // value: the study's genome build, which the reference must share, named by the build guard
    ld_window_size // value: --indep-pairwise window on the merged reference, in variants
    ld_step_size // value: --indep-pairwise step, in variants
    ld_r2 // value: --indep-pairwise r-squared threshold
    n_pcs // value: number of principal components computed and projected
    prob_threshold // value: posterior probability at or above which a study sample is assigned
    sd_filter // value: standard deviations of the centroid rule, 0 when the rule is off
    shared_reference // value: `pooled` or `matched`, the reference samples the shared marker set is filtered and pruned on; a matched group below 50 samples falls back to `pooled`

    main:

    // plink2 refuses LD pruning and frequency estimates below this many samples
    def min_matched_reference_samples = 50

    // The study fileset is never materialised: its QC'd variant set reaches the reference as the filter
    // chain's lists, and its samples are projected from the original fileset with the pruned list. The
    // reference is materialised twice, and only the reference: once per fileset restricted to the matched
    // variants, because plink2 applies `--extract` only after `--pmerge-list` has concatenated its inputs in
    // full (verified on 2.0.0a.6.9), and once merged, renamed and flipped, because pruning, the decomposition
    // and the reference projection all read that one fileset.

    //
    // MODULE: Harmonisation of the stratum's QC'd variants with the reference variant tables, by position and
    // alleles; stops when the ID-shared variants disagree on position, the signature of a build mismatch
    //
    // [ [ bim, ... ] ], every reference variant table in name order, wrapped so that `combine` keeps it one slot
    def ch_reference_bims = ch_reference.map { _meta, _bed, bim, _fam -> bim }.toSortedList { bim_a, bim_b -> bim_a.name <=> bim_b.name }.map { bims -> [bims] }
    ANCESTRY_HARMONISE(
        ch_genotypes.combine(ch_reference_bims).map { meta, _bed, bim, _fam, extract, exclude, _remove, reference_bims -> [meta, bim, extract, exclude, reference_bims] },
        genome_build,
    )

    def ch_genotypes_by_id = ch_genotypes.map { meta, bed, bim, fam, extract, exclude, remove -> [meta.id, meta, bed, bim, fam, extract, exclude, remove] }
    def ch_harmonised_by_id = ANCESTRY_HARMONISE.out.snplist.map { meta, snplist -> [meta.id, snplist] }

    //
    // MODULE: Every reference fileset restricted to the matched variants by their reference IDs, one run per
    // stratum and fileset
    //
    // The intersect is driven by reference-side IDs because plink2 renames before it extracts (verified on
    // 2.0.0a.6.9): a rename here would leave the extract to study IDs, which an unmatched reference variant
    // may also carry. No variant filter runs here, so that the shared markers can be filtered on a subset of
    // the reference samples. The scatter key joins the stratum and the fileset; the stratum metadata is
    // restored at the gather.
    def ch_reference_filesets = ch_reference.toList().map { rows -> [rows] }
    def ch_intersect_inputs = ANCESTRY_HARMONISE.out.reference_extract
        .combine(ch_reference_filesets)
        .flatMap { meta, reference_extract, rows ->
            rows.collect { row ->
                def (reference_meta, reference_bed, reference_bim, reference_fam) = row
                def meta_intersect = meta + [id: "${meta.id}.${reference_meta.id}", stratum: meta.id, reference: reference_meta.id, n_reference: rows.size()]
                [meta_intersect, reference_bed, reference_bim, reference_fam, reference_extract, [], [], []]
            }
        }

    PLINK2_MAKEBED_REFERENCE(ch_intersect_inputs)

    // [ id, [ bed, ... ], [ bim, ... ], [ fam, ... ] ], the filesets in reference id order
    def ch_intersects_by_id = PLINK2_MAKEBED_REFERENCE.out.bed
        .map { meta, bed, bim, fam -> [groupKey(meta.stratum, meta.n_reference), [meta.reference, bed, bim, fam]] }
        .groupTuple(by: 0)
        .map { key, filesets ->
            def ordered = filesets.toSorted { fileset -> fileset[0] }
            [key.getGroupTarget(), ordered.collect { fileset -> fileset[1] }, ordered.collect { fileset -> fileset[2] }, ordered.collect { fileset -> fileset[3] }]
        }

    //
    // MODULE: One merged reference fileset, renamed to the stratum's IDs and then flipped onto its strand;
    // plink2 renames before it updates alleles, so the update list names the variants by the study IDs
    //
    def ch_merge_inputs = ch_intersects_by_id
        .join(ch_genotypes_by_id.map { id, meta, _bed, _bim, _fam, _extract, _exclude, _remove -> [id, meta] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ANCESTRY_HARMONISE.out.name_update.map { meta, name_update -> [meta.id, name_update] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ANCESTRY_HARMONISE.out.flip_update.map { meta, flip_update -> [meta.id, flip_update] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, beds, bims, fams, meta, name_update, flip_update -> [meta, beds, bims, fams, [], [], [], [], name_update, flip_update] }

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

    // SHARED MARKER SET
    //
    // A stratum whose sample checks take the shared marker set needs the reference samples of its own
    // super-population: they are its heterozygosity baseline whichever samples choose the markers. Under
    // `pooled` the shared markers are the pruned list of the decomposition, filtered and pruned on every
    // reference sample; under `matched` the same filters, the same long-range LD exclusion and the same
    // pruning run on the matched samples alone, a stats-only run over the merged reference, because plink2
    // computes `--maf` and `--geno` over the `--keep` subset and applies them before `--indep-pairwise`
    // (verified on 2.0.0a.6.9). The decomposition keeps the pooled panel either way.
    def ch_shared_merged_by_id = ch_merged_by_id.filter { _id, meta, _pgen, _pvar, _psam -> meta.sample_qc_marker_set == 'shared' }

    //
    // MODULE: The reference samples of the stratum's super-population, as a keep list
    //
    ANCESTRY_REFERENCE_KEEP(
        ch_shared_merged_by_id.map { _id, meta, _pgen, _pvar, _psam -> meta },
        reference_pop_data,
    )

    def ch_reference_keep_by_id = ANCESTRY_REFERENCE_KEEP.out.sample_keep.map { meta, keep -> [meta.id, keep] }

    // The reference the shared markers are chosen on, per stratum: the requested one, except that a matched
    // group below plink2's 50-sample floor for LD pruning and frequency estimates falls back to the pooled
    // panel. The keep list is the one place its size is known; the route carries it with the choice, so that
    // the summary records the reference actually used and why.
    def ch_shared_route_by_id = ch_reference_keep_by_id.map { id, keep ->
        def n_reference_matched = keep.countLines()
        [id, n_reference_matched, shared_reference == 'matched' && n_reference_matched >= min_matched_reference_samples ? 'matched' : 'pooled']
    }

    //
    // MODULE: Filtering and LD pruning of the matched reference samples outside the regions and off the sex
    // chromosomes, for the strata whose route is `matched`
    //
    PLINK2_INDEPPAIRWISE_MATCHED(
        ch_shared_merged_by_id
            .join(HIGHLD_EXCLUDE_REFERENCE.out.variant_exclude.filter { meta, _highld_exclude -> meta.sample_qc_marker_set == 'shared' }.map { meta, highld_exclude -> [meta.id, highld_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .join(ch_reference_keep_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .join(ch_shared_route_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .filter { _id, _meta, _pgen, _pvar, _psam, _highld_exclude, _keep, _n_reference_matched, route -> route == 'matched' }
            .map { _id, meta, pgen, pvar, psam, highld_exclude, keep, _n_reference_matched, _route -> [meta, pgen, pvar, psam, [], highld_exclude, keep, []] },
        ld_window_size,
        ld_step_size,
        ld_r2,
    )

    // The stratum's map gains the reference used and the size of its matched group. Each list is joined to
    // the strata whose route chose it; the pooled list exists for every stratum, so its join is the one place
    // where unmatched keys are the strata of the other route and are dropped by design.
    def ch_matched_markers = PLINK2_INDEPPAIRWISE_MATCHED.out.prune_in
        .map { meta, prune_in -> [meta.id, meta, prune_in] }
        .join(ch_shared_route_by_id.filter { _id, _n_reference_matched, route -> route == 'matched' }, by: 0, failOnDuplicate: true, failOnMismatch: true)
    def ch_pooled_markers = PLINK2_INDEPPAIRWISE_REFERENCE.out.prune_in
        .map { meta, prune_in -> [meta.id, meta, prune_in] }
        .join(ch_shared_route_by_id.filter { _id, _n_reference_matched, route -> route == 'pooled' }, by: 0, failOnDuplicate: true)
    def ch_shared_markers = ch_matched_markers
        .mix(ch_pooled_markers)
        .map { _id, meta, prune_in, n_reference_matched, route -> [meta + [shared_reference: route, n_reference_matched: n_reference_matched], prune_in] }

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
    reference_extract     = ANCESTRY_HARMONISE.out.reference_extract // channel: [ val(meta), path(reference_extract) ]
    name_update           = ANCESTRY_HARMONISE.out.name_update // channel: [ val(meta), path(name_update) ]
    flip_update           = ANCESTRY_HARMONISE.out.flip_update // channel: [ val(meta), path(flip_update) ]
    reference_genotypes   = PLINK2_PMERGELIST.out.pgen // channel: [ val(meta), path(pgen), path(pvar), path(psam) ]
    highld_exclude        = HIGHLD_EXCLUDE_REFERENCE.out.variant_exclude // channel: [ val(meta), path(highld_exclude) ]
    prune_in              = PLINK2_INDEPPAIRWISE_REFERENCE.out.prune_in // channel: [ val(meta), path(prune_in) ]
    reference_keep        = ANCESTRY_REFERENCE_KEEP.out.sample_keep // channel: [ val(meta), path(reference_keep) ], the strata in shared mode
    shared_markers        = ch_shared_markers // channel: [ val(meta), path(shared_markers) ], the strata in shared mode: the pooled or the matched prune.in; meta carries shared_reference, the reference used, and n_reference_matched
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
    pc1_pc2_plot          = ANCESTRY_ASSIGN.out.pc1_pc2_plot // channel: [ val(meta), path(pdf), path(png) ]
    pc3_pc4_plot          = ANCESTRY_ASSIGN.out.pc3_pc4_plot // channel: [ val(meta), path(pdf), path(png) ]
}
