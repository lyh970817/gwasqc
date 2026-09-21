process ANCESTRY_HARMONISE {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/1e/1e753f05d15c5dbdb69c91490c0cb0b21388dbcc50da845d0d6263cd11a4bbff/data'
        : 'community.wave.seqera.io/library/r-base:4.3.1--04f3c4b5f283a84a'}"

    input:
    // The reference variant files are staged under `reference/` because a reference fileset may carry the
    // stratum's own basename.
    tuple val(meta), path(plink_variant_file), path(reference_variant_files, stageAs: 'reference/*')

    output:
    tuple val(meta), path("${prefix}.ancestry_harmonised.snplist"), emit: snplist
    tuple val(meta), path("${prefix}.ancestry_flip_update.txt"), emit: flip_update
    tuple val(meta), path("${prefix}.ancestry_harmonisation.tsv"), emit: table
    tuple val(meta), path("${prefix}.ancestry_harmonisation_summary.tsv"), emit: summary
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // row is written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` and `reference_variant_list` must remain visible to the template.
    prefix = task.ext.prefix ?: "${meta.id}"
    reference_variant_list = [reference_variant_files].flatten().collect { file -> file.toString() }.join(' ')
    template('ancestry_harmonise.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.ancestry_harmonised.snplist
    touch ${prefix}.ancestry_flip_update.txt
    printf 'ID\\tCHROM\\tPOS\\tREF_A1\\tREF_A2\\tTARGET_A1\\tTARGET_A2\\tCLASS\\n' > ${prefix}.ancestry_harmonisation.tsv
    printf 'CLASS\\tN\\tRETAINED\\n' > ${prefix}.ancestry_harmonisation_summary.tsv
    printf '"%s":\\n    r-base: %s\\n' '${task.process}' "\$(Rscript -e 'cat(paste(R.version[["major"]], R.version[["minor"]], sep = "."))')" > versions.yml
    """
}
