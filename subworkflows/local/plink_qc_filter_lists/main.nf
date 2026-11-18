// Derive the variant and sample filter lists of the contig, MAF, missingness and Hardy-Weinberg chain for one
// PLINK fileset per stratum from stats-only plink2 runs; the one fileset it writes is the haploid view below,
// which the frequency-based runs read in place of the stratum fileset.
// Pipeline-owned: the R decision modules carry the pipeline's thresholds, so this is not an upstream candidate.

// MODULE: Local to the pipeline
include { CONTIG_EXCLUDE                            } from '../../../modules/local/contig_exclude/main'
include { UNKNOWN_SEX_RECODE                        } from '../../../modules/local/unknown_sex_recode/main'
include { PLINK2_MAKEBED as PLINK2_MAKEBED_HAPLOID_VIEW } from '../../../modules/local/plink2/makebed/main'
include { PLINK2_WRITESNPLIST                       } from '../../../modules/local/plink2/writesnplist/main'
include { PLINK2_MISSING as PLINK2_MISSING_VARIANTS } from '../../../modules/local/plink2/missing/main'
include { GENO_DECISIONS                            } from '../../../modules/local/geno_decisions/main'
include { PLINK2_MISSING as PLINK2_MISSING_SAMPLES  } from '../../../modules/local/plink2/missing/main'
include { MIND_DECISIONS                            } from '../../../modules/local/mind_decisions/main'
include { MISSINGNESS_LADDER                        } from '../../../modules/local/missingness_ladder/main'
include { MISSINGNESS_PLOTS                         } from '../../../modules/local/missingness_plots/main'
include { PLINK2_HARDY                              } from '../../../modules/local/plink2/hardy/main'
include { PLINK2_HARDY as PLINK2_HARDY_NONMALE      } from '../../../modules/local/plink2/hardy/main'
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

    // THE HAPLOID VIEW
    //
    // PLINK 1.9, which the legacy chain ran, treats a heterozygous call on a haploid chromosome (a male's on
    // chromosome X outside a pseudo-autosomal region coded XY, anyone's on chromosome Y) and a nonmale's
    // chromosome Y call as missing in its frequency-based commands, and keeps them in every fileset it writes:
    // `--freq`, and so `--maf`, `--check-sex`'s frequencies and `--indep-pairwise`, ignore them, while
    // `--missing`, `--geno`, `--mind` and the genotypes `--check-sex` scores count them as called. plink2 counts
    // a heterozygous haploid call as half an allele in `--freq` and `--maf`, and counts an unknown-sex sample's
    // chromosome Y calls (verified on 1.90b6.21 and 2.0.0a.6.9). PLINK 1.9 also divides the samples into males
    // and nonmales, an unknown-sex sample with the females, where plink2 keeps unknown sex apart: it leaves those
    // samples out of the chromosome X Hardy-Weinberg test, which PLINK 1.9 runs over every nonmale. The view
    // is the stratum fileset as PLINK 1.9's frequency-based commands saw it: unknown sex recoded female, then
    // the invalid haploid calls set to missing with `--set-invalid-haploid-missing`, which also erases the
    // female, and so the formerly unknown-sex, chromosome Y calls. It is the one study-side intermediate fileset
    // of the chain, because plink2 applies that erasure only while writing a fileset, never within a statistics
    // run. It is read by the MAF run, the chromosome X Hardy-Weinberg run and the frequencies of the sex check,
    // and by nothing else: the missingness runs, the autosomal Hardy-Weinberg run, the sex check itself and the
    // terminal materialisation read the stratum fileset, whose heterozygous haploid calls the QC'd fileset
    // keeps, as the legacy filesets kept them. It is not published.

    //
    // MODULE: The sample file with every unknown sex recoded female
    //
    UNKNOWN_SEX_RECODE(
        ch_genotypes.map { meta, _bed, _bim, fam -> [meta, fam] }
    )

    //
    // MODULE: The haploid view; the erasure reaches plink2 through ext.args
    //
    def ch_haploid_view_inputs = ch_genotypes
        .map { meta, bed, bim, _fam -> [meta.id, meta, bed, bim] }
        .join(UNKNOWN_SEX_RECODE.out.fam.map { meta, fam -> [meta.id, fam] }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _id, meta, bed, bim, fam -> [meta, bed, bim, fam, [], [], [], []] }

    PLINK2_MAKEBED_HAPLOID_VIEW(ch_haploid_view_inputs)

    def ch_haploid_view_by_id = PLINK2_MAKEBED_HAPLOID_VIEW.out.bed.map { meta, bed, bim, fam -> [meta.id, bed, bim, fam] }

    //
    // MODULE: MAF keep-list; the threshold is native optional behaviour and reaches plink2 through ext.args
    //
    // Under --exclude_nonstandard_contigs the contig exclusion is applied here, at the first filter, and only
    // here: every later run extracts this keep-list, so no variant on a non-standard contig reaches a
    // statistic, a decision list, the ancestry route or the QC'd fileset. By default the exclusion slot is
    // empty and the keep-list carries every variant that passes the MAF. The frequencies are the haploid
    // view's, as the legacy `--maf` computed them; the view carries the stratum's variant IDs, so the keep-list
    // applies to the stratum fileset unchanged.
    PLINK2_WRITESNPLIST(
        ch_contig_genotypes_by_id
            .join(ch_haploid_view_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
            .map { _id, meta, _bed, _bim, _fam, contig_exclude, view_bed, view_bim, view_fam -> [meta, view_bed, view_bim, view_fam, [], contig_exclude, [], []] }
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
    // MODULE: Hardy-Weinberg report off chromosome X on the missingness-filtered set, as the legacy chain
    // measured it; chromosome X is left out through ext.args
    //
    def ch_hardy_lists_by_id = ch_maf_genotypes_by_id
        .join(ch_geno_exclude_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_mind_remove.map { meta, mind_remove -> [meta.id, mind_remove] }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    PLINK2_HARDY(
        ch_hardy_lists_by_id.map { _id, meta, bed, bim, fam, snplist, geno_exclude, mind_remove -> [meta, bed, bim, fam, snplist, geno_exclude, [], mind_remove] }
    )

    //
    // MODULE: Chromosome X Hardy-Weinberg report over the nonmale samples of the same set, on the haploid view
    //
    // PLINK 1.9 tested chromosome X with the ordinary exact test over its nonmale samples, females and unknown
    // sex alike; plink2 tests it with the Graffelman-Weir test over females and males and leaves unknown sex
    // out. With the males removed and unknown sex recoded female, plink2's test is PLINK 1.9's, to its printed
    // precision (verified on 1.90b6.21 and 2.0.0a.6.9). A stratum without a nonmale sample has no such report,
    // as plink2 stops when `--remove-males` leaves no sample; the report of the other chromosomes this run also
    // writes, over the nonmale samples alone, is not used.
    def ch_nonmale_hardy_inputs = ch_hardy_lists_by_id
        .join(ch_haploid_view_by_id, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .filter { _id, _meta, _bed, _bim, fam, _snplist, _geno_exclude, _mind_remove, _view_bed, _view_bim, _view_fam ->
            fam.readLines().any { line -> def fields = line.trim().split(/\s+/); fields.size() >= 5 && fields[4] != '1' }
        }
        .map { _id, meta, _bed, _bim, _fam, snplist, geno_exclude, mind_remove, view_bed, view_bim, view_fam -> [meta, view_bed, view_bim, view_fam, snplist, geno_exclude, [], mind_remove] }

    PLINK2_HARDY_NONMALE(ch_nonmale_hardy_inputs)

    //
    // MODULE: HWE exclusion list; the chromosome X report exists only for filesets that carry chromosome X and
    // a nonmale sample
    //
    def ch_hwe_inputs = PLINK2_HARDY.out.hardy
        .map { meta, hardy -> [meta.id, meta, hardy] }
        .join(PLINK2_HARDY_NONMALE.out.hardy_x.map { meta, hardy_x -> [meta.id, hardy_x] }, by: 0, remainder: true)
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
    haploid_view       = PLINK2_MAKEBED_HAPLOID_VIEW.out.bed // channel: [ val(meta), path(bed), path(bim), path(fam) ], the stratum with unknown sex recoded female and the invalid haploid calls missing; for frequencies only
    hardy              = PLINK2_HARDY.out.hardy // channel: [ val(meta), path(hardy) ], every chromosome but X
    hardy_x            = PLINK2_HARDY_NONMALE.out.hardy_x // channel: [ val(meta), path(hardy_x) ], over the nonmale samples; optional
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
