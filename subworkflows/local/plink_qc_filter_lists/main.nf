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
include { GENO_DECISIONS as GENO_DECISIONS_LADDER   } from '../../../modules/local/geno_decisions/main'
include { PLINK2_MISSING as PLINK2_MISSING_LADDER   } from '../../../modules/local/plink2/missing/main'
include { MISSINGNESS_LADDER                        } from '../../../modules/local/missingness_ladder/main'
include { MISSINGNESS_PLOTS                         } from '../../../modules/local/missingness_plots/main'
include { PLINK2_HARDY                              } from '../../../modules/local/plink2/hardy/main'
include { HWE_DECISIONS                             } from '../../../modules/local/hwe_decisions/main'
include { HWE_PLOTS                                 } from '../../../modules/local/hwe_plots/main'

workflow PLINK_QC_FILTER_LISTS {
    take:
    ch_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ]
    geno // value: maximum per-variant missing-call rate
    mind // value: maximum per-sample missing-call rate
    hwe // value: Hardy-Weinberg exact-test p-value floor

    main:

    // Every plink2 run below starts from the unfiltered stratum fileset and receives the lists accumulated so
    // far; plink2 applies `--extract`, `--exclude` and `--remove` before it computes a report, so each report
    // describes the filtered set without a filtered fileset ever being written. `--geno` is the one filter
    // plink2 applies only after `--missing` has been written, so a variant missingness threshold never reaches
    // plink2 natively here: it becomes an exclusion list first, and the sample report is measured with that
    // list excluded, as the legacy chain measured it.

    //
    // MODULE: Exclusion list of the variants on alt, random and other contigs outside 1-22, X, Y, XY and MT
    //
    CONTIG_EXCLUDE(
        ch_genotypes.map { meta, _bed, bim, _fam -> [meta, bim] }
    )

    def ch_contig_genotypes_by_id = ch_genotypes
        .map { meta, bed, bim, fam -> [meta.id, meta, bed, bim, fam] }
        .join(CONTIG_EXCLUDE.out.variant_exclude.map { meta, contig_exclude -> [meta.id, contig_exclude] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    //
    // MODULE: MAF keep-list over the standard chromosomes; the threshold is native optional behaviour and
    // reaches plink2 through ext.args
    //
    // The contig exclusion is applied here, at the first filter, and only here: every later run extracts this
    // keep-list, so no variant on a non-standard contig reaches a statistic, a decision list, the ancestry
    // route or the QC'd fileset.
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
    // MODULE: geno exclusion list from the variant report
    //
    GENO_DECISIONS(
        PLINK2_MISSING_VARIANTS.out.vmiss.map { meta, vmiss -> [meta, vmiss, geno] }
    )

    def ch_geno_exclude_by_id = GENO_DECISIONS.out.variant_exclude.map { meta, geno_exclude -> [meta.id, geno_exclude] }

    //
    // MODULE: Sample missingness over the geno-retained variants
    //
    def ch_missing_samples_inputs = ch_maf_genotypes_by_id
        .join(ch_geno_exclude_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam, snplist, geno_exclude -> [meta, bed, bim, fam, snplist, geno_exclude, [], []] }

    PLINK2_MISSING_SAMPLES(ch_missing_samples_inputs)

    //
    // MODULE: mind removal list from the sample report
    //
    MIND_DECISIONS(
        PLINK2_MISSING_SAMPLES.out.smiss.map { meta, smiss -> [meta, smiss, mind] }
    )

    //
    // MODULE: Call-rate ladder, 90 % to 99 %: per rung, the geno exclusion list at that rate from the base
    // variant report, then the sample report with that list excluded, gathered into one table
    //
    // The rung joins the metadata only while the per-rung runs need a distinct identity; the gathered table
    // carries the stratum metadata again.
    def ladder_call_rates = (90..99).toList()

    def ch_ladder_geno_inputs = PLINK2_MISSING_VARIANTS.out.vmiss
        .combine(channel.fromList(ladder_call_rates))
        .map { meta, vmiss, call_rate -> [meta + [call_rate: call_rate], vmiss, (100 - call_rate) / 100] }

    GENO_DECISIONS_LADDER(ch_ladder_geno_inputs)

    def ch_ladder_missing_inputs = GENO_DECISIONS_LADDER.out.variant_exclude
        .map { meta, geno_exclude -> [meta.id, meta, geno_exclude] }
        .combine(ch_maf_genotypes_by_id, by: 0)
        .map { _id, meta, geno_exclude, _meta_stratum, bed, bim, fam, snplist -> [meta, bed, bim, fam, snplist, geno_exclude, [], []] }

    PLINK2_MISSING_LADDER(ch_ladder_missing_inputs)

    def ch_ladder_inputs = PLINK2_MISSING_LADDER.out.smiss
        .map { meta, smiss -> [groupKey(meta.id, ladder_call_rates.size()), [meta.call_rate, smiss]] }
        .groupTuple(by: 0)
        .map { key, rungs ->
            // [ id, [ call_rate, ... ], [ smiss, ... ] ], both lists in call-rate order
            def ordered = rungs.toSorted { rung -> rung[0] }
            [key.getGroupTarget(), ordered.collect { rung -> rung[0] }, ordered.collect { rung -> rung[1] }]
        }
        .join(PLINK2_MISSING_VARIANTS.out.vmiss.map { meta, vmiss -> [meta.id, meta, vmiss] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, call_rates, smiss_files, meta, vmiss -> [meta, vmiss, call_rates, smiss_files] }

    MISSINGNESS_LADDER(ch_ladder_inputs)

    //
    // MODULE: Missingness histograms with the thresholds marked, and the ladder as a table image
    //
    def ch_missingness_plot_inputs = PLINK2_MISSING_VARIANTS.out.vmiss
        .map { meta, vmiss -> [meta.id, meta, vmiss] }
        .join(PLINK2_MISSING_SAMPLES.out.smiss.map { meta, smiss -> [meta.id, smiss] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
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
        .join(MIND_DECISIONS.out.sample_remove.map { meta, mind_remove -> [meta.id, mind_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
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
    contig_exclude     = CONTIG_EXCLUDE.out.variant_exclude // channel: [ val(meta), path(contig_exclude) ]
    maf_snplist        = PLINK2_WRITESNPLIST.out.snplist // channel: [ val(meta), path(snplist) ], over the standard chromosomes
    vmiss              = PLINK2_MISSING_VARIANTS.out.vmiss // channel: [ val(meta), path(vmiss) ], over the MAF-passing variants
    smiss              = PLINK2_MISSING_SAMPLES.out.smiss // channel: [ val(meta), path(smiss) ], over the geno-retained variants
    smiss_maf          = PLINK2_MISSING_VARIANTS.out.smiss // channel: [ val(meta), path(smiss) ], over the MAF-passing variants, before the geno filter
    geno_exclude       = GENO_DECISIONS.out.variant_exclude // channel: [ val(meta), path(geno_exclude) ]
    mind_remove        = MIND_DECISIONS.out.sample_remove // channel: [ val(meta), path(mind_remove) ]
    missingness_ladder = MISSINGNESS_LADDER.out.ladder // channel: [ val(meta), path(ladder) ]
    hardy              = PLINK2_HARDY.out.hardy // channel: [ val(meta), path(hardy) ]
    hardy_x            = PLINK2_HARDY.out.hardy_x // channel: [ val(meta), path(hardy_x) ], optional
    hwe_exclude        = HWE_DECISIONS.out.variant_exclude // channel: [ val(meta), path(hwe_exclude) ]
    vmiss_hist_data    = MISSINGNESS_PLOTS.out.variant_hist_data // channel: [ val(meta), path(vmiss_hist) ]
    vmiss_hist_plot    = MISSINGNESS_PLOTS.out.variant_hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    smiss_hist_data    = MISSINGNESS_PLOTS.out.sample_hist_data // channel: [ val(meta), path(smiss_hist) ]
    smiss_hist_plot    = MISSINGNESS_PLOTS.out.sample_hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    ladder_plot        = MISSINGNESS_PLOTS.out.ladder_plot // channel: [ val(meta), path(pdf), path(png) ]
    hwe_hist_data      = HWE_PLOTS.out.hist_data // channel: [ val(meta), path(hwe_hist) ]
    hwe_hist_plot      = HWE_PLOTS.out.hist_plot // channel: [ val(meta), path(pdf), path(png) ]
    hwe_window_data    = HWE_PLOTS.out.window_data // channel: [ val(meta), path(hwe_hist_window) ]
    hwe_window_plot    = HWE_PLOTS.out.window_plot // channel: [ val(meta), path(pdf), path(png) ]
}
