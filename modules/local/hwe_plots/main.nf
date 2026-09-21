process HWE_PLOTS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ac/ac330e254aed1e019ded0a6140463199760e9ee8f1cf398670eb40ccee61ed14/data'
        : 'community.wave.seqera.io/library/r-base_r-ggplot2_r-data.table:785e51271c23bbdc'}"

    input:
    tuple val(meta), path(hardy), path(hardy_x)
    val hwe

    output:
    tuple val(meta), path("${prefix}.hwe_hist.tsv"), emit: hist_data
    tuple val(meta), path("${prefix}.hwe_hist.pdf"), path("${prefix}.hwe_hist.png"), emit: hist_plot
    tuple val(meta), path("${prefix}.hwe_hist_window.tsv"), emit: window_data
    tuple val(meta), path("${prefix}.hwe_hist_window.pdf"), path("${prefix}.hwe_hist_window.png"), emit: window_plot
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // rows are written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations above; the template reads both assignments.
    prefix = task.ext.prefix ?: "${meta.id}"
    hardy_x_file = hardy_x ? hardy_x.toString() : ''
    template('hwe_plots.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf 'report\\tbin_start\\tbin_end\\tcount\\n' > ${prefix}.hwe_hist.tsv
    touch ${prefix}.hwe_hist.pdf
    touch ${prefix}.hwe_hist.png
    printf 'report\\tlog10_p_start\\tlog10_p_end\\tcount\\n' > ${prefix}.hwe_hist_window.tsv
    touch ${prefix}.hwe_hist_window.pdf
    touch ${prefix}.hwe_hist_window.png
    Rscript -e 'writeLines(c("\\"${task.process}\\":", paste0("    r-base: ", paste(R.version[["major"]], R.version[["minor"]], sep = ".")), paste0("    r-ggplot2: ", packageVersion("ggplot2")), paste0("    r-data.table: ", packageVersion("data.table"))), "versions.yml")'
    """
}
