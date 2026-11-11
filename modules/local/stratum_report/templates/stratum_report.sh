# Assemble the QC summary row of one stratum and the MultiQC custom-content fragments that carry its per-row
# tables and figures. Every number is a line count of a decision list or a row count or column statistic of a
# published table; nothing is re-decided and no log is read. The per-stage summary sections are cut from the
# summary rows of all strata by qc_summary, so this script writes only what is row-wise per stratum.
#
# No shebang: the script runs under the pipeline's `process.shell`, strict bash, which a shebang would bypass.
#
# Files written:
#
#   <prefix>.qc_summary.tsv                     one header row and one row of counts for the stratum, with the
#                                               marker set of its sample checks and a note when study-mode
#                                               pruning collapsed
#   <prefix>.variant_qc_ladder_mqc.tsv          the call-rate ladder, one MultiQC row per rung
#   <prefix>.sex_check_mismatches_mqc.tsv       the sex mismatch table, one row per sample; absent when empty
#   <prefix>.relatedness_pairs_mqc.tsv          the duplicate/MZ and first-degree pairs; absent when empty
#   <prefix>.<stage>_plots_mqc.yaml             the stage's figures embedded as one MultiQC image section, for
#                                               each stage that has figures

prefix='!{prefix}'
stratum='!{meta.id}'
ancestry='!{meta.ancestry}'
# The thresholds arrive as Groovy renders them (1e-10 as 1.0E-10); they are recorded in the shortest form.
maf=$(gawk -v value='!{maf}' 'BEGIN { printf "%g", value }')
geno=$(gawk -v value='!{geno}' 'BEGIN { printf "%g", value }')
mind=$(gawk -v value='!{mind}' 'BEGIN { printf "%g", value }')
hwe=$(gawk -v value='!{hwe}' 'BEGIN { printf "%g", value }')
ld_min_retained_fraction=$(gawk -v value='!{ld_min_retained_fraction}' 'BEGIN { printf "%g", value }')
sample_qc_marker_set='!{meta.sample_qc_marker_set}'
sample_qc_shared_reference='!{sample_qc_shared_reference}'
apply_sample_removals='!{apply_sample_removals}'
ancestry_remove_mismatched='!{ancestry_remove_mismatched}'
fam='!{fam}'
bim='!{bim}'
contig_exclude='!{contig_exclude}'
maf_snplist='!{maf_snplist}'
geno_exclude='!{geno_exclude}'
mind_remove='!{mind_remove}'
hwe_exclude='!{hwe_exclude}'
ladder='!{ladder}'
prune_in='!{prune_in_file}'
highld_exclude='!{highld_exclude_file}'
shared_markers='!{shared_markers_file}'
sex_mismatch='!{sex_mismatch}'
het='!{het}'
relatedness_pairs='!{relatedness_pairs}'
relatedness_remove='!{relatedness_remove}'
relatedness_outliers='!{relatedness_outliers}'
ancestry_summary='!{ancestry_summary_file}'
ancestry_mismatch_remove='!{ancestry_mismatch_remove_file}'
qc_bim='!{qc_bim}'
qc_fam='!{qc_fam}'
variant_qc_images='!{variant_qc_image_list}'
sex_check_images='!{sex_check_image_list}'
heterozygosity_images='!{heterozygosity_image_list}'
relatedness_images='!{relatedness_image_list}'
ancestry_images='!{ancestry_image_list}'

# Lines of a list, zero for an empty file; rows of a headed table.
lines() {
    if [ -s "$1" ]; then gawk 'END { print NR }' "$1"; else printf '0\n'; fi
}
rows() {
    local n
    n=$(lines "$1")
    if [ "$n" -gt 0 ]; then printf '%d\n' $((n - 1)); else printf '0\n'; fi
}

# The summary row is accumulated as two aligned arrays.
columns=()
values=()
add() {
    columns+=("$1")
    values+=("$2")
}

# Input fileset and the variant and sample filter chain, in the order the lists were derived: the variants on
# non-standard contigs first, then MAF over the rest.
samples_input=$(lines "$fam")
variants_input=$(lines "$bim")
variants_contig_removed=$(lines "$contig_exclude")
variants_after_maf=$(lines "$maf_snplist")
variants_geno_removed=$(lines "$geno_exclude")
variants_after_geno=$((variants_after_maf - variants_geno_removed))
samples_mind_removed=$(lines "$mind_remove")
samples_after_mind=$((samples_input - samples_mind_removed))
variants_hwe_removed=$(lines "$hwe_exclude")
variants_after_hwe=$((variants_after_geno - variants_hwe_removed))
add stratum "$stratum"
add ancestry "$ancestry"
add samples_input "$samples_input"
add variants_input "$variants_input"
add variants_contig_removed "$variants_contig_removed"
add maf_threshold "$maf"
add variants_maf_removed $((variants_input - variants_contig_removed - variants_after_maf))
add variants_after_maf "$variants_after_maf"
add geno_threshold "$geno"
add variants_geno_removed "$variants_geno_removed"
add variants_after_geno "$variants_after_geno"
add mind_threshold "$mind"
add samples_mind_removed "$samples_mind_removed"
add samples_after_mind "$samples_after_mind"
add hwe_threshold "$hwe"
add variants_hwe_removed "$variants_hwe_removed"
add variants_after_hwe "$variants_after_hwe"

# The marker set of the sample checks. In study mode it is the stratum's own pruned autosomal set outside the
# long-range LD regions, and pruning that kept fewer than the configured fraction of the QC'd variants is
# noted, because pairwise r-squared over a handful of samples collapses the set; in shared mode there is no
# study-side pruning and the set is the reference-pruned shared marker list, pruned on the pooled or the
# ancestry-matched reference samples as recorded, so the pruning columns read NA, as does the reference
# choice in study mode.
sample_qc_note=''
shared_reference='NA'
if [ "$sample_qc_marker_set" = 'shared' ]; then
    shared_reference=$sample_qc_shared_reference
    variants_ld_pruned_in='NA'
    variants_ld_pruned_out='NA'
    variants_highld_excluded='NA'
    variants_sample_checks='NA'
    sample_qc_markers=$(lines "$shared_markers")
else
    variants_ld_pruned_in=$(lines "$prune_in")
    variants_ld_pruned_out=$((variants_after_hwe - variants_ld_pruned_in))
    variants_highld_excluded=$(lines "$highld_exclude")
    variants_sample_checks=$((variants_ld_pruned_in - variants_highld_excluded))
    sample_qc_markers=$variants_sample_checks
    if gawk -v kept="$variants_ld_pruned_in" -v total="$variants_after_hwe" -v floor="$ld_min_retained_fraction" 'BEGIN { exit !(total > 0 && kept / total < floor) }'; then
        sample_qc_note=$(gawk -v kept="$variants_ld_pruned_in" -v total="$variants_after_hwe" -v floor="$ld_min_retained_fraction" 'BEGIN { printf "LD pruning retained %d of %d QC variants (%.1f%%, below the --ld_min_retained_fraction floor of %g); the study-pruned marker set is unreliable at this sample size, consider --sample_qc_marker_set shared", kept, total, 100 * kept / total, floor }')
    fi
fi
add variants_ld_pruned_in "$variants_ld_pruned_in"
add variants_ld_pruned_out "$variants_ld_pruned_out"
add variants_highld_excluded "$variants_highld_excluded"
add variants_sample_checks "$variants_sample_checks"
add sample_qc_marker_set "$sample_qc_marker_set"
add sample_qc_shared_reference "$shared_reference"
add sample_qc_markers "$sample_qc_markers"
add sample_qc_note "$sample_qc_note"

# Sex check: plink2's PROBLEM rows, tabled with their header.
sex_check_problems=$(rows "$sex_mismatch")
if [ "$apply_sample_removals" = 'true' ]; then gate='applied'; else gate='listed only'; fi
if [ "$apply_sample_removals" = 'true' ] && [ "$ancestry_remove_mismatched" = 'true' ]; then ancestry_gate='applied'; else ancestry_gate='listed only'; fi
add sex_check_problems "$sex_check_problems"
add sex_removals "$gate"

# Heterozygosity, report only: the distribution of F and the samples beyond three standard deviations of it.
IFS=$'\t' read -r het_samples het_f_mean het_f_sd het_f_min het_f_max het_outside_3sd < <(
    gawk -F'\t' '
        NR == 1 { for (i = 1; i <= NF; i++) if ($i == "F") column = i; next }
        { n++; f[n] = $column + 0; sum += f[n]; if (n == 1 || f[n] < min) min = f[n]; if (n == 1 || f[n] > max) max = f[n] }
        END {
            mean = n ? sum / n : 0
            for (i = 1; i <= n; i++) ss += (f[i] - mean) ^ 2
            sd = n > 1 ? sqrt(ss / (n - 1)) : 0
            for (i = 1; i <= n; i++) if (sd > 0 && (f[i] - mean > 3 * sd || mean - f[i] > 3 * sd)) outside++
            printf "%d\t%.6f\t%.6f\t%.6f\t%.6f\t%d\n", n, mean, sd, n ? min : 0, n ? max : 0, outside
        }
    ' "$het"
)
add het_samples "$het_samples"
add het_f_mean "$het_f_mean"
add het_f_sd "$het_f_sd"
add het_f_min "$het_f_min"
add het_f_max "$het_f_max"
add het_outside_3sd "$het_outside_3sd"

# Relatedness: the classified pairs, the duplicate members listed and the mean-kinship outliers.
IFS=$'\t' read -r pairs_reported pairs_duplicate pairs_parent_offspring pairs_full_sibling pairs_second pairs_third < <(
    gawk -F'\t' '
        NR == 1 { for (i = 1; i <= NF; i++) if ($i == "RELATIONSHIP") column = i; next }
        { n++; class[$column]++ }
        END { printf "%d\t%d\t%d\t%d\t%d\t%d\n", n, class["duplicate_or_mz"], class["parent_offspring"], class["full_sibling"], class["second_degree"], class["third_degree"] }
    ' "$relatedness_pairs"
)
relatedness_removed=$(lines "$relatedness_remove")
add relatedness_pairs_reported "$pairs_reported"
add relatedness_duplicate_or_mz "$pairs_duplicate"
add relatedness_parent_offspring "$pairs_parent_offspring"
add relatedness_full_sibling "$pairs_full_sibling"
add relatedness_second_degree "$pairs_second"
add relatedness_third_degree "$pairs_third"
add relatedness_removed "$relatedness_removed"
add relatedness_removals "$gate"
add relatedness_outliers "$(lines "$relatedness_outliers")"

# Ancestry, when it ran: the study samples assigned per super-population in the summary's order, the
# unassigned, and the mismatches listed against the stratum's own label.
ancestry_mismatches=0
if [ -n "$ancestry_summary" ]; then
    while IFS=$'\t' read -r column value; do
        add "$column" "$value"
    done < <(
        gawk -F'\t' '
            NR == 1 { for (i = 1; i <= NF; i++) index_of[$i] = i; next }
            $index_of["STATUS"] == "assigned" { groups[++g] = $index_of["GROUP"]; assigned[$index_of["GROUP"]] = $index_of["N_STUDY"] }
            $index_of["STATUS"] != "assigned" { unassigned += $index_of["N_STUDY"] }
            END {
                for (i = 1; i <= g; i++) printf "ancestry_n_%s\t%d\n", groups[i], assigned[groups[i]]
                printf "ancestry_unassigned\t%d\n", unassigned
            }
        ' "$ancestry_summary"
    )
    ancestry_mismatches=$(lines "$ancestry_mismatch_remove")
    add ancestry_mismatches "$ancestry_mismatches"
    add ancestry_removals "$ancestry_gate"
fi

# The gate: the union of the lists it applies, or would apply, against what the fileset actually lost.
samples_final=$(lines "$qc_fam")
variants_final=$(lines "$qc_bim")
union_lists=("$mind_remove")
if [ -s "$sex_mismatch" ]; then
    # The mismatch table is the removal list's source; its ID columns are read here so that the module needs
    # no second copy of the same samples.
    gawk -F'\t' '
        NR == 1 { sub(/^#/, "", $1); for (i = 1; i <= NF; i++) index_of[$i] = i; next }
        { if ("FID" in index_of) print $index_of["FID"], $index_of["IID"]; else print $index_of["IID"] }
    ' "$sex_mismatch" > sex_removals.txt
    union_lists+=(sex_removals.txt)
fi
union_lists+=("$relatedness_remove")
if [ -n "$ancestry_mismatch_remove" ] && [ "$ancestry_remove_mismatched" = 'true' ]; then
    union_lists+=("$ancestry_mismatch_remove")
fi
samples_removed_under_gate=$(gawk 'NF { keys[$0] = 1 } END { print length(keys) }' "${union_lists[@]}")
add samples_removed_under_gate "$samples_removed_under_gate"
add samples_removed $((samples_input - samples_final))
add samples_final "$samples_final"
add variants_final "$variants_final"

{
    (IFS=$'\t'; printf '%s\n' "${columns[*]}")
    (IFS=$'\t'; printf '%s\n' "${values[*]}")
} > "${prefix}.qc_summary.tsv"

# MultiQC fragments. Fragments of one section id from every stratum are merged by MultiQC into one table, and
# parent_id groups the sections of one stage under one heading; the header block is repeated verbatim in
# every fragment because MultiQC reads it from each.
mqc_header() {
    printf '# id: %s\n# parent_id: %s\n# parent_name: "%s"\n# parent_description: "%s"\n# section_name: "%s"\n# description: "%s"\n# plot_type: table\n' "$1" "$2" "$3" "$4" "$5" "$6"
}
variant_qc_description='Per stratum: the input fileset, the variants on contigs outside 1-22, X, Y, XY and MT, what each filter of the MAF, missingness and Hardy-Weinberg chain removes at its threshold, the call-rate ladder, the LD-pruned set the sample checks run on, and the review histograms.'
sex_check_description='plink2 --check-sex after the pseudo-autosomal split, over the pruned set in study mode and over every QC-passing variant in shared mode. Its PROBLEM calls are the mismatches, tabled and listed for removal.'
heterozygosity_description='Report only: the plink2 --het inbreeding coefficient F over the autosomal marker set of each stratum, the pruned set outside the long-range LD regions in study mode and the shared reference-pruned markers against the matched reference frequencies in shared mode. No threshold is applied and no sample is listed.'
relatedness_description='KING-robust kinship over the same autosomal marker set, pairs at or above the table filter classified on KING boundaries. One member of each duplicate/MZ pair is listed for removal; the mean-kinship outliers are listed and never applied.'
ancestry_description='Study samples projected onto the reference principal components and assigned by linear discriminant analysis. The samples not assigned to the stratum label are its mismatches.'

{
    mqc_header gwasqc_variant_qc_ladder gwasqc_variant_qc 'Variant and sample filters' "$variant_qc_description" 'Missingness ladder' 'Each call rate applied from the base fileset, the variant threshold first and the sample threshold second, as the legacy iterative missingness did; one row per stratum and rate.'
    cat <<'EOF'
# pconfig:
#     no_violin: true
#     col1_header: "Stratum and call rate"
# headers:
#     stratum:
#         title: "Stratum"
#     call_rate:
#         title: "Call rate (%)"
#         format: "{:.0f}"
#     missing_threshold:
#         title: "Missing-call threshold"
#         format: "{:.2f}"
#     variants_removed:
#         title: "Variants removed"
#         format: "{:,.0f}"
#     variants_remaining:
#         title: "Variants remaining"
#         format: "{:,.0f}"
#     samples_removed:
#         title: "Samples removed"
#         format: "{:,.0f}"
#     samples_remaining:
#         title: "Samples remaining"
#         format: "{:,.0f}"
EOF
    gawk -F'\t' -v OFS='\t' -v stratum="$stratum" '
        NR == 1 { print "row", "stratum", $0; next }
        { print stratum ":" $1 "%", stratum, $0 }
    ' "$ladder"
} > "${prefix}.variant_qc_ladder_mqc.tsv"

if [ "$sex_check_problems" -gt 0 ]; then
    {
        mqc_header gwasqc_sex_check_mismatches gwasqc_sex_check 'Sex check' "$sex_check_description" 'Mismatches' 'The PROBLEM rows of the --check-sex report: recorded and imputed sex, the chromosome X inbreeding coefficient F and the chromosome Y call count.'
        cat <<'EOF'
# pconfig:
#     no_violin: true
#     col1_header: "Stratum and sample"
# headers:
#     stratum:
#         title: "Stratum"
#     F:
#         title: "F"
#         description: "Chromosome X inbreeding coefficient"
#         format: "{:.4f}"
#     YRATE:
#         title: "Y rate"
#         format: "{:.4f}"
EOF
        gawk -F'\t' -v OFS='\t' -v stratum="$stratum" '
            NR == 1 { sub(/^#/, "", $1); for (i = 1; i <= NF; i++) if ($i == "IID") column = i; print "row", "stratum", $0; next }
            { print stratum ":" $column, stratum, $0 }
        ' "$sex_mismatch"
    } > "${prefix}.sex_check_mismatches_mqc.tsv"
fi

if [ $((pairs_duplicate + pairs_parent_offspring + pairs_full_sibling)) -gt 0 ]; then
    {
        mqc_header gwasqc_relatedness_pairs gwasqc_relatedness 'Relatedness' "$relatedness_description" 'Duplicate and first-degree pairs' 'Pairs classified duplicate/MZ, parent-offspring or full sibling, with the member listed for removal where the pair is a duplicate.'
        cat <<'EOF'
# pconfig:
#     no_violin: true
#     col1_header: "Stratum and pair"
# headers:
#     stratum:
#         title: "Stratum"
#     KINSHIP:
#         title: "Kinship"
#         format: "{:.4f}"
#     IBS0:
#         title: "IBS0"
#         format: "{:.4f}"
#     RELATIONSHIP:
#         title: "Relationship"
#     REMOVED:
#         title: "Listed for removal"
EOF
        gawk -F'\t' -v OFS='\t' -v stratum="$stratum" -v remove_file="$relatedness_remove" '
            BEGIN { while ((getline line < remove_file) > 0) if (line != "") removed[line] = 1 }
            function key(fid_column, iid_column) { return fid_column ? $fid_column " " $iid_column : $iid_column }
            NR == 1 {
                sub(/^#/, "", $1)
                for (i = 1; i <= NF; i++) index_of[$i] = i
                # The pair ID columns are IID1/IID2, or ID1/ID2 in the bare id colset the decision module also accepts.
                iid1 = ("IID1" in index_of) ? index_of["IID1"] : index_of["ID1"]
                iid2 = ("IID2" in index_of) ? index_of["IID2"] : index_of["ID2"]
                print "row", "stratum", "IID1", "IID2", "KINSHIP", "IBS0", "RELATIONSHIP", "REMOVED"
                next
            }
            $index_of["RELATIONSHIP"] ~ /^(duplicate_or_mz|parent_offspring|full_sibling)$/ {
                first = key(index_of["FID1"], iid1); second = key(index_of["FID2"], iid2)
                listed = (first in removed) ? $iid1 : ((second in removed) ? $iid2 : "none")
                print stratum ":" $iid1 "/" $iid2, stratum, $iid1, $iid2, $index_of["KINSHIP"], $index_of["IBS0"], $index_of["RELATIONSHIP"], listed
            }
        ' "$relatedness_pairs"
    } > "${prefix}.relatedness_pairs_mqc.tsv"
fi

# One image section per stage, the stratum's figures embedded as base64 PNGs so that the report is standalone.
image_section() {
    local stage="$1" parent_id="$2" parent_name="$3" parent_description="$4" description="$5" images="$6"
    [ -n "$images" ] || return 0
    {
        printf 'id: %s_plots_%s\n' "$parent_id" "$stratum"
        printf 'parent_id: %s\nparent_name: "%s"\nparent_description: "%s"\n' "$parent_id" "$parent_name" "$parent_description"
        printf 'section_name: "%s plots"\ndescription: "%s"\nplot_type: image\n' "$stratum" "$description"
        printf "data: '<div class=\"mqc-custom-content-image\" style=\"display:flex;flex-wrap:wrap;gap:1em;align-items:flex-start\">"
        for image in $images; do
            printf '<img src="data:image/png;base64,%s" style="max-width:48%%;height:auto" alt="%s"/>' "$(base64 -w 0 "$image")" "$(basename "$image")"
        done
        printf "</div>'\n"
    } > "${prefix}.${stage}_plots_mqc.yaml"
}
if [ "$sample_qc_marker_set" = 'shared' ]; then
    marker_note="the shared marker set: $sample_qc_markers reference-pruned markers with the ancestry-matched reference frequencies as the heterozygosity baseline, and every QC-passing chromosome X and Y variant, unpruned, for the sex check"
else
    marker_note="the study marker set: $sample_qc_markers pruned autosomal variants outside the long-range LD regions, and the pruned set with chromosome X for the sex check"
fi
image_section variant_qc gwasqc_variant_qc 'Variant and sample filters' "$variant_qc_description" "Missingness histograms, the call-rate ladder and the Hardy-Weinberg histograms of $stratum." "$variant_qc_images"
image_section sex_check gwasqc_sex_check 'Sex check' "$sex_check_description" "Chromosome X F histogram by recorded sex of $stratum, over $marker_note." "$sex_check_images"
image_section heterozygosity gwasqc_heterozygosity 'Heterozygosity' "$heterozygosity_description" "F histogram, with the reference distribution beneath the study's in shared mode, and the heterozygosity-against-sex-check scatter of $stratum, over $marker_note." "$heterozygosity_images"
image_section relatedness gwasqc_relatedness 'Relatedness' "$relatedness_description" "Kinship histogram of $stratum, over $marker_note." "$relatedness_images"
image_section ancestry gwasqc_ancestry 'Ancestry' "$ancestry_description" "Reference principal components with the study samples of $stratum drawn above the reference populations." "$ancestry_images"
