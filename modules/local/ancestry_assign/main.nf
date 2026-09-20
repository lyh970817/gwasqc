process ANCESTRY_ASSIGN {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ac/ac330e254aed1e019ded0a6140463199760e9ee8f1cf398670eb40ccee61ed14/data'
        : 'community.wave.seqera.io/library/r-base_r-ggplot2_r-data.table:785e51271c23bbdc'}"

    input:
    tuple val(meta), path(reference_scores), path(study_scores)
    path pop_data
    val prob_threshold
    val sd_filter

    output:
    tuple val(meta), path("${prefix}.ancestry_assignment.tsv"), emit: assignment
    tuple val(meta), path("${prefix}.ancestry_summary.tsv"), emit: summary
    tuple val(meta), path("${prefix}.ancestry_model.tsv"), emit: model
    tuple val(meta), path("${prefix}.ancestry_*.keep"), emit: keep_lists
    tuple val(meta), path("${prefix}.ancestry_mismatch_remove.txt"), emit: sample_remove
    tuple val(meta), path("${prefix}.ancestry_pca.tsv"), emit: pca_data
    tuple val(meta), path("${prefix}.ancestry_pc1_pc2.pdf"), path("${prefix}.ancestry_pc1_pc2.png"), emit: pc1_pc2_plot
    tuple val(meta), path("${prefix}.ancestry_pc3_pc4.pdf"), path("${prefix}.ancestry_pc3_pc4.png"), emit: pc3_pc4_plot
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // rows are written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` and `expected_ancestry` must remain visible to the template; the stratum's own label decides
    // the mismatch list.
    prefix = task.ext.prefix ?: "${meta.id}"
    expected_ancestry = meta.ancestry
    template('ancestry_assign.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf 'FID\\tIID\\tASSIGNED\\tSTATUS\\tMAX_PROB\\tMAX_ABS_Z\\n' > ${prefix}.ancestry_assignment.tsv
    printf 'GROUP\\tN_REFERENCE\\tN_STUDY\\tRULE\\n' > ${prefix}.ancestry_summary.tsv
    printf 'OBSERVED\\tPREDICTED\\tN\\n' > ${prefix}.ancestry_model.tsv
    touch ${prefix}.ancestry_${meta.ancestry}.keep
    touch ${prefix}.ancestry_mismatch_remove.txt
    printf 'FID\\tIID\\tSOURCE\\tPOP\\tSUPER_POP\\tASSIGNED\\n' > ${prefix}.ancestry_pca.tsv
    touch ${prefix}.ancestry_pc1_pc2.pdf
    touch ${prefix}.ancestry_pc1_pc2.png
    touch ${prefix}.ancestry_pc3_pc4.pdf
    touch ${prefix}.ancestry_pc3_pc4.png
    Rscript -e 'writeLines(c("\\"${task.process}\\":", paste0("    r-base: ", paste(R.version[["major"]], R.version[["minor"]], sep = ".")), paste0("    r-ggplot2: ", packageVersion("ggplot2")), paste0("    r-data.table: ", packageVersion("data.table")), paste0("    r-mass: ", packageVersion("MASS"))), "versions.yml")'
    """
}
