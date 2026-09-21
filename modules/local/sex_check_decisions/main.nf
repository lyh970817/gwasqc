process SEX_CHECK_DECISIONS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ac/ac330e254aed1e019ded0a6140463199760e9ee8f1cf398670eb40ccee61ed14/data'
        : 'community.wave.seqera.io/library/r-base_r-ggplot2_r-data.table:785e51271c23bbdc'}"

    input:
    tuple val(meta), path(sexcheck)

    output:
    tuple val(meta), path("${prefix}.sex_mismatch.tsv"), emit: mismatch
    tuple val(meta), path("${prefix}.sex_mismatch_remove.txt"), emit: sample_remove
    tuple val(meta), path("${prefix}.sex_check_hist.tsv"), emit: hist_data
    tuple val(meta), path("${prefix}.sex_check_hist.pdf"), path("${prefix}.sex_check_hist.png"), emit: hist_plot
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // rows are written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations above; the template reads it too.
    prefix = task.ext.prefix ?: "${meta.id}"
    template('sex_check_decisions.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    // The mismatch table carries the report's own columns, so its header is the report's header; when the
    // report is itself a stub's empty file, the header is the one the pinned plink2 writes with `cols=+ycount`.
    """
    if [ -s ${sexcheck} ]; then
        head -n 1 ${sexcheck} | sed 's/^#//' > ${prefix}.sex_mismatch.tsv
    else
        printf 'FID\\tIID\\tPEDSEX\\tSNPSEX\\tSTATUS\\tF\\tYCOUNT\\tYRATE\\n' > ${prefix}.sex_mismatch.tsv
    fi
    touch ${prefix}.sex_mismatch_remove.txt
    printf 'recorded_sex\\tbin_start\\tbin_end\\tcount\\n' > ${prefix}.sex_check_hist.tsv
    touch ${prefix}.sex_check_hist.pdf
    touch ${prefix}.sex_check_hist.png
    Rscript -e 'writeLines(c("\\"${task.process}\\":", paste0("    r-base: ", paste(R.version[["major"]], R.version[["minor"]], sep = ".")), paste0("    r-ggplot2: ", packageVersion("ggplot2")), paste0("    r-data.table: ", packageVersion("data.table"))), "versions.yml")'
    """
}
