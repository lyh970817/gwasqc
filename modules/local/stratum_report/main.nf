process STRATUM_REPORT {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0c/0c4365ad2ac928e4b018455102731c78cfcf43ecd4cb8178c12cd00c02f6ee29/data'
        : 'community.wave.seqera.io/library/gawk:5.3.1--d5d074ad9f29be71'}"

    input:
    // The original and the QC'd fileset members are staged apart because a stratum's input fileset may carry
    // any basename; the figures are staged by the report section they belong to. The study-side pruning lists
    // are present for a stratum in study mode and the shared marker list for one in shared mode; the other
    // slot is an empty list. The reference used and the size of the matched group arrive with the shared
    // marker list, NA for a stratum in study mode.
    tuple val(meta), path(fam, stageAs: 'input/*'), path(bim, stageAs: 'input/*'), path(contig_exclude), path(maf_snplist), path(geno_exclude), path(mind_remove), path(hwe_exclude), path(ladder), path(prune_in), path(highld_exclude), path(shared_markers), val(shared_reference), val(n_reference_matched), path(sex_mismatch), path(het), path(relatedness_pairs), path(relatedness_remove), path(relatedness_outliers), path(ancestry_summary), path(ancestry_mismatch_remove), path(qc_bim, stageAs: 'qc/*'), path(qc_fam, stageAs: 'qc/*'), path(variant_qc_images, stageAs: 'images/variant_qc/*'), path(sex_check_images, stageAs: 'images/sex_check/*'), path(heterozygosity_images, stageAs: 'images/heterozygosity/*'), path(relatedness_images, stageAs: 'images/relatedness/*'), path(ancestry_images, stageAs: 'images/ancestry/*')
    val maf
    val geno
    val mind
    val hwe
    val missingness_mode
    val ld_min_retained_fraction
    val sample_qc_shared_reference
    val apply_sample_removals
    val ancestry_remove_mismatched

    output:
    tuple val(meta), path("${prefix}.qc_summary.tsv"), emit: summary
    tuple val(meta), path("${prefix}.*_mqc.{tsv,yaml}"), emit: multiqc
    tuple val("${task.process}"), val("gawk"), eval("gawk --version | head -n 1 | sed 's/^GNU Awk //; s/,.*\$//'"), emit: versions_gawk, topic: versions
    tuple val("${task.process}"), val("coreutils"), eval("base64 --version | head -n 1 | sed 's/^base64 (GNU coreutils) //'"), emit: versions_coreutils, topic: versions

    when:
    task.ext.when == null || task.ext.when

    shell:
    // The template reads these; an absent optional input is an empty string and an image list a blank-separated
    // list of staged paths.
    prefix = task.ext.prefix ?: "${meta.id}"
    contig_exclude_file = contig_exclude ? contig_exclude.toString() : ''
    prune_in_file = prune_in ? prune_in.toString() : ''
    highld_exclude_file = highld_exclude ? highld_exclude.toString() : ''
    shared_markers_file = shared_markers ? shared_markers.toString() : ''
    ancestry_summary_file = ancestry_summary ? ancestry_summary.toString() : ''
    ancestry_mismatch_remove_file = ancestry_mismatch_remove ? ancestry_mismatch_remove.toString() : ''
    variant_qc_image_list = [variant_qc_images].flatten().collect { image -> image.toString() }.join(' ')
    sex_check_image_list = [sex_check_images].flatten().collect { image -> image.toString() }.join(' ')
    heterozygosity_image_list = [heterozygosity_images].flatten().collect { image -> image.toString() }.join(' ')
    relatedness_image_list = [relatedness_images].flatten().collect { image -> image.toString() }.join(' ')
    ancestry_image_list = [ancestry_images].flatten().collect { image -> image.toString() }.join(' ')
    template('stratum_report.sh')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf 'stratum\\tancestry\\tsamples_input\\tvariants_input\\tvariants_contig_removed\\tmissingness_mode\\tsample_qc_marker_set\\tsamples_final\\tvariants_final\\n' > ${prefix}.qc_summary.tsv
    printf '# id: gwasqc_variant_qc_ladder\\n# plot_type: table\\nrow\\tstratum\\tcall_rate\\n' > ${prefix}.variant_qc_ladder_mqc.tsv
    printf 'id: gwasqc_variant_qc_plots_${meta.id}\\nplot_type: image\\ndata: ""\\n' > ${prefix}.variant_qc_plots_mqc.yaml
    """
}
