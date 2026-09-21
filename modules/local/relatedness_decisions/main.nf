process RELATEDNESS_DECISIONS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ac/ac330e254aed1e019ded0a6140463199760e9ee8f1cf398670eb40ccee61ed14/data'
        : 'community.wave.seqera.io/library/r-base_r-ggplot2_r-data.table:785e51271c23bbdc'}"

    input:
    tuple val(meta), path(kin0), path(smiss), path(mind_remove)
    val indiv_sd
    val po_ibs0_max

    output:
    tuple val(meta), path("${prefix}.relatedness_pairs.tsv"), emit: pairs
    tuple val(meta), path("${prefix}.relatedness_indiv.tsv"), emit: indiv
    tuple val(meta), path("${prefix}.relatedness_remove.txt"), emit: sample_remove
    tuple val(meta), path("${prefix}.relatedness_outliers.txt"), emit: outliers
    tuple val(meta), path("${prefix}.relatedness_hist.tsv"), emit: hist_data
    tuple val(meta), path("${prefix}.relatedness_hist.pdf"), path("${prefix}.relatedness_hist.png"), emit: hist_plot
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // rows are written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` and `mind_remove_file` must remain visible to the template.
    prefix = task.ext.prefix ?: "${meta.id}"
    mind_remove_file = mind_remove ? mind_remove.toString() : ''
    template('relatedness_decisions.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    // The pair table carries the kinship report's own columns and the individual table the ID columns of
    // the missingness report, so both headers are derived from the reports; when a report is itself a stub's
    // empty file, the header is the one the pinned plink2 writes for a fileset with family IDs.
    """
    if [ -s ${kin0} ]; then
        printf '%s\\tDEGREE\\tRELATIONSHIP\\n' "\$(head -n 1 ${kin0} | sed 's/^#//')" > ${prefix}.relatedness_pairs.tsv
    else
        printf 'FID1\\tIID1\\tFID2\\tIID2\\tNSNP\\tHETHET\\tIBS0\\tKINSHIP\\tDEGREE\\tRELATIONSHIP\\n' > ${prefix}.relatedness_pairs.tsv
    fi
    if [ -s ${smiss} ]; then
        printf '%sN_PAIRS_REPORTED\\tMEAN_KINSHIP\\tOUTLIER\\n' "\$(head -n 1 ${smiss} | sed 's/^#//' | tr '\\t' '\\n' | grep -x -e FID -e IID | tr '\\n' '\\t')" > ${prefix}.relatedness_indiv.tsv
    else
        printf 'FID\\tIID\\tN_PAIRS_REPORTED\\tMEAN_KINSHIP\\tOUTLIER\\n' > ${prefix}.relatedness_indiv.tsv
    fi
    touch ${prefix}.relatedness_remove.txt
    touch ${prefix}.relatedness_outliers.txt
    printf 'bin_start\\tbin_end\\tcount\\n' > ${prefix}.relatedness_hist.tsv
    touch ${prefix}.relatedness_hist.pdf
    touch ${prefix}.relatedness_hist.png
    Rscript -e 'writeLines(c("\\"${task.process}\\":", paste0("    r-base: ", paste(R.version[["major"]], R.version[["minor"]], sep = ".")), paste0("    r-ggplot2: ", packageVersion("ggplot2")), paste0("    r-data.table: ", packageVersion("data.table"))), "versions.yml")'
    """
}
