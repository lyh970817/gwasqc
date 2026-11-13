// Derive the variant and sample filter lists of the contig, MAF, missingness and Hardy-Weinberg chain for one
// PLINK fileset per stratum from stats-only plink2 runs, without materialising an intermediate fileset.
// Pipeline-owned: the R decision modules carry the pipeline's thresholds, so this is not an upstream candidate.

// MODULE: Local to the pipeline
include { CONTIG_EXCLUDE                            } from '../../../modules/local/contig_exclude/main'
include { PLINK2_WRITESNPLIST                       } from '../../../modules/local/plink2/writesnplist/main'
include { PLINK2_MISSING as PLINK2_MISSING_VARIANTS } from '../../../modules/local/plink2/missing/main'
include { GENO_DECISIONS                            } from '../../../modules/local/geno_decisions/main'
include { PLINK2_MISSING as PLINK2_MISSING_SAMPLES  } from '../../../modules/local/plink2/missing/main'
include { MIND_DECISIONS                            } from '../../../modules/local/mind_decisions/main'
include { MISSINGNESS_LADDER                        } from '../../../modules/local/missingness_ladder/main'
include { MISSINGNESS_PLOTS                         } from '../../../modules/local/missingness_plots/main'
include { PLINK2_HARDY                              } from '../../../modules/local/plink2/hardy/main'
include { HWE_DECISIONS                             } from '../../../modules/local/hwe_decisions/main'
include { HWE_PLOTS                                 } from '../../../modules/local/hwe_plots/main'

// SUBWORKFLOW: Local to the pipeline, one alias per rung of the call-rate ladder, because each rung starts from
// the previous rung's lists and a process or subworkflow runs once per alias
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_90 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_91 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_92 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_93 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_94 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_95 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_96 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_97 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_98 } from '../missingness_rung/main'
include { MISSINGNESS_RUNG as MISSINGNESS_RUNG_99 } from '../missingness_rung/main'

workflow PLINK_QC_FILTER_LISTS {
    take:
    ch_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ]
    geno // value: maximum per-variant missing-call rate; under `iterative`, the last rung applied, 1 - its call rate
    mind // value: maximum per-sample missing-call rate; under `iterative`, equal to geno
    hwe // value: Hardy-Weinberg exact-test p-value floor
    missingness_mode // value: `iterative`, the cumulative call-rate ladder applied up to the call rate 1 - geno, or `single`, geno and then mind applied once
    exclude_nonstandard_contigs // boolean: list and exclude the variants on contigs outside 1-22, X, Y, XY and MT at the MAF step; false keeps them

    main:

    // Every plink2 run below starts from the unfiltered stratum fileset and receives the lists accumulated so
    // far; plink2 applies `--extract`, `--exclude` and `--remove` before it computes a report, so each report
    // describes the filtered set without a filtered fileset ever being written. `--geno` is the one filter
    // plink2 applies only after `--missing` has been written, so a variant missingness threshold never reaches
    // plink2 natively here: it becomes an exclusion list first, and the sample report is measured with that
    // list excluded, as the legacy chain measured it.

    //
    // MODULE: Exclusion list of the variants on alt, random and other contigs outside 1-22, X, Y, XY and MT,
    // derived only under --exclude_nonstandard_contigs; by default the slot is an empty list and no variant is
    // excluded for its contig, as in the legacy pipeline
    //
    if (exclude_nonstandard_contigs) {
        CONTIG_EXCLUDE(
            ch_genotypes.map { meta, _bed, bim, _fam -> [meta, bim] }
        )
    }
    def ch_contig_exclude = exclude_nonstandard_contigs
        ? CONTIG_EXCLUDE.out.variant_exclude
        : ch_genotypes.map { meta, _bed, _bim, _fam -> [meta, []] }

    def ch_contig_genotypes_by_id = ch_genotypes
        .map { meta, bed, bim, fam -> [meta.id, meta, bed, bim, fam] }
        .join(ch_contig_exclude.map { meta, contig_exclude -> [meta.id, contig_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: MAF keep-list; the threshold is native optional behaviour and reaches plink2 through ext.args
    //
    // Under --exclude_nonstandard_contigs the contig exclusion is applied here, at the first filter, and only
    // here: every later run extracts this keep-list, so no variant on a non-standard contig reaches a
    // statistic, a decision list, the ancestry route or the QC'd fileset. By default the exclusion slot is
    // empty and the keep-list carries every variant that passes the MAF.
    PLINK2_WRITESNPLIST(
        ch_contig_genotypes_by_id.map { _id, meta, bed, bim, fam, contig_exclude -> [meta, bed, bim, fam, [], contig_exclude, [], []] }
    )

    def ch_maf_genotypes_by_id = ch_genotypes
        .map { meta, bed, bim, fam -> [meta.id, meta, bed, bim, fam] }
        .join(PLINK2_WRITESNPLIST.out.snplist.map { meta, snplist -> [meta.id, snplist] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: Variant missingness over the MAF-passing variants, all samples
    //
    PLINK2_MISSING_VARIANTS(
        ch_maf_genotypes_by_id.map { _id, meta, bed, bim, fam, snplist -> [meta, bed, bim, fam, snplist, [], [], []] }
    )

    //
    // SUBWORKFLOW: The call-rate ladder, 90 % to 99 %, cumulative as the legacy Iterative_Missingness.sh ran
    // it: each rung applies its variant threshold and then its sample threshold, both 1 - call rate, to what
    // the previous rung kept, and its lists are the cumulative exclusions and removals so far
    //
    def ch_ladder_start = ch_maf_genotypes_by_id.map { _id, meta, bed, bim, fam, snplist -> [meta, bed, bim, fam, snplist, [], []] }
    MISSINGNESS_RUNG_90(ch_ladder_start, 90)
    MISSINGNESS_RUNG_91(MISSINGNESS_RUNG_90.out.lists, 91)
    MISSINGNESS_RUNG_92(MISSINGNESS_RUNG_91.out.lists, 92)
    MISSINGNESS_RUNG_93(MISSINGNESS_RUNG_92.out.lists, 93)
    MISSINGNESS_RUNG_94(MISSINGNESS_RUNG_93.out.lists, 94)
    MISSINGNESS_RUNG_95(MISSINGNESS_RUNG_94.out.lists, 95)
    MISSINGNESS_RUNG_96(MISSINGNESS_RUNG_95.out.lists, 96)
    MISSINGNESS_RUNG_97(MISSINGNESS_RUNG_96.out.lists, 97)
    MISSINGNESS_RUNG_98(MISSINGNESS_RUNG_97.out.lists, 98)
    MISSINGNESS_RUNG_99(MISSINGNESS_RUNG_98.out.lists, 99)

    def ladder_call_rates = (90..99).toList()
    def ch_rung_lists = MISSINGNESS_RUNG_90.out.lists
        .mix(MISSINGNESS_RUNG_91.out.lists, MISSINGNESS_RUNG_92.out.lists, MISSINGNESS_RUNG_93.out.lists, MISSINGNESS_RUNG_94.out.lists)
        .mix(MISSINGNESS_RUNG_95.out.lists, MISSINGNESS_RUNG_96.out.lists, MISSINGNESS_RUNG_97.out.lists, MISSINGNESS_RUNG_98.out.lists)
        .mix(MISSINGNESS_RUNG_99.out.lists)
    def ch_rung_smiss = MISSINGNESS_RUNG_90.out.smiss
        .mix(MISSINGNESS_RUNG_91.out.smiss, MISSINGNESS_RUNG_92.out.smiss, MISSINGNESS_RUNG_93.out.smiss, MISSINGNESS_RUNG_94.out.smiss)
        .mix(MISSINGNESS_RUNG_95.out.smiss, MISSINGNESS_RUNG_96.out.smiss, MISSINGNESS_RUNG_97.out.smiss, MISSINGNESS_RUNG_98.out.smiss)
        .mix(MISSINGNESS_RUNG_99.out.smiss)

    //
    // MODULE: The ladder table, one geno and one mind row per rung, counted from the rungs' cumulative lists
    //
    // The rung joins the metadata only while the rungs need a distinct identity; the gathered table carries the
    // stratum metadata again.
    def ch_ladder_inputs = ch_rung_lists
        .map { meta, _bed, _bim, _fam, _maf_snplist, geno_exclude, mind_remove -> [groupKey(meta.id, ladder_call_rates.size()), [meta.call_rate, geno_exclude, mind_remove]] }
        .groupTuple(by: 0)
        .map { key, rungs ->
            // [ id, [ call_rate, ... ], [ geno_exclude, ... ], [ mind_remove, ... ] ], all in call-rate order
            def ordered = rungs.toSorted { rung -> rung[0] }
            [key.getGroupTarget(), ordered.collect { rung -> rung[0] }, ordered.collect { rung -> rung[1] }, ordered.collect { rung -> rung[2] }]
        }
        .join(ch_maf_genotypes_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, call_rates, geno_excludes, mind_removes, meta, _bed, _bim, fam, snplist -> [meta, snplist, fam, call_rates, geno_excludes, mind_removes] }

    MISSINGNESS_LADDER(ch_ladder_inputs)

    //
    // The applied missingness lists and the sample report they were decided from
    //
    def ch_geno_exclude = channel.empty()
    def ch_mind_remove = channel.empty()
    def ch_smiss = channel.empty()
    if (missingness_mode == 'single') {
        //
        // MODULE: geno exclusion list from the variant report
        //
        GENO_DECISIONS(
            PLINK2_MISSING_VARIANTS.out.vmiss.map { meta, vmiss -> [meta, vmiss, geno, []] }
        )

        //
        // MODULE: Sample missingness over the geno-retained variants
        //
        def ch_missing_samples_inputs = ch_maf_genotypes_by_id
            .join(GENO_DECISIONS.out.variant_exclude.map { meta, geno_exclude -> [meta.id, geno_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .map { _id, meta, bed, bim, fam, snplist, geno_exclude -> [meta, bed, bim, fam, snplist, geno_exclude, [], []] }

        PLINK2_MISSING_SAMPLES(ch_missing_samples_inputs)

        //
        // MODULE: mind removal list from the sample report
        //
        MIND_DECISIONS(
            PLINK2_MISSING_SAMPLES.out.smiss.map { meta, smiss -> [meta, smiss, mind, []] }
        )

        ch_geno_exclude = GENO_DECISIONS.out.variant_exclude
        ch_mind_remove = MIND_DECISIONS.out.sample_remove
        ch_smiss = PLINK2_MISSING_SAMPLES.out.smiss
    }
    else {
        // The rung whose call rate is 1 - geno; ingress has checked that geno equals mind and names a rung.
        // The stratum's own metadata is restored, so the rung never leaks past the ladder.
        def applied_call_rate = Math.round(100 * (1 - (geno as double))) as int
        def ch_stratum_meta_by_id = ch_genotypes.map { meta, _bed, _bim, _fam -> [meta.id, meta] }
        def ch_applied_by_id = ch_rung_lists
            .filter { meta, _bed, _bim, _fam, _maf_snplist, _geno_exclude, _mind_remove -> meta.call_rate == applied_call_rate }
            .map { meta, _bed, _bim, _fam, _maf_snplist, geno_exclude, mind_remove -> [meta.id, geno_exclude, mind_remove] }
            .join(ch_stratum_meta_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        ch_geno_exclude = ch_applied_by_id.map { _id, geno_exclude, _mind_remove, meta -> [meta, geno_exclude] }
        ch_mind_remove = ch_applied_by_id.map { _id, _geno_exclude, mind_remove, meta -> [meta, mind_remove] }
        ch_smiss = ch_rung_smiss
            .filter { meta, _smiss -> meta.call_rate == applied_call_rate }
            .map { meta, smiss -> [meta.id, smiss] }
            .join(ch_stratum_meta_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .map { _id, smiss, meta -> [meta, smiss] }
    }

    def ch_geno_exclude_by_id = ch_geno_exclude.map { meta, geno_exclude -> [meta.id, geno_exclude] }

    //
    // MODULE: Missingness histograms with the thresholds marked, and the ladder as a table image
    //
    def ch_missingness_plot_inputs = PLINK2_MISSING_VARIANTS.out.vmiss
        .map { meta, vmiss -> [meta.id, meta, vmiss] }
        .join(ch_smiss.map { meta, smiss -> [meta.id, smiss] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(MISSINGNESS_LADDER.out.ladder.map { meta, ladder -> [meta.id, ladder] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, vmiss, smiss, ladder -> [meta, vmiss, smiss, ladder] }

    MISSINGNESS_PLOTS(
        ch_missingness_plot_inputs,
        geno,
        mind,
    )

    //
    // MODULE: Hardy-Weinberg reports on the missingness-filtered set, as the legacy chain measured them
    //
    def ch_hardy_inputs = ch_maf_genotypes_by_id
        .join(ch_geno_exclude_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_mind_remove.map { meta, mind_remove -> [meta.id, mind_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
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

    //
    // MODULE: Hardy-Weinberg p-value histograms, over every variant and within the legacy window, with the
    // threshold marked
    //
    HWE_PLOTS(ch_hwe_inputs, hwe)

    emit:
    contig_exclude     = ch_contig_exclude // channel: [ val(meta), path(contig_exclude) ], an empty list unless exclude_nonstandard_contigs
    maf_snplist        = PLINK2_WRITESNPLIST.out.snplist // channel: [ val(meta), path(snplist) ], over the standard chromosomes under exclude_nonstandard_contigs, else over every variant
    vmiss              = PLINK2_MISSING_VARIANTS.out.vmiss // channel: [ val(meta), path(vmiss) ], over the MAF-passing variants
    smiss              = ch_smiss // channel: [ val(meta), path(smiss) ], the report the applied mind list was decided from, over the geno-retained variants
    smiss_maf          = PLINK2_MISSING_VARIANTS.out.smiss // channel: [ val(meta), path(smiss) ], over the MAF-passing variants and every sample, before any geno filter, under both missingness modes
    geno_exclude       = ch_geno_exclude // channel: [ val(meta), path(geno_exclude) ], the applied variant missingness exclusions
    mind_remove        = ch_mind_remove // channel: [ val(meta), path(mind_remove) ], the applied sample missingness removals
    missingness_ladder = MISSINGNESS_LADDER.out.ladder // channel: [ val(meta), path(ladder) ]
    hardy              = PLINK2_HARDY.out.hardy // channel: [ val(meta), path(hardy) ]
    hardy_x            = PLINK2_HARDY.out.hardy_x // channel: [ val(meta), path(hardy_x) ], optional
    hwe_exclude        = HWE_DECISIONS.out.variant_exclude // channel: [ val(meta), path(hwe_exclude) ]
    vmiss_hist_data    = MISSINGNESS_PLOTS.out.variant_hist_data // channel: [ val(meta), path(vmiss_hist) ]
    vmiss_hist_plot    = MISSINGNESS_PLOTS.out.variant_hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    vmiss_hist_ylim_plot = MISSINGNESS_PLOTS.out.variant_hist_ylim_plot // channel: [ val(meta), path(pdf) ]
    smiss_hist_data    = MISSINGNESS_PLOTS.out.sample_hist_data // channel: [ val(meta), path(smiss_hist) ]
    smiss_hist_plot    = MISSINGNESS_PLOTS.out.sample_hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    ladder_plot        = MISSINGNESS_PLOTS.out.ladder_plot // channel: [ val(meta), path(pdf), path(png) ]
    hwe_hist_data      = HWE_PLOTS.out.hist_data // channel: [ val(meta), path(hwe_hist) ]
    hwe_hist_plot      = HWE_PLOTS.out.hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    hwe_window_data    = HWE_PLOTS.out.window_data // channel: [ val(meta), path(hwe_hist_window) ]
    hwe_window_plot    = HWE_PLOTS.out.window_plot // channel: [ val(meta), path(pdf), path(png) ]
}
