# Assemble the cross-stratum QC summary from the summary rows of every stratum, and cut from it the MultiQC
# tables of each QC stage. The rows must share one header, which is what makes them one table; a stratum
# whose row disagrees is a pipeline defect and stops the run.
#
# No shebang: the script runs under the pipeline's `process.shell`, strict bash, which a shebang would bypass.
#
# Files written:
#
#   gwasqc_summary.tsv                       one row per stratum, in stratum id order, every column
#   gwasqc_qc_summary_mqc.tsv                the same table as the first MultiQC section, the detail columns hidden
#   gwasqc_variant_qc_filters_mqc.tsv        the input counts and what each filter removed, with its threshold
#   gwasqc_sample_qc_markers_mqc.tsv         the marker set of each stratum's sample checks and the collapse note
#   gwasqc_sex_check_summary_mqc.tsv         samples checked and mismatches per stratum
#   gwasqc_heterozygosity_summary_mqc.tsv    the F distribution per stratum
#   gwasqc_relatedness_summary_mqc.tsv       pairs per class, removals and outliers per stratum
#   gwasqc_ancestry_summary_mqc.tsv          study samples per super-population and mismatches; only when the
#                                            rows carry ancestry columns
#   gwasqc_sample_removals_mqc.tsv           what the removal gate did or would do, and the final counts

summaries='!{summary_list}'

gawk -F'\t' -v OFS='\t' '
    FNR == 1 {
        if (header == "") {
            header = $0
            print header > "gwasqc_summary.tsv"
        }
        else if ($0 != header) {
            printf "the summary row of %s does not share the header of the first summary row\n", FILENAME > "/dev/stderr"
            exit 1
        }
        next
    }
    {
        if ($1 in rows) {
            printf "the stratum %s has more than one summary row\n", $1 > "/dev/stderr"
            exit 1
        }
        rows[$1] = $0
    }
    END {
        PROCINFO["sorted_in"] = "@ind_str_asc"
        for (stratum in rows) print rows[stratum] > "gwasqc_summary.tsv"
    }
' $summaries

# The column dictionary: title, description and number format of every known column. An unknown column, such
# as the per-super-population ancestry counts, is titled from its name.
cat > columns.tsv <<'EOF'
ancestry	Ancestry	The stratum's ancestry label from the samplesheet
samples_input	Samples in	Samples in the input fileset	{:,.0f}
variants_input	Variants in	Variants in the input fileset	{:,.0f}
variants_contig_removed	Contig removed	Variants on a contig outside 1-22, X, Y, XY and MT, such as an alt or random contig, excluded before every filter	{:,.0f}
maf_threshold	MAF threshold	Minor allele frequency below which a variant is dropped	{:g}
variants_maf_removed	MAF removed	Variants on the standard chromosomes below the MAF threshold	{:,.0f}
variants_after_maf	After MAF	Variants passing the MAF threshold	{:,.0f}
missingness_mode	Missingness mode	How the missingness thresholds were applied: iterative, the cumulative call-rate ladder from 90 % up to the call rate 1 - geno, or single, geno and then mind once
geno_threshold	geno threshold	Per-variant missing-call rate above which a variant is dropped; in iterative mode, the last rung applied	{:g}
variants_geno_removed	geno removed	Variants the applied missingness exclusions drop from the MAF-passing set, over every rung in iterative mode	{:,.0f}
variants_after_geno	After geno	Variants remaining after the geno exclusion	{:,.0f}
mind_threshold	mind threshold	Per-sample missing-call rate above which a sample is dropped; in iterative mode, the last rung applied	{:g}
samples_mind_removed	mind removed	Samples the applied missingness removals drop, each over the variants its step kept, over every rung in iterative mode	{:,.0f}
samples_after_mind	After mind	Samples remaining after the mind removal	{:,.0f}
hwe_threshold	HWE threshold	Hardy-Weinberg exact-test p-value below which a variant is dropped	{:g}
variants_hwe_removed	HWE removed	Variants below the HWE threshold	{:,.0f}
variants_after_hwe	Variants QC'd	Variants remaining after the HWE exclusion, the QC'd variant set	{:,.0f}
variants_ld_pruned_in	LD pruned in	Variants retained by LD pruning of the QC'd set in study mode; NA in shared mode	{:,.0f}
variants_ld_pruned_out	LD pruned out	Variants removed by LD pruning in study mode; NA in shared mode	{:,.0f}
variants_highld_excluded	High-LD excluded	Pruned variants in a long-range LD region or off the autosomes in study mode; NA in shared mode	{:,.0f}
variants_sample_checks	Study check set	Pruned autosomal variants outside the long-range LD regions, the set of the heterozygosity and relatedness reports in study mode; NA in shared mode	{:,.0f}
sample_qc_marker_set	Marker set	The marker set of the sample checks: study, the stratum's own LD-pruned QC'd variants, or shared, the reference-pruned markers of the ancestry route
sample_qc_shared_reference	Shared reference	The reference samples the shared marker set was filtered and pruned on: pooled, every reference sample, or matched, the reference samples of the stratum's super-population; NA in study mode
sample_qc_markers	Check markers	Autosomal markers the heterozygosity and relatedness reports ran on	{:,.0f}
sample_qc_note	Marker-set note	A note when study-mode LD pruning retained fewer than the configured fraction of the QC'd variants; empty otherwise
sex_check_problems	Sex mismatches	Samples the sex check flagged PROBLEM	{:,.0f}
sex_removals	Sex list	Whether the sex-mismatch list was applied to the QC'd fileset
het_samples	Het samples	Samples in the heterozygosity report	{:,.0f}
het_f_mean	Mean F	Mean inbreeding coefficient F	{:.4f}
het_f_sd	SD F	Standard deviation of F	{:.4f}
het_f_min	Min F	Smallest F	{:.4f}
het_f_max	Max F	Largest F	{:.4f}
het_outside_3sd	Beyond 3 SD	Samples whose F lies more than three standard deviations from the mean; informational, no sample is listed	{:,.0f}
relatedness_pairs_reported	Pairs reported	Pairs at or above the kinship table filter	{:,.0f}
relatedness_duplicate_or_mz	Duplicate/MZ	Pairs with kinship above 0.354	{:,.0f}
relatedness_parent_offspring	Parent-offspring	First-degree pairs with IBS0 at or below the parent-offspring bound	{:,.0f}
relatedness_full_sibling	Full sibling	First-degree pairs with IBS0 above the parent-offspring bound	{:,.0f}
relatedness_second_degree	Second degree	Pairs with kinship between 0.0884 and 0.177	{:,.0f}
relatedness_third_degree	Third degree	Pairs with kinship between 0.0442 and 0.0884	{:,.0f}
relatedness_removed	Duplicates listed	One member of each duplicate/MZ pair, the one with the higher missing-call rate	{:,.0f}
relatedness_removals	Duplicate list	Whether the duplicate list was applied to the QC'd fileset
relatedness_outliers	Kinship outliers	Samples whose mean kinship lies above the cohort mean by the configured standard deviations; listed, never applied	{:,.0f}
ancestry_unassigned	Unassigned	Study samples whose largest class probability did not reach the threshold, or that the centroid rule unassigned	{:,.0f}
ancestry_mismatches	Ancestry mismatches	Study samples not assigned to the stratum's label, the unassigned included	{:,.0f}
ancestry_removals	Ancestry list	Whether the ancestry mismatch list was applied to the QC'd fileset
samples_removed_under_gate	Gate removes	Samples the removal gate removes, or would remove when off: the union of the mind, sex, duplicate and, when configured, ancestry lists	{:,.0f}
samples_removed	Samples removed	Samples the QC'd fileset lost	{:,.0f}
samples_final	Samples out	Samples in the QC'd fileset	{:,.0f}
variants_final	Variants out	Variants in the QC'd fileset	{:,.0f}
EOF

# Write one MultiQC table from the named columns of the summary, the header block built from the dictionary.
# Arguments: the file, the section id, the parent id, the parent name, the parent description, the section
# name, the section description, then the column names; the stratum column is always first.
mqc_table() {
    local file="$1" id="$2" parent_id="$3" parent_name="$4" parent_description="$5" section_name="$6" description="$7"
    shift 7
    local hidden=''
    if [ "${1:-}" = '--hidden' ]; then
        hidden="$2"
        shift 2
    fi
    gawk -F'\t' -v OFS='\t' -v id="$id" -v parent_id="$parent_id" -v parent_name="$parent_name" -v parent_description="$parent_description" -v section_name="$section_name" -v description="$description" -v wanted="$*" -v hidden="$hidden" '
        FILENAME == "columns.tsv" { title[$1] = $2; text[$1] = $3; fmt[$1] = $4; next }
        FNR == 1 {
            for (i = 1; i <= NF; i++) index_of[$i] = i
            n = split(wanted, columns, " ")
            m = split(hidden, hidden_columns, " ")
            for (k = 1; k <= m; k++) is_hidden[hidden_columns[k]] = 1
            for (k = 1; k <= n; k++) if (!(columns[k] in index_of)) { printf "the summary has no column %s\n", columns[k] > "/dev/stderr"; exit 1 }
            print "# id: " id
            print "# parent_id: " parent_id
            print "# parent_name: \"" parent_name "\""
            print "# parent_description: \"" parent_description "\""
            print "# section_name: \"" section_name "\""
            print "# description: \"" description "\""
            print "# plot_type: table"
            print "# pconfig:"
            print "#     no_violin: true"
            print "#     col1_header: \"Stratum\""
            print "# headers:"
            for (k = 1; k <= n; k++) {
                column = columns[k]
                name = (column in title) ? title[column] : column
                if (column ~ /^ancestry_n_/) name = "N " substr(column, 12)
                print "#     " column ":"
                print "#         title: \"" name "\""
                if (column in text) print "#         description: \"" text[column] "\""
                else if (column ~ /^ancestry_n_/) print "#         description: \"Study samples assigned to " substr(column, 12) "\""
                if ((column in fmt) && fmt[column] != "") print "#         format: \"" fmt[column] "\""
                else if (column ~ /^ancestry_n_/) print "#         format: \"{:,.0f}\""
                if (column in is_hidden) print "#         hidden: true"
            }
            line = "stratum"
            for (k = 1; k <= n; k++) line = line OFS columns[k]
            print line
            next
        }
        {
            line = $1
            for (k = 1; k <= n; k++) line = line OFS $index_of[columns[k]]
            print line
        }
    ' columns.tsv gwasqc_summary.tsv > "$file"
}

# Every column of the summary, in its order; the ancestry group columns are whatever the rows carry.
all_columns=$(gawk -F'\t' 'NR == 1 { for (i = 2; i <= NF; i++) printf "%s%s", (i > 2 ? " " : ""), $i }' gwasqc_summary.tsv)
ancestry_columns=$(gawk -F'\t' 'NR == 1 { for (i = 2; i <= NF; i++) if ($i ~ /^ancestry_(n_|unassigned|mismatches|removals)/) printf "%s%s", (n++ ? " " : ""), $i }' gwasqc_summary.tsv)

summary_hidden='maf_threshold variants_after_maf missingness_mode geno_threshold variants_after_geno mind_threshold samples_after_mind hwe_threshold variants_ld_pruned_out variants_sample_checks sample_qc_shared_reference sample_qc_note sex_removals het_samples het_f_mean het_f_sd het_f_min het_f_max het_outside_3sd relatedness_pairs_reported relatedness_parent_offspring relatedness_full_sibling relatedness_second_degree relatedness_third_degree relatedness_removals relatedness_outliers ancestry_removals samples_removed_under_gate'
mqc_table gwasqc_qc_summary_mqc.tsv gwasqc_qc_summary gwasqc_qc_summary 'QC summary' 'One row per stratum: the samples and variants that entered, what each stage removed or listed, and what left. The hidden columns hold the thresholds and the per-stage detail; the sections below repeat them by stage.' 'QC summary' '' --hidden "$summary_hidden" $all_columns

variant_qc_description='Per stratum: the input fileset, the variants on contigs outside 1-22, X, Y, XY and MT, what each filter of the MAF, missingness and Hardy-Weinberg chain removes at its threshold, the call-rate ladder, the LD-pruned set the sample checks run on in study mode, and the review histograms.'
mqc_table gwasqc_variant_qc_filters_mqc.tsv gwasqc_variant_qc_filters gwasqc_variant_qc 'Variant and sample filters' "$variant_qc_description" 'Filters' 'Variants and samples removed by each filter at its threshold, applied in this order from the input fileset after the variants on non-standard contigs are excluded; every comparison is strict, as in plink2. In iterative missingness mode the geno and mind columns count every rung of the call-rate ladder up to the threshold shown. The pruning columns read NA for a stratum in the shared marker-set mode, which prunes nothing on the study side.' \
    samples_input variants_input variants_contig_removed maf_threshold variants_maf_removed variants_after_maf missingness_mode geno_threshold variants_geno_removed variants_after_geno mind_threshold samples_mind_removed samples_after_mind hwe_threshold variants_hwe_removed variants_after_hwe variants_ld_pruned_in variants_ld_pruned_out variants_highld_excluded variants_sample_checks

mqc_table gwasqc_sample_qc_markers_mqc.tsv gwasqc_sample_qc_markers gwasqc_sample_qc_markers 'Sample QC marker set' 'The variant set the sex check, heterozygosity and relatedness reports of each stratum ran on, chosen per stratum by --sample_qc_marker_set: study, the stratum'"'"'s own LD-pruned QC'"'"'d variants, or shared, the harmonised reference-pruned markers of the ancestry route with the ancestry-matched reference frequencies as the heterozygosity baseline; under auto a stratum with fewer than --small_n_threshold samples after the mind filter takes shared. A shared marker set is filtered and LD-pruned on the pooled reference panel or on the reference samples of the stratum'"'"'s super-population, as --sample_qc_shared_reference chose. The note flags study-mode pruning that retained fewer than the --ld_min_retained_fraction floor of the QC'"'"'d variants, the signature of pruning collapse on a small stratum.' 'Marker set' 'The mode of each stratum, the reference samples a shared set was chosen on, the markers its autosomal checks ran on, and the pruning-collapse note.' \
    samples_after_mind sample_qc_marker_set sample_qc_shared_reference sample_qc_markers variants_after_hwe variants_ld_pruned_in sample_qc_note

mqc_table gwasqc_sex_check_summary_mqc.tsv gwasqc_sex_check_summary gwasqc_sex_check 'Sex check' 'plink2 --check-sex after the pseudo-autosomal split, over the pruned set in study mode and over every QC-passing variant in shared mode. Its PROBLEM calls are the mismatches, tabled and listed for removal.' 'Summary' 'Samples checked, the mismatches plink2 called, and whether the list reached the QC fileset.' \
    samples_after_mind sex_check_problems sex_removals

mqc_table gwasqc_heterozygosity_summary_mqc.tsv gwasqc_heterozygosity_summary gwasqc_heterozygosity 'Heterozygosity' 'Report only: the plink2 --het inbreeding coefficient F over the autosomal marker set of each stratum, the pruned set outside the long-range LD regions in study mode and the shared reference-pruned markers against the matched reference frequencies in shared mode. No threshold is applied and no sample is listed.' 'Summary' 'The distribution of F per stratum, with the marker set it was computed on.' \
    sample_qc_marker_set sample_qc_markers het_samples het_f_mean het_f_sd het_f_min het_f_max het_outside_3sd

mqc_table gwasqc_relatedness_summary_mqc.tsv gwasqc_relatedness_summary gwasqc_relatedness 'Relatedness' 'KING-robust kinship over the same autosomal marker set, pairs at or above the table filter classified on KING boundaries. One member of each duplicate/MZ pair is listed for removal; the mean-kinship outliers are listed and never applied.' 'Summary' 'Reported pairs per relationship class, the duplicate members listed and the mean-kinship outliers.' \
    relatedness_pairs_reported relatedness_duplicate_or_mz relatedness_parent_offspring relatedness_full_sibling relatedness_second_degree relatedness_third_degree relatedness_removed relatedness_removals relatedness_outliers

if [ -n "$ancestry_columns" ]; then
    mqc_table gwasqc_ancestry_summary_mqc.tsv gwasqc_ancestry_summary gwasqc_ancestry 'Ancestry' 'Study samples projected onto the reference principal components and assigned by the elastic-net multinomial classifier of the legacy pipeline, trained on the reference. The samples not assigned to the stratum label are its mismatches.' 'Summary' 'Study samples assigned per super-population against the stratum label, the unassigned, and the mismatches listed for removal.' \
        ancestry $ancestry_columns
fi

removal_columns='samples_mind_removed sex_check_problems sex_removals relatedness_removed relatedness_removals'
if [ -n "$ancestry_columns" ]; then
    removal_columns="$removal_columns ancestry_mismatches ancestry_removals"
fi
mqc_table gwasqc_sample_removals_mqc.tsv gwasqc_sample_removals gwasqc_sample_removals 'Sample removals' 'What the removal gate did or would do. The mind removals always apply; the sex-mismatch, duplicate and ancestry-mismatch lists reach the QC fileset only under --apply_sample_removals, and the ancestry list only while --ancestry_remove_mismatched holds.' 'Sample removals' '' \
    $removal_columns samples_removed_under_gate samples_removed samples_final variants_final
