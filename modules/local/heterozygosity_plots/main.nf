process HETEROZYGOSITY_PLOTS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ac/ac330e254aed1e019ded0a6140463199760e9ee8f1cf398670eb40ccee61ed14/data'
        : 'community.wave.seqera.io/library/r-base_r-ggplot2_r-data.table:785e51271c23bbdc'}"

    input:
    tuple val(meta), path(het), path(sexcheck)

    output:
    tuple val(meta), path("${prefix}.het_hist.tsv"), emit: hist_data
    tuple val(meta), path("${prefix}.het_hist.pdf"), path("${prefix}.het_hist.png"), emit: hist_plot
    tuple val(meta), path("${prefix}.het_sex_scatter.tsv"), emit: scatter_data
    tuple val(meta), path("${prefix}.het_sex_scatter.pdf"), path("${prefix}.het_sex_scatter.png"), emit: scatter_plot
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // rows are written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations above; the template reads it too.
    prefix = task.ext.prefix ?: "${meta.id}"
    template('heterozygosity_plots.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf 'bin_start\\tbin_end\\tcount\\n' > ${prefix}.het_hist.tsv
    touch ${prefix}.het_hist.pdf
    touch ${prefix}.het_hist.png
    printf 'FID\\tIID\\tPEDSEX\\tF_HET\\tF_SEX\\n' > ${prefix}.het_sex_scatter.tsv
    touch ${prefix}.het_sex_scatter.pdf
    touch ${prefix}.het_sex_scatter.png
    Rscript -e 'writeLines(c("\\"${task.process}\\":", paste0("    r-base: ", paste(R.version[["major"]], R.version[["minor"]], sep = ".")), paste0("    r-ggplot2: ", packageVersion("ggplot2")), paste0("    r-data.table: ", packageVersion("data.table"))), "versions.yml")'
    """
}
